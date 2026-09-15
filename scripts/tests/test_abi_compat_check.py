#!/usr/bin/env python3
"""Regression tests for scripts/abi-compat-check.py.

Each test builds a pair of minimal Foundry `out/` directories in a temp dir - just
enough of an artifact for the checker to pick it up - and runs the real entry point
over them, so the exit status and the report are covered along with the comparison.

Run with:  python3 -m unittest discover -s scripts/tests -p 'test_*.py'
"""
import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

CHECKER = Path(__file__).resolve().parent.parent / "abi-compat-check.py"
_spec = importlib.util.spec_from_file_location("abi_compat_check", CHECKER)
checker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(checker)

UINT256 = {"encoding": "inplace", "label": "uint256", "numberOfBytes": "32"}
UINT128 = {"encoding": "inplace", "label": "uint128", "numberOfBytes": "16"}
ADDRESS = {"encoding": "inplace", "label": "address", "numberOfBytes": "20"}

GAP_TYPE = "t_array(t_uint256){}_storage"

ABI = [
    {
        "type": "function",
        "name": "deposit",
        "inputs": [{"name": "amount", "type": "uint256"}],
        "outputs": [],
        "stateMutability": "nonpayable",
    },
    {
        "type": "event",
        "name": "Deposited",
        "inputs": [{"name": "who", "type": "address", "indexed": True}],
        "anonymous": False,
    },
]

RECEIVE = {"type": "receive", "stateMutability": "payable"}
PAYABLE_FALLBACK = {"type": "fallback", "stateMutability": "payable"}
PLAIN_FALLBACK = {"type": "fallback", "stateMutability": "nonpayable"}


def slot_entry(label, slot, type_id, offset=0):
    """One entry of storageLayout.storage, or one struct member; solc shapes them alike."""
    return {"label": label, "slot": str(slot), "offset": offset, "type": type_id}


def artifact(name, storage, types, abi=ABI, ast=None):
    content = {
        "metadata": {"settings": {"compilationTarget": {f"contracts/{name}.sol": name}}},
        "storageLayout": {"storage": list(storage), "types": dict(types)},
        "abi": list(abi),
    }
    if ast is not None:
        content["ast"] = ast
    return content


def gap_types(*lengths):
    """Types map carrying a uint256[N] for every gap length the fixture spells out."""
    types = {"t_uint256": UINT256, "t_address": ADDRESS}
    for length in lengths:
        types[GAP_TYPE.format(length)] = {
            "encoding": "inplace",
            "label": f"uint256[{length}]",
            "numberOfBytes": str(32 * length),
            "base": "t_uint256",
        }
    return types


def enum_ast(contract, enum, members):
    """A source unit AST holding one contract level enum, shaped the way solc emits it."""
    return {
        "nodeType": "SourceUnit",
        "nodes": [
            {
                "nodeType": "ContractDefinition",
                "name": contract,
                "nodes": [
                    {
                        "nodeType": "EnumDefinition",
                        "name": enum,
                        "canonicalName": f"{contract}.{enum}",
                        "members": [{"nodeType": "EnumValue", "name": member} for member in members],
                    }
                ],
            }
        ],
    }


def enum_vault(members, ast_id, nested=False, with_ast=True):
    """A Vault storing a `Status`, either directly or as a member of a struct.

    The layout says no more than "one byte" either way, so the member list has to come
    from the AST - which is what `with_ast` can withhold.
    """
    enum_id = f"t_enum(Status){ast_id}"
    types = {
        "t_uint256": UINT256,
        enum_id: {"encoding": "inplace", "label": "enum Vault.Status", "numberOfBytes": "1"},
    }
    if nested:
        struct_id = f"t_struct(Entry){ast_id}_storage"
        types[struct_id] = {
            "encoding": "inplace",
            "label": "struct Vault.Entry",
            "numberOfBytes": "64",
            "members": [slot_entry("amount", 0, "t_uint256"), slot_entry("status", 1, enum_id)],
        }
        storage = [slot_entry("entry", 0, struct_id)]
    else:
        storage = [slot_entry("status", 0, enum_id)]
    return artifact("Vault", storage, types, ast=enum_ast("Vault", "Status", members) if with_ast else None)


