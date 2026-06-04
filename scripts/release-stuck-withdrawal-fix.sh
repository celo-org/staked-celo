#!/usr/bin/env bash
#
# release-stuck-withdrawal-fix.sh
# ===============================
# Releases the stuck-withdrawal fix by upgrading the four stCELO
# implementations (Account, DefaultStrategy, SpecificGroupStrategy, Manager)
# via a CELO GOVERNANCE proposal.
#
# The proxies are owned by the stCELO MultiSig, which exposes
# `governanceProposeAndExecute(destinations, values, payloads)` gated by
# `onlyGovernance`. So Celo Governance executes a single batched call through
# it - no owner confirmations, no timelock. The release CGP is one tx:
#   Governance -> MultiSig.governanceProposeAndExecute(
#       [Account, DefaultStrategy, SpecificGroupStrategy, Manager],
#       [0,0,0,0],
#       [upgradeTo(implA), upgradeTo(implDS), upgradeTo(implSGS), upgradeTo(implMgr)])
#
# Usage:
#   scripts/release-stuck-withdrawal-fix.sh fork        # (default) fork test
#   scripts/release-stuck-withdrawal-fix.sh mainnet     # real deploy + verify + CGP
#
# fork    : fork mainnet, deploy ephemeral impls, impersonate Celo Governance,
#           execute the proposal, assert upgrades + storage intact + new code
#           live. No explorer verification (fork addresses are throwaway).
# mainnet : REAL broadcast. Deploys the 4 impls (+ library) to Celo mainnet,
#           verifies each on Celoscan AND Blockscout, then builds + prints the
#           CGP transaction/JSON with the real addresses. Does NOT execute the
#           upgrade - that happens when the CGP passes the Governance vote.
#           Required env: DEPLOYER_PK, CELO_SCAN_API_KEY.
#
# Requirements: anvil, cast, forge, jq, python3, yarn, npx (foundry in PATH).
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TARGET="${1:-fork}"
RPC_FORK="${CELO_RPC_URL:-https://forno.celo.org}"
PORT=8591; ANVIL_RPC="http://127.0.0.1:${PORT}"
GAS=25000000000; BIG=0x10000000000000000000000
ANVIL_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# --- mainnet addresses ---
REGISTRY=0x000000000000000000000000000000000000ce10
MULTISIG=0x78DaA21FcE4D30E74fF745Da3204764a0ad40179
ACCOUNT=0x4aAD04D41FD7fd495503731C5a2579e19054C432
MANAGER=0x0239b96D10a434a56CC9E09383077A0490cF9398
DS=0x3A3ed74B1cC543D5EB323f70ac2F19977a0eA088
SGS=0xb88af6EAc9cd146D8b03b66708EF76beBD937871
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
# verification
SOLC_VERSION=0.8.11
EVM_VERSION=istanbul          # optimizer is DISABLED in hardhat.config for 0.8.11
BLOCKSCOUT_API=https://celo.blockscout.com/api
DS_LIB_PATH="contracts/common/linkedlists/AddressSortedLinkedList.sol:AddressSortedLinkedList"

