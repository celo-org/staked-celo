#!/usr/bin/env bash
#
# Vendors the OpenZeppelin sources into ./@openzeppelin/.
#
# The contracts import OpenZeppelin as "@openzeppelin/contracts/..." and
# "@openzeppelin/contracts-upgradeable/...". Keeping the sources at exactly that
# path (instead of a Foundry remapping into lib/) makes the solc source-unit names
# identical to the ones Hardhat used, which keeps the metadata hash appended to the
# bytecode identical. scripts/bytecode-compat-check.py verifies this.
#
# Versions are pinned to what the production contracts were compiled with.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_VERSION="${OZ_CONTRACTS_VERSION:-4.4.2}"
UPGRADEABLE_VERSION="${OZ_UPGRADEABLE_VERSION:-4.5.2}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

vendor() {
  local package="$1" version="$2" target="$3"
  echo "vendoring $package@$version -> $target"
  (cd "$TMP" && npm pack "$package@$version" --silent >/dev/null)
  local tarball
  tarball="$(ls "$TMP"/*.tgz)"
  rm -rf "$target" "$TMP/package"
  mkdir -p "$target"
  tar xzf "$tarball" -C "$TMP"
  # Only the Solidity sources are needed; compiled artifacts and docs are dropped.
  (cd "$TMP/package" && find . -name '*.sol' -print0 | while IFS= read -r -d '' f; do
    mkdir -p "$target/$(dirname "$f")"
    cp "$f" "$target/$f"
  done)
  cp "$TMP/package/LICENSE" "$target/LICENSE" 2>/dev/null || true
  rm -f "$tarball"
}

vendor "@openzeppelin/contracts" "$CONTRACTS_VERSION" "$ROOT/@openzeppelin/contracts"
vendor "@openzeppelin/contracts-upgradeable" "$UPGRADEABLE_VERSION" "$ROOT/@openzeppelin/contracts-upgradeable"

echo "done"