def value_type_ast(contract, value_type, underlying):
    """A source unit AST holding one `type Amount is uint256`, shaped the way solc emits it."""
    return {
        "nodeType": "SourceUnit",
        "nodes": [
            {
                "nodeType": "ContractDefinition",
                "name": contract,
                "nodes": [
                    {
                        "nodeType": "UserDefinedValueTypeDefinition",
                        "name": value_type,
                        "canonicalName": f"{contract}.{value_type}",
                        "underlyingType": {
                            "nodeType": "ElementaryTypeName",
                            "name": underlying,
                            "typeDescriptions": {
                                "typeIdentifier": f"t_{underlying}",
                                "typeString": underlying,
                            },
                        },
                    }
                ],
            }
        ],
    }


def value_type_vault(underlying, ast_id, shape="direct", with_ast=True):
    """A Vault storing an `Amount`: on its own, as a struct member or as a mapping key.

    solc writes out the same `t_userDefinedValueType(Amount)<id>` of the same width for
    every underlying type of that width, and labels it with the canonical name either
    way, so what `Amount` wraps shows up in the AST only - which is what `with_ast` can
    withhold.
    """
    value_id = f"t_userDefinedValueType(Amount){ast_id}"
    types = {
        "t_uint256": UINT256,
        value_id: {"encoding": "inplace", "label": "Vault.Amount", "numberOfBytes": "32"},
    }
    if shape == "struct_member":
        struct_id = f"t_struct(Entry){ast_id}_storage"
        types[struct_id] = {
            "encoding": "inplace",
            "label": "struct Vault.Entry",
            "numberOfBytes": "64",
            "members": [slot_entry("amount", 0, value_id), slot_entry("fee", 1, "t_uint256")],
        }
        storage = [slot_entry("entry", 0, struct_id)]
    elif shape == "mapping_key":
        mapping_id = f"t_mapping({value_id},t_uint256)"
        types[mapping_id] = {
            "encoding": "mapping",
            "label": "mapping(Vault.Amount => uint256)",
            "numberOfBytes": "32",
            "key": value_id,
            "value": "t_uint256",
        }
        storage = [slot_entry("byAmount", 0, mapping_id)]
    else:
        storage = [slot_entry("total", 0, value_id)]
    ast = value_type_ast("Vault", "Amount", underlying) if with_ast else None
    return artifact("Vault", storage, types, ast=ast)


def padded_vault(members, ast_id):
    """An `Entry[]` whose element is a single slot, however many uint128s sit in it."""
    struct_id = f"t_struct(Entry){ast_id}_storage"
    array_id = f"t_array({struct_id})dyn_storage"
    types = {
        "t_uint128": UINT128,
        struct_id: {
            "encoding": "inplace",
            "label": "struct Vault.Entry",
            "numberOfBytes": "32",
            "members": [
                slot_entry(label, 0, "t_uint128", offset=16 * index) for index, label in enumerate(members)
            ],
        },
        array_id: {
            "encoding": "dynamic_array",
            "label": "struct Vault.Entry[]",
            "numberOfBytes": "32",
            "base": struct_id,
        },
    }
    return artifact("Vault", [slot_entry("entries", 0, array_id)], types)