FAIL=0; pass(){ echo "  [PASS] $*"; }; fail(){ echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
cleanup(){ pkill -f "anvil .*port ${PORT}" 2>/dev/null || true; }
trap cleanup EXIT
norm(){ echo "$1" | tr 'A-Z' 'a-z' | sed 's/^0x0*//'; }

# ---------------------------------------------------------------------------
echo "=== compiling ==="
yarn --silent compile >/tmp/release-compile.log 2>&1 || { echo "compile failed"; tail /tmp/release-compile.log; exit 1; }

# pick RPC + deployer per target
if [ "$TARGET" = "fork" ]; then
  echo "=== starting anvil fork of $RPC_FORK ==="
  anvil --fork-url "$RPC_FORK" --celo --port "$PORT" --host 127.0.0.1 \
    --disable-code-size-limit --base-fee "$GAS" --gas-price "$GAS" >/tmp/anvil-release.log 2>&1 &
  for i in $(seq 1 60); do cast block-number --rpc-url "$ANVIL_RPC" >/dev/null 2>&1 && break; sleep 1; done
  RPC="$ANVIL_RPC"; DEPLOY_KEY="$ANVIL_PK"; SEND_EXTRA="--legacy --gas-price $GAS"
  echo "  forked block: $(cast block-number --rpc-url "$RPC")"
elif [ "$TARGET" = "mainnet" ]; then
  : "${DEPLOYER_PK:?set DEPLOYER_PK for mainnet deploy}"
  : "${CELO_SCAN_API_KEY:?set CELO_SCAN_API_KEY for Celoscan verification}"
  RPC="$RPC_FORK"; DEPLOY_KEY="$DEPLOYER_PK"; SEND_EXTRA="--legacy"
  echo "=== MAINNET broadcast via $RPC (deployer $(cast wallet address --private-key "$DEPLOY_KEY")) ==="
else
  echo "unknown target '$TARGET' (use: fork | mainnet)"; exit 1
fi

# ---------------------------------------------------------------------------
echo "=== deploying the 4 new implementations ==="
# Deploy creation bytecode; surface the cast error (and abort) on failure.
deploy(){
  local out addr
  out=$(cast send --rpc-url "$RPC" --private-key "$DEPLOY_KEY" $SEND_EXTRA --create "$1" --json 2>/tmp/deploy-err.log)
  addr=$(echo "$out" | jq -r '.contractAddress // empty' 2>/dev/null)
  if [ -z "$addr" ] || [ "$addr" = "null" ]; then
    echo "DEPLOY FAILED:" >&2; tail -5 /tmp/deploy-err.log >&2; return 1
  fi
  echo "$addr"
}
A_IMPL=$(deploy "$(jq -r .bytecode artifacts/contracts/Account.sol/Account.json)") || exit 1
M_IMPL=$(deploy "$(jq -r .bytecode artifacts/contracts/Manager.sol/Manager.json)") || exit 1
S_IMPL=$(deploy "$(jq -r .bytecode artifacts/contracts/SpecificGroupStrategy.sol/SpecificGroupStrategy.json)") || exit 1
LIB=$(deploy "$(jq -r .bytecode artifacts/contracts/common/linkedlists/AddressSortedLinkedList.sol/AddressSortedLinkedList.json)") || exit 1
# Link DefaultStrategy to the deployed library. The placeholder must be replaced
# by the full 40-hex address (lowercased, 0x stripped, LEADING ZEROS PRESERVED).
LIB_HEX=$(echo "${LIB#0x}" | tr 'A-Z' 'a-z')
DBC=$(jq -r .bytecode artifacts/contracts/DefaultStrategy.sol/DefaultStrategy.json | sed "s/__\$[0-9a-f]*\$__/$LIB_HEX/g")
case "$DBC" in *'__$'*) echo "ERROR: DefaultStrategy bytecode still has an unlinked library placeholder" >&2; exit 1;; esac
D_IMPL=$(deploy "$DBC") || exit 1
for v in "$A_IMPL:Account" "$M_IMPL:Manager" "$S_IMPL:SpecificGroupStrategy" "$D_IMPL:DefaultStrategy" "$LIB:AddressSortedLinkedList"; do
  [ -n "${v%%:*}" ] && [ "${v%%:*}" != null ] || { echo "deploy failed: ${v##*:}"; exit 1; }
  echo "  ${v##*:}: ${v%%:*}"
done

