#!/usr/bin/env bash
#
# release-stuck-withdrawal-fix.sh
# ===============================
# Releases the stuck-withdrawal fix by upgrading the four stCELO
# implementations (Account, DefaultStrategy, SpecificGroupStrategy, Manager)
# via a CELO GOVERNANCE proposal.
#
# The stCELO proxies are owned by the stCELO MultiSig, but the MultiSig exposes
# `governanceProposeAndExecute(destinations, values, payloads)` gated by
# `onlyGovernance` - so Celo Governance can execute a batch of calls through it
# directly (no owner timelock). The release is therefore a single CGP
# transaction: Governance -> MultiSig.governanceProposeAndExecute([4 proxies],
# [0,0,0,0], [upgradeTo(newImpl) x4]).
#
# Modes:
#   (default) FORK TEST - fork mainnet, deploy impls, impersonate Celo
#             Governance, execute the proposal, and assert upgrades + that
#             pre-existing storage is intact and new code is live.
#   --emit-only - deploy impls against the fork (or a node) and print the CGP
#             transaction (to / value / data) + a celocli-style JSON, without
#             asserting. Use the deployed impl addresses from a real broadcast
#             when filing the actual CGP.
#
# Requirements: anvil, cast, jq, python3, yarn (foundry in PATH or ~/.foundry/bin).
# RPC: https://forno.celo.org (override via CELO_RPC_URL).
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODE="${1:-fork-test}"
RPC_FORK="${CELO_RPC_URL:-https://forno.celo.org}"
PORT=8591; RPC="http://127.0.0.1:${PORT}"
GAS=25000000000; BIG=0x10000000000000000000000
# anvil default funded key (deployer in the fork).
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# --- mainnet addresses ---
REGISTRY=0x000000000000000000000000000000000000ce10
MULTISIG=0x78DaA21FcE4D30E74fF745Da3204764a0ad40179
ACCOUNT=0x4aAD04D41FD7fd495503731C5a2579e19054C432
MANAGER=0x0239b96D10a434a56CC9E09383077A0490cF9398
DS=0x3A3ed74B1cC543D5EB323f70ac2F19977a0eA088
SGS=0xb88af6EAc9cd146D8b03b66708EF76beBD937871
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc

