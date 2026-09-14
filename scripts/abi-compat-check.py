#!/usr/bin/env python3
"""
Checks that the current build stays upgrade-compatible with a baseline build.

Both sides are Foundry `out/` directories (the baseline is produced by building an
older release with the same toolchain, see .github/workflows/solidity.yml). This
replaces the Hardhat-based `@celo/contract-compatibility-check` run and keeps its
contract exclusion regex, so the same set of production contracts is covered.

Two things are compared for every non-excluded contract under contracts/:

  storage layout  Every baseline variable must keep its label, slot, offset and
                  type. Struct definitions reachable from the layout must keep
                  their members. New variables are fine as long as they sit past
                  the end of the baseline layout; anything placed inside the
                  baseline region (typically by shrinking a __gap) is reported for
                  manual review because only a human can tell a deliberate gap
                  reservation from an accidental overlap.

  ABI             Every baseline function, event and custom error must still exist
                  with identical inputs and outputs. Comparison is by canonical
                  signature, which is what the selector and the event topic are
                  derived from. Additions are fine.

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

ERROR = "ERROR"
REVIEW = "REVIEW"


def normalize_type(type_id):
    return AST_ID.sub(r"\1", type_id)


def load_artifacts(out_dir, exclude, source_prefix):
    """Maps contract name -> artifact for the compiled sources under source_prefix."""
    artifacts = {}
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
            target = artifact.get("metadata", {}).get("settings", {}).get("compilationTarget")
            if not target:
                continue
            source, name = next(iter(target.items()))
            if not source.startswith(source_prefix) or exclude.search(name):
                continue
            artifacts[name] = artifact
    return artifacts


def slot_span(entry, types):
    """Number of slots the variable occupies, starting at its own slot."""
    size = int(types.get(entry["type"], {}).get("numberOfBytes", 32))
    return max(1, -(-size // 32))


def layout_end(storage, types):
    return max((int(e["slot"]) + slot_span(e, types) for e in storage), default=0)


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


def array_length(label):
    match = re.fullmatch(r".*\[(\d+)\]", label)
    return int(match.group(1)) if match else None


def check_type(name, base_id, base_types, cur_id, cur_types, findings, seen):
    """Compares two type definitions and everything reachable from them.

    Both sides are walked in lockstep so each identifier is resolved in its own
    types map; nothing is ever looked up across builds, where the AST ids differ.
    """
    if (base_id, cur_id) in seen:
        return
    seen.add((base_id, cur_id))

    base_type, cur_type = base_types.get(base_id), cur_types.get(cur_id)
    if base_type is None or cur_type is None:
        return

    for key in ("base", "key", "value"):
        if key in base_type and key in cur_type:
            check_type(name, base_type[key], base_types, cur_type[key], cur_types, findings, seen)

    base_members = base_type.get("members")
    if base_members is None:
        return
    label = base_type.get("label", base_id)
    cur_members = cur_type.get("members")
    if cur_members is None:
        findings.append((ERROR, name, f"{label} is no longer a struct"))
        return

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
            check_type(name, base_member["type"], base_types, cur_member["type"], cur_types, findings, seen)

    if len(cur_members) > len(base_members):
        added = ", ".join(m["label"] for m in cur_members[len(base_members) :])
        findings.append(
            (
                REVIEW,
                name,
                f"{label} gained member(s) {added}; safe only where the struct is "
                "reached through a mapping or a dynamic array",
            )
        )


def check_storage(name, baseline, current, findings):
    base_layout = baseline.get("storageLayout") or {"storage": [], "types": {}}
    cur_layout = current.get("storageLayout") or {"storage": [], "types": {}}
    base_storage, base_types = base_layout["storage"], base_layout.get("types") or {}
    cur_storage, cur_types = cur_layout["storage"], cur_layout.get("types") or {}

    seen_structs = set()

    # Variables are compared by position, not by name: labels repeat (every
    # inherited upgradeable contract brings its own __gap) and solc emits the
    # layout in slot order, so position is the only stable identity.
    for index, base_entry in enumerate(base_storage):
        label = base_entry["label"]
        if index >= len(cur_storage):
            findings.append((ERROR, name, f"variable {label} (slot {base_entry['slot']}) was removed"))
            continue
        cur_entry = cur_storage[index]
        if cur_entry["label"] != label:
            findings.append(
                (
                    ERROR,
                    name,
                    f"slot {base_entry['slot']}+{base_entry['offset']} held {label}, now holds "
                    f"{cur_entry['label']} (slot {cur_entry['slot']}+{cur_entry['offset']})",
                )
            )
            continue
        if cur_entry["slot"] != base_entry["slot"] or cur_entry["offset"] != base_entry["offset"]:
            findings.append(
                (
                    ERROR,
                    name,
                    f"variable {label} moved from slot {base_entry['slot']}+{base_entry['offset']} "
                    f"to slot {cur_entry['slot']}+{cur_entry['offset']}",
                )
            )
        base_type = type_label(base_entry["type"], base_types)
        cur_type = type_label(cur_entry["type"], cur_types)
        if base_type != cur_type:
            base_len, cur_len = array_length(base_type), array_length(cur_type)
            shrunk_gap = is_gap(base_entry) and base_len is not None and cur_len is not None and cur_len < base_len
            findings.append(
                (
                    REVIEW if shrunk_gap else ERROR,
                    name,
                    f"reserved gap {label} shrank from {base_len} to {cur_len} slots; the freed "
                    "slots must hold the newly added variables"
                    if shrunk_gap
                    else f"variable {label} changed type from {base_type} to {cur_type}",
                )
            )
        else:
            check_type(name, base_entry["type"], base_types, cur_entry["type"], cur_types, findings, seen_structs)

    base_end = layout_end(base_storage, base_types)
    for cur_entry in cur_storage[len(base_storage) :]:
        if int(cur_entry["slot"]) >= base_end:
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


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--baseline", required=True, help="Foundry out/ directory of the baseline build")
    parser.add_argument("--current", default="out", help="Foundry out/ directory of the current build")
    parser.add_argument("--exclude", default=DEFAULT_EXCLUDE, help="contract names to skip")
    parser.add_argument("--source-prefix", default="contracts/", help="only check sources under this prefix")
    parser.add_argument("-v", "--verbose", action="store_true", help="list compatible contracts too")
    args = parser.parse_args()

    for directory in (args.baseline, args.current):
        if not os.path.isdir(directory):
            sys.exit(f"not a directory: {directory} (run `forge build` first)")

    exclude = re.compile(args.exclude)
    baseline = load_artifacts(args.baseline, exclude, args.source_prefix)
    current = load_artifacts(args.current, exclude, args.source_prefix)
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
            check_storage(name, baseline[name], current[name], findings)
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
