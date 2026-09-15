#!/usr/bin/env python3
"""
Checks that the current build stays upgrade-compatible with a baseline build.

Both sides are Foundry `out/` directories (the baseline is produced by building an
older release with the same toolchain, see .github/workflows/solidity.yml). This
replaces the Hardhat-based `@celo/contract-compatibility-check` run and keeps its
contract exclusion regex, so the same set of production contracts is covered.

Two things are compared for every non-excluded contract under contracts/:

  storage layout  Every baseline variable must keep its label, slot, offset and
                  type. Variables are matched by the slot and offset they occupy,
                  never by their position in the list, so the standard way of
                  adding one to an upgradeable contract - declaring it in front of
                  a __gap and shortening the gap by what it takes - reads as the
                  gap being consumed rather than as every variable behind it being
                  renamed. Struct definitions reachable from the layout must keep
                  their members, and enum definitions must keep the order of
                  theirs: the layout only records that a slot holds a one byte
                  enum, not what its values stand for. New variables are fine as
                  long as they sit past the end of the baseline layout; anything
                  placed inside the baseline region (typically by shrinking a
                  __gap) is reported for manual review because only a human can
                  tell a deliberate gap reservation from an accidental overlap.

                  Growing a type is only free where nothing sits behind it. Array
                  elements are stored back to back from the array's base slot, so
                  the element's size is the stride: growing it moves every element
                  after the first one and silently reinterprets the state that is
                  already there. Growth anywhere below an array element - directly,
                  or through a struct member of one - is therefore an error, while
                  growth of a mapping value stays a review item, because every
                  mapping entry starts at its own hash. An array element that gains
                  a member without growing - the member fits into padding the
                  element already carried - moves nothing and stays a review item.

  ABI             Every baseline function, event and custom error must still exist
                  with identical inputs and outputs. Comparison is by canonical
                  signature, which is what the selector and the event topic are
                  derived from. The receive() and fallback() handlers carry no
                  signature and are compared on their own: dropping either, or its
                  payable flag, turns a plain transfer into a revert. Additions are
                  fine.

Findings come in two flavours: ERROR (breaks a deployed proxy, exit status 1) and
REVIEW (legal in principle but a human has to confirm the intent, exit status 0).

Usage:
  scripts/abi-compat-check.py --baseline /path/to/release/out --current out
"""
import argparse
import json
import os
import re
import sys

# Same exclusion regex the Hardhat compatibility job used: mocks, test helpers,
# interfaces, proxies and the contracts inherited from the Celo monorepo are not
# deployed behind a proxy, so their layout and ABI may change freely.
DEFAULT_EXCLUDE = r".*Test|Mock.*|I[A-Z].*|.*Proxy|ReleaseGold|SlasherUtil|UsingPrecompiles|^UsingRegistry|ERC20.*|^Managed$"

# solc appends the declaration's AST id to struct, enum, contract and user defined
# value type identifiers. The id shifts whenever anything above the declaration
# moves, so it carries no layout information and has to go before comparing.
# The number in t_array(...)N_storage is the array length and must be kept.
AST_ID = re.compile(r"(t_(?:struct|enum|contract|userDefinedValueType)\([^)]*\))\d+")

# The declared name inside an enum type identifier, `Status` in t_enum(Status)42.
# Unlike the layout's label it is not qualified by the declaring contract.
ENUM_TYPE = re.compile(r"t_enum\(([^)]*)\)")

ERROR = "ERROR"
REVIEW = "REVIEW"


def normalize_type(type_id):
    return AST_ID.sub(r"\1", type_id)


def enum_definitions(ast):
    """Yields (qualified name, member names) for every enum of one source unit AST.

    Solidity only allows an enum at file or contract level, so the two outermost
    node lists are the whole search space - no need to walk the statement trees.
    `canonicalName` is what the storage layout's label spells out ("Vault.Status"),
    and is just the declared name for a file level enum.
    """
    for node in (ast or {}).get("nodes") or []:
        for candidate in (node, *(node.get("nodes") or [])):
            if candidate.get("nodeType") != "EnumDefinition":
                continue
            name = candidate.get("canonicalName") or candidate.get("name")
            if name:
                yield name, [member.get("name") for member in candidate.get("members") or []]


