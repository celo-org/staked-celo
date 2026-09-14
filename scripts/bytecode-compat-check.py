#!/usr/bin/env python3
"""
Verifies that the Foundry build produces the same bytecode as a reference build.

The production contracts must keep compiling to exactly the bytecode Hardhat produced
(solc 0.8.11, evm istanbul, optimizer off, literal metadata content). Three references
are supported:

  --reference FILE          Checked-in digests of every contract's creation and runtime
                            bytecode (scripts/bytecode-reference.json). This is the check
                            CI runs: it needs no Hardhat install, and it fails as soon as
                            a contract or a compiler setting changes, because the solc
                            settings are hashed into the metadata trailer. Regenerate it
                            with --update-reference when a contract change is intended.

  --hardhat-artifacts DIR   Hardhat `artifacts/contracts` directory, produced by the frozen
                            toolchain under legacy/. Every contract is compared on both
                            creation and runtime bytecode. This is the strict check that
                            originally proved the Foundry build reproduces the Hardhat one.

  --deployments NETWORK     `deployments/<NETWORK>/*_Implementation.json` produced by
                            hardhat-deploy. Only informational: implementations on chain
                            may predate the current sources.

For the two artifact-based modes the comparison is reported twice: on the full bytecode
and with the CBOR metadata trailer stripped (the trailer only carries the metadata hash).

Exit status is non-zero when a strict comparison finds a difference.
"""
import argparse
import glob
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Only the project's own contracts are pinned; library and test sources pulled in by
# the build are not part of the deployed surface.
REFERENCE_SOURCE_PREFIX = "contracts/"


def norm(hexstr):
    return hexstr[2:] if hexstr.startswith("0x") else hexstr


def strip_metadata(hexstr):
    code = norm(hexstr)
    if len(code) < 4:
        return code
    length = int(code[-4:], 16)
    return code[: -(length + 2) * 2]