FAIL=0; pass(){ echo "  [PASS] $*"; }; fail(){ echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
cleanup(){ pkill -f "anvil .*port ${PORT}" 2>/dev/null || true; }
trap cleanup EXIT

start_anvil(){
  anvil --fork-url "$RPC_FORK" --celo --port "$PORT" --host 127.0.0.1 \
    --disable-code-size-limit --base-fee "$GAS" --gas-price "$GAS" >/tmp/anvil-release.log 2>&1 &
  for i in $(seq 1 60); do cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && return 0; sleep 1; done
  echo "anvil failed to start"; tail -20 /tmp/anvil-release.log; exit 1
}

deploy(){ cast send --rpc-url "$RPC" --private-key "$PK" --legacy --gas-price "$GAS" --create "$1" --json 2>/dev/null | jq -r .contractAddress; }

echo "=== compiling ==="
yarn --silent compile >/tmp/release-compile.log 2>&1 || { echo "compile failed"; tail /tmp/release-compile.log; exit 1; }

echo "=== starting anvil fork of $RPC_FORK ==="
start_anvil
echo "  forked block: $(cast block-number --rpc-url "$RPC")"

echo "=== deploying the 4 new implementations ==="
A_IMPL=$(deploy "$(jq -r .bytecode artifacts/contracts/Account.sol/Account.json)")
M_IMPL=$(deploy "$(jq -r .bytecode artifacts/contracts/Manager.sol/Manager.json)")
S_IMPL=$(deploy "$(jq -r .bytecode artifacts/contracts/SpecificGroupStrategy.sol/SpecificGroupStrategy.json)")
LIB=$(deploy "$(jq -r .bytecode artifacts/contracts/common/linkedlists/AddressSortedLinkedList.sol/AddressSortedLinkedList.json)")
DBC=$(jq -r .bytecode artifacts/contracts/DefaultStrategy.sol/DefaultStrategy.json | sed "s/__\$[0-9a-f]*\$__/$(echo "${LIB#0x}" | tr 'A-Z' 'a-z')/g")
D_IMPL=$(deploy "$DBC")
for v in "$A_IMPL:Account" "$M_IMPL:Manager" "$S_IMPL:SpecificGroupStrategy" "$D_IMPL:DefaultStrategy"; do
  [ -n "${v%%:*}" ] && [ "${v%%:*}" != null ] || { echo "deploy failed: ${v##*:}"; exit 1; }
  echo "  ${v##*:} impl: ${v%%:*}"
done
echo "  (DefaultStrategy linked to AddressSortedLinkedList $LIB)"

echo "=== building the governance proposal calldata ==="
# Per-proxy upgradeTo(newImpl) payloads.
P_ACC=$(cast calldata "upgradeTo(address)" "$A_IMPL")
P_MGR=$(cast calldata "upgradeTo(address)" "$M_IMPL")
P_SGS=$(cast calldata "upgradeTo(address)" "$S_IMPL")
P_DS=$(cast calldata "upgradeTo(address)" "$D_IMPL")
# The single CGP transaction: Governance -> MultiSig.governanceProposeAndExecute(...).
DESTS="[$ACCOUNT,$DS,$SGS,$MANAGER]"
VALUES="[0,0,0,0]"
PAYLOADS="[$P_ACC,$P_DS,$P_SGS,$P_MGR]"
GPE=$(cast calldata "governanceProposeAndExecute(address[],uint256[],bytes[])" "$DESTS" "$VALUES" "$PAYLOADS")
echo "  CGP transaction:"
echo "    to:    $MULTISIG"
echo "    value: 0"
echo "    data:  ${GPE:0:74}... (${#GPE} chars)"
# celocli-style proposal JSON (raw form).
PROPOSAL_JSON=$(cat <<JSON
[
  { "value": "0", "to": "$MULTISIG", "data": "$GPE" }
]
JSON
)
echo "$PROPOSAL_JSON" > /tmp/stcelo-fix-cgp.json
echo "  wrote CGP JSON -> /tmp/stcelo-fix-cgp.json"

if [ "$MODE" = "--emit-only" ]; then
  echo; echo "emit-only mode: proposal built, not executed."
  echo "NOTE: deploy the impls on mainnet (real broadcast) and substitute their"
  echo "      addresses before filing the CGP."
  exit 0
fi

echo "=== FORK TEST: execute the proposal as Celo Governance ==="
GOV=$(cast call "$REGISTRY" "getAddressForStringOrDie(string)(address)" "Governance" --rpc-url "$RPC")
echo "  Celo Governance: $GOV"
# snapshot pre-existing storage
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
[ "$ST" = "0x1" ] && pass "governanceProposeAndExecute succeeded (Governance executed the batch)" || fail "governance execute tx status=$ST"

# impl slots updated
norm(){ echo "$1" | tr 'A-Z' 'a-z' | sed 's/^0x0*//'; }
for pair in "Account:$ACCOUNT:$A_IMPL" "Manager:$MANAGER:$M_IMPL" "SGS:$SGS:$S_IMPL" "DefaultStrategy:$DS:$D_IMPL"; do
  n=$(echo "$pair"|cut -d: -f1); a=$(echo "$pair"|cut -d: -f2); ex=$(echo "$pair"|cut -d: -f3)
  got=$(cast storage "$a" "$IMPL_SLOT" --rpc-url $RPC)
  [ "$(norm "$got")" = "$(norm "$ex")" ] && pass "$n proxy now points at new impl" || fail "$n impl slot got=$got want=$ex"
done
# pre-existing storage intact
[ "$(cast call $ACCOUNT 'totalScheduledWithdrawals()(uint256)' --rpc-url $RPC|awk '{print $1}')" = "$A_TSW" ] && pass "Account.totalScheduledWithdrawals intact ($A_TSW)" || fail "Account.tsw changed"
[ "$(cast call $ACCOUNT 'manager()(address)' --rpc-url $RPC)" = "$A_MGR" ] && pass "Account.manager intact" || fail "Account.manager changed"
[ "$(cast call $ACCOUNT 'owner()(address)' --rpc-url $RPC)" = "$A_OWN" ] && pass "Account.owner intact (still MultiSig)" || fail "Account.owner changed"
[ "$(cast call $DS 'totalStCeloInStrategy()(uint256)' --rpc-url $RPC|awk '{print $1}')" = "$DS_TOTAL" ] && pass "DefaultStrategy.totalStCeloInStrategy intact ($DS_TOTAL)" || fail "DS.total changed"
[ "$(cast call $DS 'maxGroupsToWithdrawFrom()(uint256)' --rpc-url $RPC|awk '{print $1}')" = "$DS_MAXW" ] && pass "DefaultStrategy.maxGroupsToWithdrawFrom intact ($DS_MAXW)" || fail "DS.maxW changed"
[ "$(cast call $SGS 'totalStCeloLocked()(uint256)' --rpc-url $RPC|awk '{print $1}')" = "$SGS_LOCKED" ] && pass "SpecificGroupStrategy.totalStCeloLocked intact ($SGS_LOCKED)" || fail "SGS.locked changed"
# new code live + versions
cast call $ACCOUNT "getRealisableCeloForGroup(address)(uint256)" 0x81AE1C73A326325216E25ff1af9EA3871195036E --rpc-url $RPC >/dev/null 2>&1 \
  && pass "Account.getRealisableCeloForGroup live (new code active)" || fail "new Account code not live"
chk(){ v=$(cast call "$1" "getVersionNumber()(uint256,uint256,uint256,uint256)" --rpc-url $RPC 2>/dev/null|tr '\n' ' '|sed 's/ *$//'); [ "$v" = "$2" ] && pass "$3 version $v" || fail "$3 version got [$v] want [$2]"; }
chk $ACCOUNT "1 2 1 0" Account
chk $DS "1 2 0 0" DefaultStrategy
chk $SGS "1 1 1 0" SpecificGroupStrategy
chk $MANAGER "1 3 1 0" Manager

echo
if [ $FAIL -eq 0 ]; then
  echo "ALL CHECKS PASSED - Celo Governance can release the fix via the MultiSig:"
  echo "  Governance.execute -> MultiSig.governanceProposeAndExecute -> upgradeTo x4"
  echo "  storage preserved, new code live. CGP tx in /tmp/stcelo-fix-cgp.json"
else
  echo "$FAIL CHECK(S) FAILED"
fi
exit $FAIL
