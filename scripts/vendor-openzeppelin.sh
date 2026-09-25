#!/usr/bin/env bash
#
# Vendors the OpenZeppelin sources into <root>/@openzeppelin/, for a checkout that has
# no node_modules.
#
# This repo does not need it. Here @openzeppelin is a symlink into node_modules, put
# there by `yarn install` from the exact versions package.json pins, and the script
# refuses to overwrite that symlink.
#
# What needs it is the baseline of the CI compatibility job: an older release, checked
# out beside this one and built with the current toolchain, with no install step of its
# own. Its contracts import "@openzeppelin/contracts/..." and
# "@openzeppelin/contracts-upgradeable/..." like ours do, and keeping the sources at
# exactly that path (rather than behind a Foundry remapping into lib/) makes the solc
# source-unit names identical on both sides, which is what keeps the metadata hash
# appended to the bytecode comparable.
#
# Usage: scripts/vendor-openzeppelin.sh [--root <dir>]
#
# --root picks the checkout to vendor into, and with it the package.json the versions
# are read from. Each side of the comparison is therefore built against the OpenZeppelin
# versions it pins itself. Sharing one copy across both sides would let an upgrade of
# the dependency change the inherited storage layout on both sides at once, which
# cancels an incompatible change out of the diff instead of reporting it.
#
# The whole upstream tree is extracted. The two packages carry an order of magnitude
# more Solidity than this protocol uses, but solc records only the sources of the unit
# it compiles, so a file no compilation ever opens is a file no metadata hash and no
# bytecode ever depends on.
#
# Versions are resolved in this order, first match wins:
#
#   1. OZ_CONTRACTS_VERSION / OZ_UPGRADEABLE_VERSION
#   2. dependencies/devDependencies of <root>/package.json (a leading ^ or ~ is
#      dropped, so the range is taken as the exact version it was resolved from)
#   3. the defaults below
#
# The defaults are the versions this protocol was audited and compiled with, for a
# checkout whose package.json lists OpenZeppelin nowhere. They matter because the
# sources are hashed into the metadata trailer of the bytecode.
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

# A symlink means the checkout resolves @openzeppelin through node_modules, which is
# how this repo is set up. Vendoring over it would replace a dependency pinned in
# package.json and the lockfile with an unmanaged copy of the same files.
if [ -L "$ROOT/@openzeppelin" ]; then
  echo "$ROOT/@openzeppelin is a symlink into node_modules: use yarn install here" >&2
  exit 1
fi

# Prints the version $ROOT/package.json pins for a package, or nothing when it does
# not list it. node is present anyway, `npm pack` below needs it.
pinned_version() {
  local package="$1"
  [ -f "$ROOT/package.json" ] || return 0
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const [file, name] = process.argv.slice(1);
    let pkg;
    try {
      pkg = JSON.parse(readFileSync(file, "utf8"));
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
