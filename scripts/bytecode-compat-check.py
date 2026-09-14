#!/usr/bin/env python3
"""
Verifies that the Foundry build produces the same bytecode as a reference build.

The production contracts must keep compiling to exactly the bytecode Hardhat produced
(solc 0.8.11, evm istanbul, optimizer off, literal metadata content). Two references
are supported:

  --hardhat-artifacts DIR   Hardhat `artifacts/contracts` directory (from `yarn compile`
                            on the legacy toolchain). Every contract is compared on both
                            creation and runtime bytecode. This is the strict check.

  --deployments NETWORK     `deployments/<NETWORK>/*_Implementation.json` produced by
                            hardhat-deploy. Only informational: implementations on chain
                            may predate the current sources.

The comparison is reported twice: on the full bytecode and with the CBOR metadata
trailer stripped (the trailer only carries the metadata hash).

Exit status is non-zero when a strict comparison finds a difference.
"""
import argparse
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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


def print_table(title, rows):
    print(f"\n{title}")
    if not rows:
        print("  (nothing to compare)")
        return
    width = max(len(r[0]) for r in rows)
    print(f"  {'source':<{width}}  {'contract':<28} {'full':<8} {'no-metadata'}")
    for source, name, full, stripped in rows:
        print(f"  {source:<{width}}  {name:<28} {full:<8} {stripped}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--hardhat-artifacts", help="Hardhat artifacts/contracts directory (strict)")
    parser.add_argument("--deployments", help="network name under deployments/ (informational)")
    parser.add_argument("--out", default=os.path.join(ROOT, "out"), help="Foundry out directory")
    args = parser.parse_args()

    if not args.hardhat_artifacts and not args.deployments:
        parser.error("pass --hardhat-artifacts and/or --deployments")
    if not os.path.isdir(args.out):
        sys.exit(f"Foundry out directory not found: {args.out} (run `forge build` first)")

    failures = 0
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