def forge_artifact(out_dir, source_name, contract_name):
    path = os.path.join(out_dir, os.path.basename(source_name), f"{contract_name}.json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        artifact = json.load(f)
    return norm(artifact["bytecode"]["object"]), norm(artifact["deployedBytecode"]["object"])


def compare(reference_creation, reference_runtime, forge_creation, forge_runtime):
    full = reference_creation == forge_creation and reference_runtime == forge_runtime
    stripped = strip_metadata(reference_creation) == strip_metadata(forge_creation) and strip_metadata(
        reference_runtime
    ) == strip_metadata(forge_runtime)
    return full, stripped


def check_hardhat(artifacts_dir, out_dir):
    failures = 0
    rows = []
    for path in sorted(glob.glob(os.path.join(artifacts_dir, "**", "*.json"), recursive=True)):
        if path.endswith(".dbg.json"):
            continue
        with open(path) as f:
            artifact = json.load(f)
        if not artifact.get("bytecode") or artifact["bytecode"] == "0x":
            continue  # abstract contract, interface or library without code
        name, source = artifact["contractName"], artifact["sourceName"]
        forge = forge_artifact(out_dir, source, name)
        if forge is None:
            rows.append((source, name, "MISSING", "MISSING"))
            failures += 1
            continue
        full, stripped = compare(norm(artifact["bytecode"]), norm(artifact["deployedBytecode"]), *forge)
        rows.append((source, name, "ok" if full else "DIFF", "ok" if stripped else "DIFF"))
        if not full:
            failures += 1
    print_table("Hardhat artifacts vs Foundry", rows)
    return failures


def check_deployments(network, out_dir):
    rows = []
    for path in sorted(glob.glob(os.path.join(ROOT, "deployments", network, "*_Implementation.json"))):
        name = os.path.basename(path).replace("_Implementation.json", "")
        with open(path) as f:
            deployment = json.load(f)
        forge = forge_artifact(out_dir, f"{name}.sol", name)
        if forge is None:
            rows.append((network, name, "MISSING", "MISSING"))
            continue
        runtime = norm(deployment.get("deployedBytecode", ""))
        full = runtime == forge[1]
        stripped = strip_metadata(runtime) == strip_metadata(forge[1])
        rows.append((network, name, "ok" if full else "DIFF", "ok" if stripped else "DIFF"))
    print_table(f"deployments/{network} implementations vs Foundry (informational)", rows)
    return 0


def digest(hexstr):
    """sha256 of the lowercase hex digits of the bytecode, without the 0x prefix."""
    return hashlib.sha256(norm(hexstr).lower().encode("ascii")).hexdigest()


def iter_default_artifacts(out_dir):
    """Yields (source, contract, artifact) for the default compiler profile.

    Foundry names the artifact <Contract>.json, or <Contract>.default.json when the
    contract is also built under one of the additional_compiler_profiles. Artifacts
    of the other profiles (<Contract>.test-via-ir.json) never ship on chain.
    """
    for root, dirs, files in os.walk(out_dir):
        dirs[:] = [d for d in dirs if d != "build-info"]
        for filename in sorted(files):
            if not filename.endswith(".json"):
                continue
            name, _, profile = filename[: -len(".json")].partition(".")
            if profile and (profile != "default" or f"{name}.json" in files):
                continue
            with open(os.path.join(root, filename)) as f:
                artifact = json.load(f)
            target = artifact.get("metadata", {}).get("settings", {}).get("compilationTarget")
            if not target:
                continue
            source, contract = next(iter(target.items()))
            yield source, contract, artifact


def iter_contracts(out_dir):
    """Yields (source, contract, artifact) for the project's contracts that have code."""
    for source, contract, artifact in iter_default_artifacts(out_dir):
        if not source.startswith(REFERENCE_SOURCE_PREFIX):
            continue
        if not norm(artifact.get("bytecode", {}).get("object", "")):
            continue  # abstract contract or interface
        yield source, contract, artifact


def build_reference(out_dir):
    contracts = {}
    for source, name, artifact in iter_contracts(out_dir):
        contracts[f"{source}:{name}"] = {
            "creation": digest(artifact["bytecode"]["object"]),
            "runtime": digest(artifact["deployedBytecode"]["object"]),
        }
    return {
        "comment": (
            "Digests of the creation and runtime bytecode of every contract under "
            "contracts/. Regenerate with `forge build && scripts/bytecode-compat-check.py "
            "--update-reference scripts/bytecode-reference.json` whenever a contract change "
            "is intended, and review the resulting diff as carefully as the contract change."
        ),
        "algorithm": "sha256 of the lowercase hex digits, without the 0x prefix",
        "contracts": dict(sorted(contracts.items())),
    }


def update_reference(path, out_dir):
    reference = build_reference(out_dir)
    with open(path, "w") as f:
        json.dump(reference, f, indent=2)
        f.write("\n")
    print(f"wrote {len(reference['contracts'])} contract digests to {path}")


def check_reference(path, out_dir):
    if not os.path.exists(path):
        sys.exit(f"reference not found: {path} (create it with --update-reference)")
    with open(path) as f:
        expected = json.load(f)["contracts"]
    current = build_reference(out_dir)["contracts"]

    failures = 0
    rows = []
    for key in sorted(set(expected) | set(current)):
        source, name = key.rsplit(":", 1)
        want, have = expected.get(key), current.get(key)
        if want is None:
            rows.append((source, name, "UNPINNED", "UNPINNED"))
            failures += 1
            continue
        if have is None:
            rows.append((source, name, "MISSING", "MISSING"))
            failures += 1
            continue
        creation = want["creation"] == have["creation"]
        runtime = want["runtime"] == have["runtime"]
        rows.append((source, name, "ok" if creation else "DIFF", "ok" if runtime else "DIFF"))
        if not (creation and runtime):
            failures += 1
    print_table(f"{os.path.relpath(path, ROOT)} vs Foundry", rows, ("creation", "runtime"))
    if failures:
        print(
            "\nUNPINNED means the contract is not in the reference yet, MISSING means the "
            "reference has a contract the build does not produce."
            "\nIf the change is intended, rerun with --update-reference to refresh the reference."
        )
    return failures


def print_table(title, rows, columns=("full", "no-metadata")):
    print(f"\n{title}")
    if not rows:
        print("  (nothing to compare)")
        return
    width = max(len(r[0]) for r in rows)
    print(f"  {'source':<{width}}  {'contract':<28} {columns[0]:<8} {columns[1]}")
    for source, name, full, stripped in rows:
        print(f"  {source:<{width}}  {name:<28} {full:<8} {stripped}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reference", help="checked-in bytecode digests to verify against (strict)")
    parser.add_argument("--update-reference", help="regenerate the digest file from the current build")
    parser.add_argument("--hardhat-artifacts", help="Hardhat artifacts/contracts directory (strict)")
    parser.add_argument("--deployments", help="network name under deployments/ (informational)")
    parser.add_argument("--out", default=os.path.join(ROOT, "out"), help="Foundry out directory")
    args = parser.parse_args()

    if not (args.reference or args.update_reference or args.hardhat_artifacts or args.deployments):
        parser.error("pass --reference, --update-reference, --hardhat-artifacts and/or --deployments")
    if not os.path.isdir(args.out):
        sys.exit(f"Foundry out directory not found: {args.out} (run `forge build` first)")

    if args.update_reference:
        update_reference(args.update_reference, args.out)
        return

    failures = 0
    if args.reference:
        failures += check_reference(args.reference, args.out)
    if args.hardhat_artifacts:
        failures += check_hardhat(args.hardhat_artifacts, args.out)
    if args.deployments:
        failures += check_deployments(args.deployments, args.out)

    if failures:
        print(f"\n{failures} contract(s) differ from the reference build")
        sys.exit(1)
    print("\nbytecode matches the reference build")


if __name__ == "__main__":
    main()
