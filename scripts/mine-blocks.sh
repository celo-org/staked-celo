#!/usr/bin/env bash
#
# Mines blocks on a local development node.
#
# Ports legacy/scripts/mineBlocks.ts, which `yarn deploy:devchain` ran right after
# deploying so that the epoch based logic of the Celo core contracts had a few epochs
# of history behind it. The Hardhat script sent one `evm_mine` per block; anvil mines
# the whole batch in a single `anvil_mine` call.
#
# Usage:
#   scripts/mine-blocks.sh                 # 35 blocks on http://localhost:8545
#   scripts/mine-blocks.sh 100
#   scripts/mine-blocks.sh 100 http://localhost:8546
#   BLOCKS=100 RPC_URL=http://localhost:8546 scripts/mine-blocks.sh
#
# Other node types expose the same thing under a different method:
#   hardhat node   cast rpc --rpc-url "$RPC_URL" hardhat_mine "$(cast to-hex 35)"
#   ganache        cast rpc --rpc-url "$RPC_URL" evm_mine       # once per block
#   geth --dev     cast rpc --rpc-url "$RPC_URL" miner_start; sleep; miner_stop
# A real network needs none of this: its validators produce the blocks.
#
set -euo pipefail

BLOCKS="${1:-${BLOCKS:-35}}"
RPC_URL="${2:-${RPC_URL:-http://localhost:8545}}"

if ! [[ "$BLOCKS" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: block count must be a positive integer, got '$BLOCKS'" >&2
  exit 1
fi

before="$(cast block-number --rpc-url "$RPC_URL")"
cast rpc --rpc-url "$RPC_URL" anvil_mine "$BLOCKS" >/dev/null
after="$(cast block-number --rpc-url "$RPC_URL")"

echo "mined $((after - before)) blocks on $RPC_URL: $before -> $after"
