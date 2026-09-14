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
ADDRESS = {"encoding": "inplace", "label": "address", "numberOfBytes": "20"}

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


def slot_entry(label, slot, type_id, offset=0):
    """One entry of storageLayout.storage, or one struct member; solc shapes them alike."""
    return {"label": label, "slot": str(slot), "offset": offset, "type": type_id}


def artifact(name, storage, types, abi=ABI):
    return {
        "metadata": {"settings": {"compilationTarget": {f"contracts/{name}.sol": name}}},
        "storageLayout": {"storage": list(storage), "types": dict(types)},
        "abi": list(abi),
    }


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
        status, output = self.run_check(
            {"Vault": vault("dynamic_array", ["value", "timestamp"], 1)},
            {"Vault": vault("dynamic_array", ["value", "timestamp"], 7)},
        )
        self.assertEqual(status, 0, output)
        self.assertIn("compatible with the baseline (0 item(s) flagged for review)", output)

    def test_removed_function_and_event_are_errors(self):
        self.assert_rejected(
            {"Vault": vault("mapping", ["value"], 1)},
            {"Vault": vault("mapping", ["value"], 7, abi=[])},
            "function deposit(uint256) was removed",
            "event Deposited(address) was removed",
        )

    # Shrinking a __gap is how new variables are added to an upgradeable contract,
    # so it stays a review item: only a human can tell it from an accidental overlap.
    def test_shrunk_gap_is_a_review(self):
        gap_types = {
            "t_uint256": UINT256,
            "t_address": ADDRESS,
            "t_array(t_uint256)50_storage": {
                "encoding": "inplace",
                "label": "uint256[50]",
                "numberOfBytes": "1600",
                "base": "t_uint256",
            },
            "t_array(t_uint256)49_storage": {
                "encoding": "inplace",
                "label": "uint256[49]",
                "numberOfBytes": "1568",
                "base": "t_uint256",
            },
        }
        baseline = artifact("Vault", [slot_entry("__gap", 0, "t_array(t_uint256)50_storage")], gap_types)
        current = artifact(
            "Vault",
            [
                slot_entry("__gap", 0, "t_array(t_uint256)49_storage"),
                slot_entry("treasury", 49, "t_address"),
            ],
            gap_types,
        )
        self.assert_review_only(
            {"Vault": baseline},
            {"Vault": current},
            "reserved gap __gap shrank from 50 to 49 slots",
            "new variable treasury sits at slot 49",
        )


if __name__ == "__main__":
    unittest.main()
