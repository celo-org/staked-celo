#!/usr/bin/env bash
#
# Vendors the OpenZeppelin sources into <root>/@openzeppelin/.
#
# The contracts import OpenZeppelin as "@openzeppelin/contracts/..." and
# "@openzeppelin/contracts-upgradeable/...". Keeping the sources at exactly that
# path (instead of a Foundry remapping into lib/) makes the solc source-unit names
# identical to the ones Hardhat used, which keeps the metadata hash appended to the
# bytecode identical. scripts/bytecode-compat-check.py verifies this.
#
# Usage: scripts/vendor-openzeppelin.sh [--root <dir>]
#
# --root picks the checkout to vendor into, and with it the package.json the versions
# are read from. The CI compatibility job uses it to vendor into the baseline release
# checkout, so that each side of the comparison is built against the OpenZeppelin
# versions it pins itself. Sharing one copy across both sides would let an upgrade of
# the vendored sources change the inherited storage layout on both sides at once,
# which cancels an incompatible change out of the diff instead of reporting it.
#
# Versions are resolved in this order, first match wins:
#
#   1. OZ_CONTRACTS_VERSION / OZ_UPGRADEABLE_VERSION
#   2. dependencies/devDependencies of <root>/package.json (a leading ^ or ~ is
#      dropped, so the range is taken as the exact version it was resolved from)
#   3. the defaults below
#
# The defaults are what this repo builds with: its package.json no longer lists
# OpenZeppelin now that the sources are vendored. They must stay at the versions the
# deployed contracts were audited and compiled with, because the sources are hashed
# into the metadata trailer of the bytecode.
#
# NPM_REGISTRY overrides the registry `npm pack` downloads from, for networks where
# the configured one is unreachable (e.g. NPM_REGISTRY=https://registry.yarnpkg.com).
#
set -euo pipefail

DEFAULT_CONTRACTS_VERSION="4.4.2"
DEFAULT_UPGRADEABLE_VERSION="4.5.2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "--root needs a directory" >&2; exit 1; }
      ROOT="$(cd "$2" && pwd)"
      shift 2
      ;;
    *)
      echo "usage: $0 [--root <dir>]" >&2
      exit 1
      ;;
  esac
done

# Prints the version $ROOT/package.json pins for a package, or nothing when it does
# not list it. node is present anyway, `npm pack` below needs it.
pinned_version() {
  local package="$1"
  [ -f "$ROOT/package.json" ] || return 0
  node -e '
    const fs = require("fs");
    const [file, name] = process.argv.slice(1);
    let pkg;
    try {
      pkg = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (error) {
      process.exit(0);
    }
    const range = (pkg.dependencies || {})[name] || (pkg.devDependencies || {})[name];
    if (range) process.stdout.write(String(range).replace(/^[\^~]/, ""));
  ' "$ROOT/package.json" "$package"
}

CONTRACTS_VERSION="${OZ_CONTRACTS_VERSION:-$(pinned_version "@openzeppelin/contracts")}"
CONTRACTS_VERSION="${CONTRACTS_VERSION:-$DEFAULT_CONTRACTS_VERSION}"
UPGRADEABLE_VERSION="${OZ_UPGRADEABLE_VERSION:-$(pinned_version "@openzeppelin/contracts-upgradeable")}"
UPGRADEABLE_VERSION="${UPGRADEABLE_VERSION:-$DEFAULT_UPGRADEABLE_VERSION}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

vendor() {
  local package="$1" version="$2" target="$3"
  echo "vendoring $package@$version -> $target"
  (cd "$TMP" && npm pack "$package@$version" ${NPM_REGISTRY:+--registry "$NPM_REGISTRY"} --silent >/dev/null)
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