def entry_types(shape, members, ast_id):
    """Types map and top level type id for an `Entry` struct held in the given shape.

    `ast_id` is what solc appends to struct identifiers; it differs between any two
    builds, so the fixtures use different ids on the two sides on purpose.
    """
    struct_id = f"t_struct(Entry){ast_id}_storage"
    array_id = f"t_array({struct_id})dyn_storage"
    types = {
        "t_uint256": UINT256,
        "t_address": ADDRESS,
        struct_id: {
            "encoding": "inplace",
            "label": "struct Vault.Entry",
            "numberOfBytes": str(32 * len(members)),
            "members": [slot_entry(label, index, "t_uint256") for index, label in enumerate(members)],
        },
    }
    dynamic_array = {
        "encoding": "dynamic_array",
        "label": "struct Vault.Entry[]",
        "numberOfBytes": "32",
        "base": struct_id,
    }

    if shape == "plain":
        return types, struct_id
    if shape == "dynamic_array":
        types[array_id] = dynamic_array
        return types, array_id
    if shape == "static_array":
        static_id = f"t_array({struct_id})3_storage"
        types[static_id] = {
            "encoding": "inplace",
            "label": "struct Vault.Entry[3]",
            "numberOfBytes": str(3 * 32 * len(members)),
            "base": struct_id,
        }
        return types, static_id
    if shape == "mapping":
        mapping_id = f"t_mapping(t_address,{struct_id})"
        types[mapping_id] = {
            "encoding": "mapping",
            "label": "mapping(address => struct Vault.Entry)",
            "numberOfBytes": "32",
            "key": "t_address",
            "value": struct_id,
        }
        return types, mapping_id
    if shape == "mapping_of_array":
        types[array_id] = dynamic_array
        mapping_id = f"t_mapping(t_address,{array_id})"
        types[mapping_id] = {
            "encoding": "mapping",
            "label": "mapping(address => struct Vault.Entry[])",
            "numberOfBytes": "32",
            "key": "t_address",
            "value": array_id,
        }
        return types, mapping_id
    if shape == "struct_of_array":
        types[array_id] = dynamic_array
        holder_id = f"t_struct(Holder){ast_id + 100}_storage"
        types[holder_id] = {
            "encoding": "inplace",
            "label": "struct Vault.Holder",
            "numberOfBytes": "32",
            "members": [slot_entry("items", 0, array_id)],
        }
        return types, holder_id
    raise AssertionError(f"unknown shape: {shape}")


def vault(shape, members, ast_id, abi=ABI):
    types, type_id = entry_types(shape, members, ast_id)
    return artifact("Vault", [slot_entry("entries", 0, type_id)], types, abi)


