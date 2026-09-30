#!/usr/bin/env bash
#
# Prepares the Celo devchain fixture used by the Foundry test-suite.
#
# The tests that exercise real Celo core contracts (Election, LockedGold,
# Validators, Accounts, Governance, ...) load the anvil state published in the
# `@celo/devchain-anvil` npm package via `vm.loadAllocs`. That state file is an
# anvil `--dump-state` document; Foundry's `loadAllocs` cheatcode wants a plain
# genesis "alloc" map, so this script extracts the `accounts` section into
# test/devchain/allocs.json and the block environment into test/devchain/meta.json.
#
# The package version is pinned in package.json's devDependencies; set
# DEVCHAIN_ANVIL_VERSION to override it for a one-off run.
#
# Usage:
#   scripts/prepare-devchain.sh            # uses node_modules or downloads the package
#   DEVCHAIN_STATE=/path/l2-devchain.json scripts/prepare-devchain.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/test/devchain"
PKG="@celo/devchain-anvil"

# Prints one top-level field of a JSON file, empty when it is not set. node is a
# prerequisite of this script anyway: `npm pack` below runs on it.
json_field() {
  node --input-type=module -e '
import { readFileSync } from "node:fs";
const [file, field] = process.argv.slice(1);
process.stdout.write(String(JSON.parse(readFileSync(file, "utf8"))[field] ?? ""));
' "$1" "$2"
}

# package.json is the single source of truth for the pinned version.
# DEVCHAIN_ANVIL_VERSION overrides it, e.g. to try a bump before editing package.json.
DEFAULT_VERSION="$(node --input-type=module -e '
import { readFileSync } from "node:fs";
const pkg = JSON.parse(readFileSync(process.argv[1], "utf8"));
process.stdout.write(pkg.devDependencies["@celo/devchain-anvil"].replace(/^[\^~]+/, ""));
' "$ROOT/package.json")"
VERSION="${DEVCHAIN_ANVIL_VERSION:-$DEFAULT_VERSION}"
STATE="${DEVCHAIN_STATE:-}"

# Provenance of the fixture, recorded in meta.json so that a different state file or
# package version regenerates the fixture instead of silently reusing the old one.
if [[ -n "$STATE" ]]; then
  SOURCE="state:$STATE"
else
  SOURCE="npm:$PKG@$VERSION"
fi

echo "using $SOURCE"

mkdir -p "$OUT_DIR"

# An explicit state file may be regenerated in place, so it is always re-extracted; the
# cache only serves the pinned package, whose contents are fixed by its version.
if [[ -z "$STATE" && -f "$OUT_DIR/allocs.json" && -f "$OUT_DIR/meta.json" && "${FORCE:-0}" != "1" ]]; then
  RECORDED="$(json_field "$OUT_DIR/meta.json" source)"
  if [[ "$RECORDED" == "$SOURCE" ]]; then
    echo "devchain fixture already present in $OUT_DIR and up to date (set FORCE=1 to regenerate)"
    exit 0
  fi
  echo "devchain fixture in $OUT_DIR was built from '${RECORDED:-unknown}', regenerating"
fi

if [[ -z "$STATE" ]]; then
  INSTALLED=""
  if [[ -f "$ROOT/node_modules/$PKG/package.json" ]]; then
    INSTALLED="$(json_field "$ROOT/node_modules/$PKG/package.json" version)"
  fi
  # The installed package is only a shortcut when it is the requested version.
  if [[ "$INSTALLED" == "$VERSION" && -f "$ROOT/node_modules/$PKG/devchain/l2-devchain.json" ]]; then
    STATE="$ROOT/node_modules/$PKG/devchain/l2-devchain.json"
  else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    echo "downloading $PKG@$VERSION ..."
    (cd "$TMP" && npm pack "$PKG@$VERSION" --silent >/dev/null && tar xzf ./*.tgz)
    STATE="$TMP/package/devchain/l2-devchain.json"
  fi
fi

echo "extracting allocs from $STATE ..."
# The pinned state dump is ~700 MB: the extractor holds the whole document in one
# buffer and builds the alloc map beside it, so node is given a heap to match.
node --max-old-space-size=8192 "$ROOT/scripts/lib/extract-devchain-allocs.ts" \
  "$STATE" "$OUT_DIR" "$SOURCE"