# ---------------------------------------------------------------------------
echo "=== building the governance proposal calldata ==="
P_ACC=$(cast calldata "upgradeTo(address)" "$A_IMPL")
P_MGR=$(cast calldata "upgradeTo(address)" "$M_IMPL")
P_SGS=$(cast calldata "upgradeTo(address)" "$S_IMPL")
P_DS=$(cast calldata "upgradeTo(address)" "$D_IMPL")
DESTS="[$ACCOUNT,$DS,$SGS,$MANAGER]"; VALUES="[0,0,0,0]"; PAYLOADS="[$P_ACC,$P_DS,$P_SGS,$P_MGR]"
GPE=$(cast calldata "governanceProposeAndExecute(address[],uint256[],bytes[])" "$DESTS" "$VALUES" "$PAYLOADS")
printf '[\n  { "value": "0", "to": "%s", "data": "%s" }\n]\n' "$MULTISIG" "$GPE" > /tmp/stcelo-fix-cgp.json
echo "  CGP tx -> to=$MULTISIG value=0 data=${GPE:0:50}... (${#GPE} chars)"
echo "  CGP JSON -> /tmp/stcelo-fix-cgp.json"

# ---------------------------------------------------------------------------
if [ "$TARGET" = "mainnet" ]; then
  echo "=== verifying implementations on Celoscan + Blockscout ==="
  printf 'module.exports = { "%s": "%s" };\n' "AddressSortedLinkedList" "$LIB" > /tmp/ds-libs.js
  verify_celoscan(){ # <addr> [extra hardhat args...]
    local a="$1"; shift
    echo "  [Celoscan] $a"; npx hardhat verify --network celo "$a" "$@" 2>&1 | tail -3 || true; }
  verify_blockscout(){ # <addr> <path:Contract> [extra forge args...]
    local a="$1" cp="$2"; shift 2
    echo "  [Blockscout] $a ($cp)"; forge verify-contract "$a" "$cp" \
      --verifier blockscout --verifier-url "$BLOCKSCOUT_API" \
      --compiler-version "$SOLC_VERSION" --evm-version "$EVM_VERSION" --watch "$@" 2>&1 | tail -3 || true; }

  verify_celoscan  "$LIB";    verify_blockscout "$LIB"    "$DS_LIB_PATH"
  verify_celoscan  "$A_IMPL"; verify_blockscout "$A_IMPL" "contracts/Account.sol:Account"
  verify_celoscan  "$M_IMPL"; verify_blockscout "$M_IMPL" "contracts/Manager.sol:Manager"
  verify_celoscan  "$S_IMPL"; verify_blockscout "$S_IMPL" "contracts/SpecificGroupStrategy.sol:SpecificGroupStrategy"
  verify_celoscan  "$D_IMPL" --libraries /tmp/ds-libs.js
  verify_blockscout "$D_IMPL" "contracts/DefaultStrategy.sol:DefaultStrategy" --libraries "$DS_LIB_PATH:$LIB"

  echo
  echo "MAINNET deploy + verification submitted. NEXT: file the CGP from"
  echo "/tmp/stcelo-fix-cgp.json (Governance -> MultiSig.governanceProposeAndExecute)."
  echo "The upgrade executes only after the proposal passes the Governance vote."
  exit 0
fi

# ---------------------------------------------------------------------------
# fork target: execute the proposal as Celo Governance and assert outcome.
echo "=== FORK TEST: execute the proposal as Celo Governance ==="
GOV=$(cast call "$REGISTRY" "getAddressForStringOrDie(string)(address)" "Governance" --rpc-url "$RPC")
echo "  Celo Governance: $GOV"
A_TSW=$(cast call $ACCOUNT "totalScheduledWithdrawals()(uint256)" --rpc-url $RPC | awk '{print $1}')
A_MGR=$(cast call $ACCOUNT "manager()(address)" --rpc-url $RPC)
A_OWN=$(cast call $ACCOUNT "owner()(address)" --rpc-url $RPC)
DS_TOTAL=$(cast call $DS "totalStCeloInStrategy()(uint256)" --rpc-url $RPC | awk '{print $1}')
DS_MAXW=$(cast call $DS "maxGroupsToWithdrawFrom()(uint256)" --rpc-url $RPC | awk '{print $1}')
SGS_LOCKED=$(cast call $SGS "totalStCeloLocked()(uint256)" --rpc-url $RPC | awk '{print $1}')