class CompatCheckTest(unittest.TestCase):
    def run_check(self, baseline, current):
        """Writes both sides as Foundry artifacts and runs the checker over them."""
        with tempfile.TemporaryDirectory() as tmp:
            directories = []
            for side, artifacts in (("baseline", baseline), ("current", current)):
                out = os.path.join(tmp, side, "out")
                for name, content in artifacts.items():
                    contract_dir = os.path.join(out, f"{name}.sol")
                    os.makedirs(contract_dir, exist_ok=True)
                    with open(os.path.join(contract_dir, f"{name}.json"), "w") as handle:
                        json.dump(content, handle)
                directories.append(out)

            captured, status = io.StringIO(), 0
            with contextlib.redirect_stdout(captured):
                try:
                    checker.main(["--baseline", directories[0], "--current", directories[1]])
                except SystemExit as exit_request:
                    status = exit_request.code
            return status, captured.getvalue()

    def assert_rejected(self, baseline, current, *expected):
        status, output = self.run_check(baseline, current)
        self.assertEqual(status, 1, output)
        self.assertIn("\nERRORS", output)
        for needle in expected:
            self.assertIn(needle, output)
        return output

    def assert_review_only(self, baseline, current, *expected):
        status, output = self.run_check(baseline, current)
        self.assertEqual(status, 0, output)
        self.assertNotIn("\nERRORS", output)
        self.assertIn("\nREVIEW", output)
        for needle in expected:
            self.assertIn(needle, output)
        return output

    def assert_compatible(self, baseline, current):
        status, output = self.run_check(baseline, current)
        self.assertEqual(status, 0, output)
        self.assertIn("compatible with the baseline (0 item(s) flagged for review)", output)
        return output

    # A struct that is an array element may not grow: the elements sit back to back
    # from the array's base slot, so a wider element moves all the ones behind it.
    def test_appended_member_in_dynamic_array_element_is_an_error(self):
        self.assert_rejected(
            {"Vault": vault("dynamic_array", ["value"], 1)},
            {"Vault": vault("dynamic_array", ["value", "timestamp"], 7)},
            "gained member(s) timestamp at entries[i]",
            "array element",
        )

    def test_appended_member_in_static_array_element_is_an_error(self):
        self.assert_rejected(
            {"Vault": vault("static_array", ["value"], 1)},
            {"Vault": vault("static_array", ["value", "timestamp"], 7)},
            "gained member(s) timestamp at entries[i]",
        )

    def test_appended_member_in_array_under_a_mapping_is_an_error(self):
        self.assert_rejected(
            {"Vault": vault("mapping_of_array", ["value"], 1)},
            {"Vault": vault("mapping_of_array", ["value", "timestamp"], 7)},
            "gained member(s) timestamp at entries[key][i]",
        )

    def test_appended_member_in_array_under_a_struct_is_an_error(self):
        self.assert_rejected(
            {"Vault": vault("struct_of_array", ["value"], 1)},
            {"Vault": vault("struct_of_array", ["value", "timestamp"], 7)},
            "gained member(s) timestamp at entries.items[i]",
        )

    # An element that gains a member without getting wider - the member lands in the
    # padding the element already carried - leaves the stride, and everything stored
    # behind the first element, exactly where it was.
    def test_member_appended_within_array_element_padding_is_a_review(self):
        self.assert_review_only(
            {"Vault": padded_vault(["amount"], 1)},
            {"Vault": padded_vault(["amount", "fee"], 7)},
            "gained member(s) fee at entries[i]",
            "appended within padding",
        )

    # A mapping value has nothing behind it: every entry starts at its own hash.
    def test_appended_member_in_a_mapping_value_is_a_review(self):
        self.assert_review_only(
            {"Vault": vault("mapping", ["value"], 1)},
            {"Vault": vault("mapping", ["value", "timestamp"], 7)},
            "gained member(s) timestamp at entries[key]",
            "not an array element",
        )

    def test_appended_member_in_a_top_level_struct_is_a_review(self):
        self.assert_review_only(
            {"Vault": vault("plain", ["value"], 1)},
            {"Vault": vault("plain", ["value", "timestamp"], 7)},
            "gained member(s) timestamp at entries",
            "not an array element",
        )

    def test_removed_struct_member_is_an_error(self):
        self.assert_rejected(
            {"Vault": vault("mapping", ["value", "timestamp"], 1)},
            {"Vault": vault("mapping", ["value"], 7)},
            "member timestamp was removed",
        )

    def test_reordered_struct_members_are_an_error(self):
        self.assert_rejected(
            {"Vault": vault("mapping", ["value", "timestamp"], 1)},
            {"Vault": vault("mapping", ["timestamp", "value"], 7)},
            "was value, is now timestamp",
        )

    def test_unchanged_layout_is_compatible(self):
        self.assert_compatible(
            {"Vault": vault("dynamic_array", ["value", "timestamp"], 1)},
            {"Vault": vault("dynamic_array", ["value", "timestamp"], 7)},
        )

    def test_removed_function_and_event_are_errors(self):
        self.assert_rejected(
            {"Vault": vault("mapping", ["value"], 1)},
            {"Vault": vault("mapping", ["value"], 7, abi=[])},
            "function deposit(uint256) was removed",
            "event Deposited(address) was removed",
        )

    # receive() and fallback() have no signature to key them by, so they are compared
    # on their own. Losing either turns a plain transfer into a revert.
    def test_removed_receive_is_an_error(self):
        self.assert_rejected(
            {"Vault": vault("mapping", ["value"], 1, abi=ABI + [RECEIVE])},
            {"Vault": vault("mapping", ["value"], 7)},
            "receive() was removed",
        )

    def test_removed_fallback_is_an_error(self):
        self.assert_rejected(
            {"Vault": vault("mapping", ["value"], 1, abi=ABI + [PAYABLE_FALLBACK])},
            {"Vault": vault("mapping", ["value"], 7)},
            "fallback() was removed",
        )

    def test_fallback_that_stops_being_payable_is_an_error(self):
        self.assert_rejected(
            {"Vault": vault("mapping", ["value"], 1, abi=ABI + [PAYABLE_FALLBACK])},
            {"Vault": vault("mapping", ["value"], 7, abi=ABI + [PLAIN_FALLBACK])},
            "fallback() changed mutability from payable to nonpayable",
        )

    def test_kept_receive_is_compatible(self):
        self.assert_compatible(
            {"Vault": vault("mapping", ["value"], 1, abi=ABI + [RECEIVE])},
            {"Vault": vault("mapping", ["value"], 7, abi=ABI + [RECEIVE])},
        )

    # Shrinking a __gap is how new variables are added to an upgradeable contract,
    # so it stays a review item: only a human can tell it from an accidental overlap.
    def test_shrunk_gap_is_a_review(self):
        types = gap_types(49, 50)
        baseline = artifact("Vault", [slot_entry("__gap", 0, GAP_TYPE.format(50))], types)
        current = artifact(
            "Vault",
            [
                slot_entry("__gap", 0, GAP_TYPE.format(49)),
                slot_entry("treasury", 49, "t_address"),
            ],
            types,
        )
        self.assert_review_only(
            {"Vault": baseline},
            {"Vault": current},
            "reserved gap __gap shrank from 50 to 49 slots",
            "new variable treasury sits at slot 49",
        )

    # The usual spelling of the same upgrade: the new variable is declared in front of
    # the gap, which pushes the gap back a slot and shifts the list position of
    # everything behind it without moving a byte of state.
    def test_gap_consumed_by_a_new_variable_is_a_review(self):
        types = gap_types(49, 50)
        baseline = artifact(
            "Vault",
            [slot_entry("treasury", 0, "t_address"), slot_entry("__gap", 1, GAP_TYPE.format(50))],
            types,
        )
        current = artifact(
            "Vault",
            [
                slot_entry("treasury", 0, "t_address"),
                slot_entry("keeper", 1, "t_address"),
                slot_entry("__gap", 2, GAP_TYPE.format(49)),
            ],
            types,
        )
        self.assert_review_only({"Vault": baseline}, {"Vault": current}, "consumed 1 gap slot(s)")

    def test_gap_consumption_that_moves_a_later_variable_is_an_error(self):
        types = gap_types(50)
        baseline = artifact(
            "Vault",
            [
                slot_entry("treasury", 0, "t_address"),
                slot_entry("__gap", 1, GAP_TYPE.format(50)),
                slot_entry("keeper", 51, "t_address"),
            ],
            types,
        )
        # The gap was not shortened to pay for `minter`, so `keeper` is pushed out.
        current = artifact(
            "Vault",
            [
                slot_entry("treasury", 0, "t_address"),
                slot_entry("minter", 1, "t_address"),
                slot_entry("__gap", 2, GAP_TYPE.format(50)),
                slot_entry("keeper", 52, "t_address"),
            ],
            types,
        )
        self.assert_rejected(
            {"Vault": baseline},
            {"Vault": current},
            "variable keeper moved from slot 51+0 to slot 52+0",
        )

    def test_consuming_more_slots_than_the_gap_reserved_is_an_error(self):
        types = gap_types(50, 51)
        baseline = artifact("Vault", [slot_entry("__gap", 0, GAP_TYPE.format(50))], types)
        current = artifact(
            "Vault",
            [slot_entry("keeper", 0, "t_address"), slot_entry("__gap", 1, GAP_TYPE.format(51))],
            types,
        )
        self.assert_rejected(
            {"Vault": baseline},
            {"Vault": current},
            "reserved by __gap at slot 0 now hold data reaching to slot 52",
        )

    def test_variable_replaced_at_its_slot_is_an_error(self):
        types = gap_types(50)
        baseline = artifact(
            "Vault",
            [slot_entry("treasury", 0, "t_address"), slot_entry("__gap", 1, GAP_TYPE.format(50))],
            types,
        )
        current = artifact(
            "Vault",
            [slot_entry("keeper", 0, "t_address"), slot_entry("__gap", 1, GAP_TYPE.format(50))],
            types,
        )
        self.assert_rejected({"Vault": baseline}, {"Vault": current}, "slot 0+0 held treasury, now holds keeper")

    def test_variable_that_changed_type_is_an_error(self):
        types = gap_types(50)
        baseline = artifact("Vault", [slot_entry("treasury", 0, "t_address")], types)
        current = artifact("Vault", [slot_entry("treasury", 0, "t_uint256")], types)
        self.assert_rejected(
            {"Vault": baseline},
            {"Vault": current},
            "variable treasury changed type from address to uint256",
        )

    # An enum is one byte in the layout whatever it holds, so the member list has to
    # be read out of the AST: reordering it reinterprets every value already stored.
    def test_unchanged_enum_is_compatible(self):
        self.assert_compatible(
            {"Vault": enum_vault(["Pending", "Active"], 1)},
            {"Vault": enum_vault(["Pending", "Active"], 7)},
        )

    def test_appended_enum_member_is_a_review(self):
        self.assert_review_only(
            {"Vault": enum_vault(["Pending", "Active"], 1)},
            {"Vault": enum_vault(["Pending", "Active", "Frozen"], 7)},
            "enum Vault.Status gained member(s) Frozen at the end",
        )

    def test_reordered_enum_members_are_an_error(self):
        self.assert_rejected(
            {"Vault": enum_vault(["Pending", "Active"], 1)},
            {"Vault": enum_vault(["Active", "Pending"], 7)},
            "enum Vault.Status: value 0 was Pending, is now Active",
        )

    def test_enum_member_inserted_before_the_existing_ones_is_an_error(self):
        self.assert_rejected(
            {"Vault": enum_vault(["Pending", "Active"], 1)},
            {"Vault": enum_vault(["Draft", "Pending", "Active"], 7)},
            "enum Vault.Status: value 0 was Pending, is now Draft",
        )

    def test_removed_enum_member_is_an_error(self):
        self.assert_rejected(
            {"Vault": enum_vault(["Pending", "Active"], 1)},
            {"Vault": enum_vault(["Pending"], 7)},
            "enum Vault.Status: member Active (value 1) was removed",
        )

    def test_reordered_enum_inside_a_struct_is_an_error(self):
        self.assert_rejected(
            {"Vault": enum_vault(["Pending", "Active"], 1, nested=True)},
            {"Vault": enum_vault(["Active", "Pending"], 7, nested=True)},
            "enum Vault.Status: value 0 was Pending, is now Active",
        )

    def test_enum_without_a_definition_is_a_review(self):
        self.assert_review_only(
            {"Vault": enum_vault(["Pending", "Active"], 1)},
            {"Vault": enum_vault(["Pending", "Active"], 7, with_ast=False)},
            "enum Vault.Status at status is not in the current build's ASTs",
        )

    # A user defined value type keeps its name, its label and its width when what it
    # wraps changes, so the layout is byte for byte the same and the underlying type has
    # to be read out of the AST - otherwise `type Amount is int256` replacing
    # `type Amount is uint256` reads every balance above int256.max back as negative.
    def test_unchanged_value_type_is_compatible(self):
        self.assert_compatible(
            {"Vault": value_type_vault("uint256", 5)},
            {"Vault": value_type_vault("uint256", 11)},
        )

    def test_changed_underlying_type_is_an_error(self):
        self.assert_rejected(
            {"Vault": value_type_vault("uint256", 5)},
            {"Vault": value_type_vault("int256", 11)},
            "value type Vault.Amount at total wraps int256 instead of uint256",
        )

    def test_changed_underlying_type_of_a_struct_member_is_an_error(self):
        self.assert_rejected(
            {"Vault": value_type_vault("uint256", 5, shape="struct_member")},
            {"Vault": value_type_vault("int256", 11, shape="struct_member")},
            "value type Vault.Amount at entry.amount wraps int256 instead of uint256",
        )

    # A value type used as a mapping key decides which slot an entry hashes to, so a
    # value that now means something else sends every lookup somewhere else.
    def test_changed_underlying_type_of_a_mapping_key_is_an_error(self):
        self.assert_rejected(
            {"Vault": value_type_vault("uint256", 5, shape="mapping_key")},
            {"Vault": value_type_vault("int256", 11, shape="mapping_key")},
            "value type Vault.Amount at byAmount[key] wraps int256 instead of uint256",
        )

    def test_value_type_without_a_definition_is_a_review(self):
        self.assert_review_only(
            {"Vault": value_type_vault("uint256", 5)},
            {"Vault": value_type_vault("uint256", 11, with_ast=False)},
            "value type Vault.Amount at total is not in the current build's ASTs",
        )


if __name__ == "__main__":
    unittest.main()
