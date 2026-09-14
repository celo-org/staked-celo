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
# Usage:
#   scripts/prepare-devchain.sh            # uses node_modules or downloads the package
#   DEVCHAIN_STATE=/path/l2-devchain.json scripts/prepare-devchain.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/test/devchain"
PKG="@celo/devchain-anvil"
VERSION="${DEVCHAIN_ANVIL_VERSION:-17.0.7}"
STATE="${DEVCHAIN_STATE:-}"

mkdir -p "$OUT_DIR"

if [[ -f "$OUT_DIR/allocs.json" && -f "$OUT_DIR/meta.json" && "${FORCE:-0}" != "1" ]]; then
  echo "devchain fixture already present in $OUT_DIR (set FORCE=1 to regenerate)"
  exit 0
fi

if [[ -z "$STATE" ]]; then
  if [[ -f "$ROOT/node_modules/$PKG/devchain/l2-devchain.json" ]]; then
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
python3 - "$STATE" "$OUT_DIR" <<'EOF'
import json, sys, os

state_path, out_dir = sys.argv[1], sys.argv[2]
state = json.load(open(state_path))

allocs = {}
for address, record in state["accounts"].items():
    entry = {"balance": record.get("balance", "0x0"), "nonce": record.get("nonce", 0)}
    code = record.get("code")
    if code and code != "0x":
        entry["code"] = code
    storage = record.get("storage") or {}
    if storage:
        entry["storage"] = storage
    allocs[address] = entry

with open(os.path.join(out_dir, "allocs.json"), "w") as f:
    json.dump(allocs, f, separators=(",", ":"))

meta = {
    "blockNumber": int(state["block"]["number"], 16),
    "timestamp": int(state["block"]["timestamp"], 16),
    "bestBlockNumber": state.get("best_block_number", 0),
}
with open(os.path.join(out_dir, "meta.json"), "w") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")

print(f"wrote {len(allocs)} accounts to {out_dir}/allocs.json; block {meta['blockNumber']} ts {meta['timestamp']}")
EOF