cast rpc --rpc-url $RPC anvil_impersonateAccount "$GOV" >/dev/null
cast rpc --rpc-url $RPC anvil_setBalance "$GOV" "$BIG" >/dev/null
ST=$(cast send --rpc-url $RPC --from "$GOV" --unlocked --legacy --gas-price $GAS \
  "$MULTISIG" "governanceProposeAndExecute(address[],uint256[],bytes[])" "$DESTS" "$VALUES" "$PAYLOADS" \
  --json 2>/dev/null | jq -r '.status')
[ "$ST" = "0x1" ] && pass "governanceProposeAndExecute succeeded" || fail "governance execute tx status=$ST"

for pair in "Account:$ACCOUNT:$A_IMPL" "Manager:$MANAGER:$M_IMPL" "SGS:$SGS:$S_IMPL" "DefaultStrategy:$DS:$D_IMPL"; do
  n=$(echo "$pair"|cut -d: -f1); a=$(echo "$pair"|cut -d: -f2); ex=$(echo "$pair"|cut -d: -f3)
  got=$(cast storage "$a" "$IMPL_SLOT" --rpc-url $RPC)
  [ "$(norm "$got")" = "$(norm "$ex")" ] && pass "$n proxy now points at new impl" || fail "$n impl slot got=$got want=$ex"
done
[ "$(cast call $ACCOUNT 'totalScheduledWithdrawals()(uint256)' --rpc-url $RPC|awk '{print $1}')" = "$A_TSW" ] && pass "Account.totalScheduledWithdrawals intact ($A_TSW)" || fail "Account.tsw changed"
[ "$(cast call $ACCOUNT 'manager()(address)' --rpc-url $RPC)" = "$A_MGR" ] && pass "Account.manager intact" || fail "Account.manager changed"
[ "$(cast call $ACCOUNT 'owner()(address)' --rpc-url $RPC)" = "$A_OWN" ] && pass "Account.owner intact (still MultiSig)" || fail "Account.owner changed"
[ "$(cast call $DS 'totalStCeloInStrategy()(uint256)' --rpc-url $RPC|awk '{print $1}')" = "$DS_TOTAL" ] && pass "DefaultStrategy.totalStCeloInStrategy intact ($DS_TOTAL)" || fail "DS.total changed"
[ "$(cast call $DS 'maxGroupsToWithdrawFrom()(uint256)' --rpc-url $RPC|awk '{print $1}')" = "$DS_MAXW" ] && pass "DefaultStrategy.maxGroupsToWithdrawFrom intact ($DS_MAXW)" || fail "DS.maxW changed"
[ "$(cast call $SGS 'totalStCeloLocked()(uint256)' --rpc-url $RPC|awk '{print $1}')" = "$SGS_LOCKED" ] && pass "SpecificGroupStrategy.totalStCeloLocked intact ($SGS_LOCKED)" || fail "SGS.locked changed"
cast call $ACCOUNT "getRealisableCeloForGroup(address)(uint256)" 0x81AE1C73A326325216E25ff1af9EA3871195036E --rpc-url $RPC >/dev/null 2>&1 \
  && pass "Account.getRealisableCeloForGroup live (new code active)" || fail "new Account code not live"
chk(){ v=$(cast call "$1" "getVersionNumber()(uint256,uint256,uint256,uint256)" --rpc-url $RPC 2>/dev/null|tr '\n' ' '|sed 's/ *$//'); [ "$v" = "$2" ] && pass "$3 version $v" || fail "$3 version got [$v] want [$2]"; }
chk $ACCOUNT "1 2 1 0" Account; chk $DS "1 2 0 0" DefaultStrategy; chk $SGS "1 1 1 0" SpecificGroupStrategy; chk $MANAGER "1 3 1 0" Manager

echo
[ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED - Governance release via MultiSig.governanceProposeAndExecute works; storage preserved, new code live. CGP in /tmp/stcelo-fix-cgp.json" || echo "$FAIL CHECK(S) FAILED"
exit $FAIL
