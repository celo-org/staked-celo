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
# Usage: scripts/vendor-openzeppelin.sh [--root <dir>] [--no-prune]
#
# --root picks the checkout to vendor into, and with it the package.json the versions
# are read from. The CI compatibility job uses it to vendor into the baseline release
# checkout, so that each side of the comparison is built against the OpenZeppelin
# versions it pins itself. Sharing one copy across both sides would let an upgrade of
# the vendored sources change the inherited storage layout on both sides at once,
# which cancels an incompatible change out of the diff instead of reporting it.
#
# The two packages carry an order of magnitude more Solidity than this protocol uses,
# so what is extracted is then pruned to the files the build actually reaches: forge
# builds <root> and every vendored .sol that solc was never handed is deleted, along
# with the directories that empties. solc records only the sources of the unit it
# compiles, so a file no compilation ever opened is a file no metadata hash and no
# bytecode ever depended on, and dropping it cannot move either. --no-prune keeps the
# full upstream tree.
#
# That build is a throwaway: it writes its artifacts and its cache into the temporary
# directory below, so pruning neither disturbs nor depends on an existing out/ in
# <root>, and the caller's next `forge build` is unaffected either way.
#
# The set is always computed from the build of <root> itself, never from the checkout
# this script lives in. The baseline of the CI compatibility job is an older release
# whose contracts import a different set of files, and pruning it against what the
# current contracts import would delete sources it still needs.
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
PRUNE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "--root needs a directory" >&2; exit 1; }
      ROOT="$(cd "$2" && pwd)"
      shift 2
      ;;
    --no-prune)
      PRUNE=0
      shift
      ;;
    *)
      echo "usage: $0 [--root <dir>] [--no-prune]" >&2
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

# Deletes the vendored sources the build of $ROOT never compiles. Everything that is
# not Solidity - the LICENSE of each package - is left alone.
prune() {
  command -v forge >/dev/null 2>&1 || {
    echo "prune needs forge on PATH: install Foundry, or pass --no-prune" >&2
    exit 1
  }

  echo "building $ROOT to see which vendored sources it imports"
  local log="$TMP/forge-build.log"
  # forge is pointed at a scratch out/ and cache/ so that the prune leaves whatever
  # build $ROOT already has exactly as it found it. FOUNDRY_BUILD_INFO is what the
  # used set is read from, so it is asked for here rather than assumed of the config.
  if ! FOUNDRY_OUT="$TMP/prune-out" FOUNDRY_CACHE_PATH="$TMP/prune-cache" \
       FOUNDRY_BUILD_INFO=true forge build --root "$ROOT" >"$log" 2>&1; then
    cat "$log" >&2
    echo "forge build --root $ROOT failed, so the imported set is unknown; nothing pruned" >&2
    exit 1
  fi

  python3 - "$ROOT" "$TMP/prune-out/build-info" <<'PY'
import json
import pathlib
import sys

root, build_info = (pathlib.Path(argument) for argument in sys.argv[1:3])

infos = sorted(build_info.glob("*.json"))
if not infos:
    sys.exit("no build-info written to %s" % build_info)

# The standard-json input of a compilation lists every source unit solc was handed,
# transitive imports included, under the same "@openzeppelin/..." names the contracts
# import. One build-info file per compiler invocation, so the sets are unioned.
used = set()
for info in infos:
    build = json.loads(info.read_text())
    # source_id_to_path is the cheap one; input.sources names the same units for
    # build-info versions written before it existed.
    by_id = build.get("source_id_to_path")
    names = by_id.values() if by_id else build["input"]["sources"].keys()
    used.update(name for name in names if name.startswith("@openzeppelin/"))

if not used:
    sys.exit("the build imports no @openzeppelin source; refusing to empty the tree")

kept = removed = 0
for source in sorted(root.glob("@openzeppelin/**/*.sol")):
    if source.relative_to(root).as_posix() in used:
        kept += 1
    else:
        source.unlink()
        removed += 1

# Deepest first, so a directory emptied by its own subdirectories goes too.
for directory in sorted(root.glob("@openzeppelin/**/*"), reverse=True):
    if directory.is_dir() and not any(directory.iterdir()):
        directory.rmdir()

print("pruned @openzeppelin: kept %d imported sources, removed %d unused" % (kept, removed))
PY
}

vendor "@openzeppelin/contracts" "$CONTRACTS_VERSION" "$ROOT/@openzeppelin/contracts"
vendor "@openzeppelin/contracts-upgradeable" "$UPGRADEABLE_VERSION" "$ROOT/@openzeppelin/contracts-upgradeable"

if [ "$PRUNE" -eq 1 ]; then
  prune
else
  echo "--no-prune: keeping every vendored source"
fi

echo "done"