def lookup_enum(enums, label):
    """Member list of an enum, or None when the build does not pin it down.

    The layout's label is qualified, the type identifier is not, so the lookup falls
    back to the declared name. Several contracts may declare the same name; that is
    only good enough while they all declare the same members.
    """
    if label in enums:
        return enums[label]
    declared = label.rsplit(".", 1)[-1]
    matches = [members for name, members in enums.items() if name.rsplit(".", 1)[-1] == declared]
    if matches and all(members == matches[0] for members in matches):
        return matches[0]
    return None


def load_artifacts(out_dir, exclude, source_prefix):
    """Maps contract name -> artifact for the compiled sources under source_prefix.

    Returns the enum definitions of the whole build alongside, the excluded sources
    included: an enum a checked contract stores is often declared by an interface or
    by one of the inherited OpenZeppelin contracts, whose own layout is not checked.
    """
    artifacts, enums = {}, {}
    for root, dirs, files in os.walk(out_dir):
        dirs[:] = [d for d in dirs if d != "build-info"]
        for filename in files:
            # Foundry names the artifact <Contract>.json, or <Contract>.default.json
            # when the contract is also built under one of the additional compiler
            # profiles. Only the default profile describes what gets deployed.
            if not filename.endswith(".json"):
                continue
            stem, _, profile = filename[: -len(".json")].partition(".")
            if profile and (profile != "default" or f"{stem}.json" in files):
                continue
            with open(os.path.join(root, filename)) as f:
                artifact = json.load(f)
            enums.update(enum_definitions(artifact.get("ast")))
            target = artifact.get("metadata", {}).get("settings", {}).get("compilationTarget")
            if not target:
                continue
            source, name = next(iter(target.items()))
            if not source.startswith(source_prefix) or exclude.search(name):
                continue
            artifacts[name] = artifact
    return artifacts, enums


def slot_span(entry, types):
    """Number of slots the variable occupies, starting at its own slot."""
    size = int(types.get(entry["type"], {}).get("numberOfBytes", 32))
    return max(1, -(-size // 32))


def layout_end(storage, types):
    return max((int(e["slot"]) + slot_span(e, types) for e in storage), default=0)


def position(entry):
    """The (slot, offset) a variable sits at - its only identity across builds."""
    return int(entry["slot"]), int(entry["offset"])


def is_gap(entry):
    return entry["label"].startswith("__gap")


def type_label(type_id, types):
    """Canonical name of a type identifier, free of AST ids.

    solc's own `label` is fully qualified ("struct SortedLinkedList.List"), which
    the identifier is not: two different libraries in the same layout can both
    define a `List`, so the identifier alone is ambiguous even after stripping the
    AST id. Fall back to the stripped identifier for types with no entry.
    """
    definition = types.get(type_id) or {}
    return definition.get("label") or normalize_type(type_id)


def enum_label(type_id, definition):
    """Qualified name of an enum type, e.g. `Vault.Status`, or None for other types."""
    if not type_id.startswith("t_enum("):
        return None
    label = (definition or {}).get("label") or ""
    if label.startswith("enum "):
        return label[len("enum ") :]
    match = ENUM_TYPE.match(type_id)
    return match.group(1) if match else None


def array_length(label):
    match = re.fullmatch(r".*\[(\d+)\]", label)
    return int(match.group(1)) if match else None


def type_size(definition):
    return int(definition.get("numberOfBytes", 32))


def check_type(name, base_id, base_types, cur_id, cur_types, findings, seen, enums, stride, path):
    """Compares two type definitions and everything reachable from them.

    Both sides are walked in lockstep so each identifier is resolved in its own
    types map; nothing is ever looked up across builds, where the AST ids differ.

    `stride` says whether the size of this type decides where other data lives,
    which is what turns a growth from a review item into an error. It is set when
    descending into an array's element type and stays set for everything that
    contributes to that element's size (its struct members, and their members in
    turn). It is cleared again under a mapping value, whose entries are each
    addressed by their own hash and so have nothing sitting behind them.

    `enums` collects the enum types the walk reaches, keyed by the pair of names the
    two sides know them under, so their members can be compared against the ASTs
    afterwards. The layout itself says no more than "one byte", so a reordered enum
    is invisible here.

    `path` is the access path the type was reached by, e.g. `withdrawals[key][i]`,
    and only serves to make the findings readable.
    """
    if (base_id, cur_id, stride) in seen:
        return
    seen.add((base_id, cur_id, stride))

    base_type, cur_type = base_types.get(base_id), cur_types.get(cur_id)
    if base_type is None or cur_type is None:
        return

    before = len(findings)

    base_enum = enum_label(base_id, base_type)
    if base_enum:
        enums.setdefault((base_enum, enum_label(cur_id, cur_type)), path)

    # Only array types carry a `base`, both the static t_array(...)N_storage and
    # the dynamic t_array(...)dyn_storage kind: in either the elements are packed
    # one after another, so the element size is the distance between them.
    if "base" in base_type and "base" in cur_type:
        check_type(
            name, base_type["base"], base_types, cur_type["base"], cur_types, findings, seen, enums, True, f"{path}[i]"
        )
    if "value" in base_type and "value" in cur_type:
        check_type(
            name,
            base_type["value"],
            base_types,
            cur_type["value"],
            cur_types,
            findings,
            seen,
            enums,
            False,
            f"{path}[key]",
        )
    # The key decides which slot an entry hashes to, so an enum used as one carries
    # the same meaning as an enum that is stored. Nothing else about a key can move.
    if "key" in base_type and "key" in cur_type:
        check_type(
            name, base_type["key"], base_types, cur_type["key"], cur_types, findings, seen, enums, False, f"{path}[key]"
        )

    label = base_type.get("label", base_id)
    base_members = base_type.get("members")
    cur_members = cur_type.get("members")
    if base_members is not None and cur_members is None:
        findings.append((ERROR, name, f"{label} is no longer a struct"))
        return

    if base_members is not None:
        for index, base_member in enumerate(base_members):
            if index >= len(cur_members):
                findings.append((ERROR, name, f"{label}: member {base_member['label']} was removed"))
                continue
            cur_member = cur_members[index]
            base_member_type = type_label(base_member["type"], base_types)
            cur_member_type = type_label(cur_member["type"], cur_types)
            if base_member["label"] != cur_member["label"]:
                findings.append(
                    (
                        ERROR,
                        name,
                        f"{label}: slot {base_member['slot']} was {base_member['label']}, "
                        f"is now {cur_member['label']}",
                    )
                )
            elif base_member_type != cur_member_type:
                findings.append(
                    (
                        ERROR,
                        name,
                        f"{label}: member {base_member['label']} changed type from "
                        f"{base_member_type} to {cur_member_type}",
                    )
                )
            elif base_member["slot"] != cur_member["slot"] or base_member["offset"] != cur_member["offset"]:
                findings.append(
                    (
                        ERROR,
                        name,
                        f"{label}: member {base_member['label']} moved from "
                        f"slot {base_member['slot']}+{base_member['offset']} to "
                        f"slot {cur_member['slot']}+{cur_member['offset']}",
                    )
                )
            else:
                check_type(
                    name,
                    base_member["type"],
                    base_types,
                    cur_member["type"],
                    cur_types,
                    findings,
                    seen,
                    enums,
                    stride,
                    f"{path}.{base_member['label']}",
                )

        if len(cur_members) > len(base_members):
            added = ", ".join(m["label"] for m in cur_members[len(base_members) :])
            # An array element only moves the elements behind it when it actually
            # gets wider. Members that fit into the padding the element already
            # carried (a second uint128 next to the first) leave the stride alone.
            if stride and type_size(base_type) != type_size(cur_type):
                level = ERROR
                message = (
                    f"{label} gained member(s) {added} at {path}; it is an array element, so every "
                    "element behind the first one moves and existing entries are misread"
                )
            elif stride:
                level = REVIEW
                message = (
                    f"{label} gained member(s) {added} at {path}; it is an array element, but it still "
                    f"measures {type_size(cur_type)} bytes, so the member(s) were appended within padding "
                    "and no element moves - confirm those bytes were never written"
                )
            else:
                level = REVIEW
                message = (
                    f"{label} gained member(s) {added} at {path}; not an array element (a mapping "
                    "value starts at its own hash, a top level struct is followed by free slots), so "
                    "existing entries keep their meaning - confirm the slots it grows into are unused"
                )
            findings.append((level, name, message))

    # Catches the size changes the member walk above cannot see, e.g. a fixed array
    # member whose element type grew. Skipped when something below already reported,
    # because that finding is the same growth, named at the place it happens.
    if stride and type_size(base_type) != type_size(cur_type) and len(findings) == before:
        findings.append(
            (
                ERROR,
                name,
                f"{label} at {path} grew from {type_size(base_type)} to {type_size(cur_type)} bytes; "
                "it is an array element, so every element behind the first one moves and existing "
                "entries are misread",
            )
        )


def check_enums(name, reached, base_enums, cur_enums, findings):
    """Compares the member lists of the enums the layout walk reached.

    An enum is one byte in the layout whatever its members are, so reordering them
    or inserting one in front silently changes what the values already in storage
    mean. The member lists only exist in the ASTs, which is why they are looked up
    per build and by name.
    """
    for (base_name, cur_name), path in sorted(reached.items()):
        base_members = lookup_enum(base_enums, base_name)
        cur_members = lookup_enum(cur_enums, cur_name or base_name)
        missing = [
            side for side, members in (("baseline", base_members), ("current", cur_members)) if members is None
        ]
        if missing:
            findings.append(
                (
                    REVIEW,
                    name,
                    f"enum {base_name} at {path} is not in the {' or the '.join(missing)} build's ASTs; "
                    "the order of its members could not be compared",
                )
            )
            continue
        for index, member in enumerate(base_members):
            if index >= len(cur_members):
                findings.append((ERROR, name, f"enum {base_name}: member {member} (value {index}) was removed"))
            elif cur_members[index] != member:
                findings.append(
                    (ERROR, name, f"enum {base_name}: value {index} was {member}, is now {cur_members[index]}")
                )
        if len(cur_members) > len(base_members):
            added = ", ".join(cur_members[len(base_members) :])
            findings.append(
                (
                    REVIEW,
                    name,
                    f"enum {base_name} gained member(s) {added} at the end; the values already stored keep "
                    "their meaning - confirm nothing switches on the member count",
                )
            )


def check_gaps(name, base_storage, base_types, cur_storage, cur_types, findings):
    """Reports what became of the slots a baseline __gap reserved.

    Adding a variable to an upgradeable contract means spending gap slots: the new
    variable is declared in front of the __gap and the gap is shortened by what the
    variable takes, so nothing behind it moves. Both spellings of that show up here,
    the gap staying put and getting shorter, and the gap being pushed back by the new
    variables, and both are review items - only a human can tell a deliberate
    reservation from an accidental overlap. What is not allowed is the replacement
    reaching past the last slot the gap reserved, because then the layout behind it
    moves after all.
    """
    cur_at = {position(entry): entry for entry in cur_storage}
    for base_entry in base_storage:
        if not is_gap(base_entry):
            continue
        label, start = base_entry["label"], int(base_entry["slot"])
        end = start + slot_span(base_entry, base_types)
        fillers = [entry for entry in cur_storage if start <= int(entry["slot"]) < end]
        reach = max((int(e["slot"]) + slot_span(e, cur_types) for e in fillers), default=end)
        if reach > end:
            findings.append(
                (
                    ERROR,
                    name,
                    f"the {end - start} slot(s) reserved by {label} at slot {start} now hold data reaching "
                    f"to slot {reach}; everything behind the gap moves",
                )
            )
            continue

        cur_entry = cur_at.get(position(base_entry))
        if cur_entry is not None and is_gap(cur_entry):
            # The gap kept its first slot, so only its length can have changed.
            base_type = type_label(base_entry["type"], base_types)
            cur_type = type_label(cur_entry["type"], cur_types)
            if base_type == cur_type:
                continue
            base_len, cur_len = array_length(base_type), array_length(cur_type)
            if base_len is None or cur_len is None or cur_len > base_len:
                findings.append((ERROR, name, f"variable {label} changed type from {base_type} to {cur_type}"))
            else:
                findings.append(
                    (
                        REVIEW,
                        name,
                        f"reserved gap {label} shrank from {base_len} to {cur_len} slots; the freed "
                        "slots must hold the newly added variables",
                    )
                )
            continue

        # The gap no longer starts where it did: new variables took its first slots
        # and the remainder of the gap, if any, was pushed back behind them.
        consumed = (end - start) - sum(slot_span(e, cur_types) for e in fillers if is_gap(e))
        findings.append(
            (
                REVIEW,
                name,
                f"reserved gap {label} at slot {start} consumed {consumed} gap slot(s); the rest of the "
                f"layout stays put, confirm the {consumed} slot(s) were never written",
            )
        )


def check_storage(name, baseline, current, base_enums, cur_enums, findings):
    base_layout = baseline.get("storageLayout") or {"storage": [], "types": {}}
    cur_layout = current.get("storageLayout") or {"storage": [], "types": {}}
    base_storage, base_types = base_layout["storage"], base_layout.get("types") or {}
    cur_storage, cur_types = cur_layout["storage"], cur_layout.get("types") or {}

    seen_structs, reached_enums = set(), {}
    cur_at = {position(entry): entry for entry in cur_storage}

    # Variables are matched by the slot and offset they occupy, never by their index
    # in the list: labels repeat (every inherited upgradeable contract brings its own
    # __gap) and a variable added in front of a __gap shifts the index of everything
    # behind it without moving a byte of state. The gaps themselves are left to
    # check_gaps, which is the only place where a replacement is legitimate.
    for base_entry in base_storage:
        if is_gap(base_entry):
            continue
        label = base_entry["label"]
        cur_entry = cur_at.get(position(base_entry))
        if cur_entry is None:
            moved = next((e for e in cur_storage if e["label"] == label and not is_gap(e)), None)
            if moved is None:
                findings.append((ERROR, name, f"variable {label} (slot {base_entry['slot']}) was removed"))
            else:
                findings.append(
                    (
                        ERROR,
                        name,
                        f"variable {label} moved from slot {base_entry['slot']}+{base_entry['offset']} "
                        f"to slot {moved['slot']}+{moved['offset']}",
                    )
                )
            continue
        if cur_entry["label"] != label:
            findings.append(
                (
                    ERROR,
                    name,
                    f"slot {base_entry['slot']}+{base_entry['offset']} held {label}, now holds "
                    f"{cur_entry['label']}",
                )
            )
            continue
        base_type = type_label(base_entry["type"], base_types)
        cur_type = type_label(cur_entry["type"], cur_types)
        if base_type != cur_type:
            findings.append((ERROR, name, f"variable {label} changed type from {base_type} to {cur_type}"))
        else:
            # A top level variable has no stride of its own: anything that grows
            # behind it shows up as the next variable having moved.
            check_type(
                name,
                base_entry["type"],
                base_types,
                cur_entry["type"],
                cur_types,
                findings,
                seen_structs,
                reached_enums,
                False,
                label,
            )

    check_gaps(name, base_storage, base_types, cur_storage, cur_types, findings)
    check_enums(name, reached_enums, base_enums, cur_enums, findings)

    base_at = {position(entry) for entry in base_storage}
    base_end = layout_end(base_storage, base_types)
    for cur_entry in cur_storage:
        # A gap that moved is reported by check_gaps, as part of the gap it came from.
        if is_gap(cur_entry) or position(cur_entry) in base_at or int(cur_entry["slot"]) >= base_end:
            continue
        findings.append(
            (
                REVIEW,
                name,
                f"new variable {cur_entry['label']} sits at slot {cur_entry['slot']}, inside the "
                f"baseline layout (which ends at slot {base_end}); confirm it only consumes gap space",
            )
        )


def canonical_type(item):
    if item["type"].startswith("tuple"):
        inner = ",".join(canonical_type(c) for c in item.get("components", []))
        return f"({inner}){item['type'][len('tuple'):]}"
    return item["type"]


def signature(entry):
    return f"{entry.get('name', '')}({','.join(canonical_type(i) for i in entry.get('inputs', []))})"


def outputs(entry):
    return ",".join(canonical_type(o) for o in entry.get("outputs", []))


def indexed_flags(entry):
    return [bool(i.get("indexed")) for i in entry.get("inputs", [])]


def abi_index(abi, kind):
    return {signature(e): e for e in abi if e.get("type") == kind}


def check_mutability(name, sig, base, cur, findings):
    base_mutability = base.get("stateMutability", "nonpayable")
    cur_mutability = cur.get("stateMutability", "nonpayable")
    if base_mutability == cur_mutability:
        return
    read_only = ("view", "pure")
    breaking = (base_mutability in read_only and cur_mutability not in read_only) or (
        base_mutability == "payable" and cur_mutability != "payable"
    )
    findings.append(
        (
            ERROR if breaking else REVIEW,
            name,
            f"function {sig} changed mutability from {base_mutability} to {cur_mutability}",
        )
    )


def check_handler(name, kind, base_abi, cur_abi, findings):
    """Compares the receive() or fallback() handler, which has no signature.

    Both are unnamed and take no arguments, so they cannot be keyed like the rest of
    the ABI and a contract has at most one of each. Losing the handler turns every
    plain transfer into a revert, and so does dropping its payable flag; a handler
    that was not payable and becomes one changes what a transfer does just as much,
    so any change at all is reported.
    """
    base_entry = next((e for e in base_abi if e.get("type") == kind), None)
    if base_entry is None:
        return
    cur_entry = next((e for e in cur_abi if e.get("type") == kind), None)
    if cur_entry is None:
        findings.append((ERROR, name, f"{kind}() was removed"))
        return
    base_mutability = base_entry.get("stateMutability", "nonpayable")
    cur_mutability = cur_entry.get("stateMutability", "nonpayable")
    if base_mutability != cur_mutability:
        findings.append(
            (ERROR, name, f"{kind}() changed mutability from {base_mutability} to {cur_mutability}")
        )


def check_abi(name, baseline, current, findings):
    base_abi, cur_abi = baseline.get("abi", []), current.get("abi", [])

    base_functions, cur_functions = abi_index(base_abi, "function"), abi_index(cur_abi, "function")
    for sig, base_entry in sorted(base_functions.items()):
        cur_entry = cur_functions.get(sig)
        if cur_entry is None:
            findings.append((ERROR, name, f"function {sig} was removed"))
            continue
        if outputs(base_entry) != outputs(cur_entry):
            findings.append(
                (
                    ERROR,
                    name,
                    f"function {sig} returns ({outputs(cur_entry)}) instead of ({outputs(base_entry)})",
                )
            )
        check_mutability(name, sig, base_entry, cur_entry, findings)

    for kind in ("receive", "fallback"):
        check_handler(name, kind, base_abi, cur_abi, findings)

    base_events, cur_events = abi_index(base_abi, "event"), abi_index(cur_abi, "event")
    for sig, base_entry in sorted(base_events.items()):
        cur_entry = cur_events.get(sig)
        if cur_entry is None:
            findings.append((ERROR, name, f"event {sig} was removed"))
        elif indexed_flags(base_entry) != indexed_flags(cur_entry):
            findings.append((ERROR, name, f"event {sig} changed which arguments are indexed"))
        elif bool(base_entry.get("anonymous")) != bool(cur_entry.get("anonymous")):
            findings.append((ERROR, name, f"event {sig} changed its anonymous flag"))

    base_errors, cur_errors = abi_index(base_abi, "error"), abi_index(cur_abi, "error")
    for sig in sorted(base_errors):
        if sig not in cur_errors:
            findings.append((ERROR, name, f"error {sig} was removed"))


def report(results, errors, reviews, verbose):
    width = max((len(name) for name, _ in results), default=8)
    rows = []
    for name, contract_findings in results:
        contract_errors = sum(1 for level, _, _ in contract_findings if level == ERROR)
        contract_reviews = len(contract_findings) - contract_errors
        if contract_errors:
            rows.append((name, f"{contract_errors} error(s)"))
        elif contract_reviews:
            rows.append((name, f"{contract_reviews} to review"))
        elif verbose:
            rows.append((name, "ok"))
    if rows:
        print(f"\n{'contract':<{width}}  status")
        for name, status in rows:
            print(f"{name:<{width}}  {status}")

    for level, bucket in ((ERROR, errors), (REVIEW, reviews)):
        if not bucket:
            continue
        print(f"\n{level}S" if level == ERROR else f"\n{level} (not fatal, confirm by hand)")
        for _, name, message in bucket:
            print(f"  {name}: {message}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--baseline", required=True, help="Foundry out/ directory of the baseline build")
    parser.add_argument("--current", default="out", help="Foundry out/ directory of the current build")
    parser.add_argument("--exclude", default=DEFAULT_EXCLUDE, help="contract names to skip")
    parser.add_argument("--source-prefix", default="contracts/", help="only check sources under this prefix")
    parser.add_argument("-v", "--verbose", action="store_true", help="list compatible contracts too")
    args = parser.parse_args(argv)

    for directory in (args.baseline, args.current):
        if not os.path.isdir(directory):
            sys.exit(f"not a directory: {directory} (run `forge build` first)")

    exclude = re.compile(args.exclude)
    baseline, base_enums = load_artifacts(args.baseline, exclude, args.source_prefix)
    current, cur_enums = load_artifacts(args.current, exclude, args.source_prefix)
    if not baseline:
        sys.exit(f"no contracts found under {args.baseline}; is it a Foundry out/ directory?")

    print(f"baseline: {args.baseline} ({len(baseline)} contracts)")
    print(f"current:  {args.current} ({len(current)} contracts)")

    results, errors, reviews = [], [], []
    for name in sorted(baseline):
        findings = []
        if name not in current:
            findings.append((ERROR, name, "contract is gone from the current build"))
        else:
            check_storage(name, baseline[name], current[name], base_enums, cur_enums, findings)
            check_abi(name, baseline[name], current[name], findings)
        results.append((name, findings))
        errors.extend(f for f in findings if f[0] == ERROR)
        reviews.extend(f for f in findings if f[0] == REVIEW)

    added = sorted(set(current) - set(baseline))
    if added:
        print(f"new contracts (not checked): {', '.join(added)}")

    report(results, errors, reviews, args.verbose)

    if errors:
        print(f"\n{len(errors)} incompatibility(ies) across {len({e[1] for e in errors})} contract(s)")
        sys.exit(1)
    print(f"\ncompatible with the baseline ({len(reviews)} item(s) flagged for review)")


if __name__ == "__main__":
    main()
