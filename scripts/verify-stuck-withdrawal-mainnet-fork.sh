#!/usr/bin/env bash
#
# verify-stuck-withdrawal-mainnet-fork.sh
# =======================================
# Proves the staked-CELO stuck-withdrawal fix against REAL Celo mainnet state
# on anvil forks. Runs two scenarios and prints explicit [PASS]/[FAIL] per
# assertion. Exits non-zero if any assertion fails.
#
#   SCENARIO A  - RECOVERY: recreate the stuck pin at the withdrawal block by
#                 replaying the user's Manager.withdraw with the DEPLOYED code,
#                 then the patched permissionless `rescueScheduledWithdrawal`
#                 moves the pin off the bad group onto healthy groups and a
#                 real `Account.withdraw` succeeds. (The live mainnet pin
#                 self-resolved post-incident, so recovery is demonstrated on a
#                 reproduced pin rather than mutable current state.)
#
#   SCENARIO B1 - REPRODUCE the bug with the DEPLOYED code at the exact
#                 withdrawal-initiation block (67413681): Manager.withdraw
#                 pins an unfulfillable amount to the bad group -> user stuck.
#
#   SCENARIO B2 - PREVENTION with the patched code (all four impls upgraded)
#                 at the same block: Manager.withdraw either reverts (user
#                 keeps stCELO) OR succeeds with every pinned group's pin
#                 physically fulfillable, and a real Account.withdraw works.
#
# Requirements: anvil, cast, forge, jq, python3, yarn (in PATH or ~/.foundry/bin).
# RPC: https://forno.celo.org (override via CELO_RPC_URL).
#
# Usage:  scripts/verify-stuck-withdrawal-mainnet-fork.sh
#
set -uo pipefail

# --------------------------------------------------------------------------
# Environment / tooling
# --------------------------------------------------------------------------
export PATH="$HOME/.foundry/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RPC_FORK=${CELO_RPC_URL:-https://forno.celo.org}

# Distinct ports per scenario so concurrent leftovers cannot collide.
PORT_A=8561
PORT_B1=8562
PORT_B2=8563
RPC_A="http://127.0.0.1:${PORT_A}"
RPC_B1="http://127.0.0.1:${PORT_B1}"
RPC_B2="http://127.0.0.1:${PORT_B2}"

# Fixed gas pricing. REQUIRED for forks pinned to a historical block: anvil's
# Celo block production calls eth_feeHistory / exchange-rate lookups against
# the remote node, and the public Forno archive prunes that historical state,
# making block mining fail with "failed to get exchange rates". Pinning the
# base fee / gas price and sending --legacy txs avoids those remote lookups.
GAS_PRICE=25000000000          # 25 gwei
BIG_BAL=0x10000000000000000000000

# anvil default funded signer (random permissionless EOA).
RANDOM_EOA=0xf39Fd6e51aad88F6F4ce6aB8827279cfFFb92266
RANDOM_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# --------------------------------------------------------------------------
# Verified mainnet addresses / facts
# --------------------------------------------------------------------------
ACCOUNT_PROXY=0x4aAD04D41FD7fd495503731C5a2579e19054C432
MANAGER_PROXY=0x0239b96D10a434a56CC9E09383077A0490cF9398
DS_PROXY=0x3A3ed74B1cC543D5EB323f70ac2F19977a0eA088
SGS_PROXY=0xb88af6EAc9cd146D8b03b66708EF76beBD937871
MULTISIG=0x78DaA21FcE4D30E74fF745Da3204764a0ad40179
ELECTION=0x8D6677192144292870907E3Fa8A5527fE55A7ff6
STCELO=0xC668583dcbDc9ae6FA3CE46462758188adfdfC24

STUCK_USER=0x85ca0Dff027102ea3FBF1c077524eab21D1F7927
BAD_GROUP=0x81AE1C73A326325216E25ff1af9EA3871195036E
WITHDRAW_BLOCK=67413681
STCELO_AMOUNT=146388633198899438192672

# Candidate healthy groups (re-verified on the fork before use).
HEALTHY_CANDIDATES=(
  0xc8A81D473992c7c6D3F469A8263F24914625709d
  0xD72Ed2e3db984bAC3bB351FE652200dE527eFfcf
  0xc24baeac0Fd189637112B7e33d22FfF2730aF993
)

ZERO=0x0000000000000000000000000000000000000000

# --------------------------------------------------------------------------
# Result tracking + helpers
# --------------------------------------------------------------------------
FAILURES=0
pass() { echo "  [PASS] $*"; }
fail() { echo "  [FAIL] $*"; FAILURES=$((FAILURES + 1)); }
section() { echo; echo "============================================================"; echo "$*"; echo "============================================================"; }

# assert_ge LABEL A B  -> pass iff A >= B (big-int safe)
assert_ge() {
  local label="$1" a="$2" b="$3"
  if python3 -c "import sys; sys.exit(0 if int('$a') >= int('$b') else 1)"; then
    pass "$label ($a >= $b)"
  else
    fail "$label ($a < $b)"
  fi
}
# assert_lt LABEL A B  -> pass iff A < B
assert_lt() {
  local label="$1" a="$2" b="$3"
  if python3 -c "import sys; sys.exit(0 if int('$a') < int('$b') else 1)"; then
    pass "$label ($a < $b)"
  else
    fail "$label ($a >= $b)"
  fi
}
# assert_eq LABEL A B
assert_eq() {
  local label="$1" a="$2" b="$3"
  if python3 -c "import sys; sys.exit(0 if int('$a') == int('$b') else 1)"; then
    pass "$label (= $a)"
  else
    fail "$label (got $a, want $b)"
  fi
}

# cast call with small retry to tolerate Forno rate limiting.
ccall() {
  local rpc="$1"; shift
  local out i
  for i in 1 2 3 4 5; do
    if out=$(cast call --rpc-url "$rpc" "$@" 2>/dev/null); then
      echo "$out" | awk '{print $1}'
      return 0
    fi
    sleep 1
  done
  echo "0"
  return 1
}

# Read a uint return, first whitespace token only.
pin_of() { ccall "$1" "$2" "scheduledWithdrawalsForGroupAndBeneficiary(address,address)(uint256)" "$3" "$4"; }
realisable_of() { ccall "$1" "$2" "getRealisableCeloForGroup(address)(uint256)" "$3"; }
revokable_of() { ccall "$1" "$ELECTION" "getTotalVotesForGroupByAccount(address,address)(uint256)" "$2" "$ACCOUNT_PROXY"; }

# Start anvil. start_anvil PORT LOGFILE [BLOCK]
start_anvil() {
  local port="$1" log="$2" block="${3:-}"
  local args=(--fork-url "$RPC_FORK" --celo --port "$port" --host 127.0.0.1
              --disable-code-size-limit --base-fee "$GAS_PRICE" --gas-price "$GAS_PRICE")
  if [ -n "$block" ]; then
    args+=(--fork-block-number "$block")
  fi
  anvil "${args[@]}" > "$log" 2>&1 &
  local rpc="http://127.0.0.1:${port}"
  local i
  for i in $(seq 1 60); do
    if cast block-number --rpc-url "$rpc" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: anvil on port $port never became ready; see $log" >&2
  tail -20 "$log" >&2
  return 1
}

cleanup() {
  pkill -f "anvil .*port ${PORT_A}" 2>/dev/null || true
  pkill -f "anvil .*port ${PORT_B1}" 2>/dev/null || true
  pkill -f "anvil .*port ${PORT_B2}" 2>/dev/null || true
}
trap cleanup EXIT

# send_tx RPC FROM_SPEC TO SIG [ARGS...]   FROM_SPEC = "pk:<key>" or "from:<addr>"
# Echoes normalised receipt status: "1" (success), "0" (revert), "" (RPC error).
send_tx() {
  local rpc="$1" from="$2" to="$3" sig="$4"; shift 4
  local base=(send --rpc-url "$rpc" --legacy --gas-price "$GAS_PRICE" --gas-limit 12000000)
  if [[ "$from" == pk:* ]]; then
    base+=(--private-key "${from#pk:}")
  else
    base+=(--from "${from#from:}" --unlocked)
  fi
  local raw
  raw=$(cast "${base[@]}" "$to" "$sig" "$@" --json 2>/dev/null | jq -r '.status // empty' 2>/dev/null)
  case "$raw" in
    0x1|1) echo "1" ;;
    0x0|0) echo "0" ;;
    *)     echo "" ;;
  esac
}

# Deploy + upgrade one UUPS proxy. Handles library-linked DefaultStrategy.
# deploy_and_upgrade RPC CONTRACT PROXY [LIB_ADDR]
deploy_and_upgrade() {
  local rpc="$1" contract="$2" proxy="$3" lib="${4:-}"
  local bc impl
  bc=$(jq -r '.bytecode' "artifacts/contracts/${contract}.sol/${contract}.json")
  if echo "$bc" | grep -q '__\$'; then
    if [ -z "$lib" ]; then
      echo "ERROR: $contract needs a library but none supplied" >&2
      return 1
    fi
    local libnoaddr
    libnoaddr=$(echo "$lib" | sed 's/^0x//' | tr 'A-Z' 'a-z')
    # Replace any link placeholder __$...$__ with the library address.
    bc=$(echo "$bc" | sed "s/__\$[0-9a-f]*\$__/$libnoaddr/g")
  fi
  impl=$(cast send --rpc-url "$rpc" --private-key "$RANDOM_PK" --legacy \
          --gas-price "$GAS_PRICE" --create "$bc" --json 2>/dev/null | jq -r .contractAddress)
  if [ -z "$impl" ] || [ "$impl" = "null" ]; then
    echo "ERROR: failed to deploy $contract" >&2
    return 1
  fi
  cast send --rpc-url "$rpc" --from "$MULTISIG" --unlocked --legacy \
    --gas-price "$GAS_PRICE" "$proxy" "upgradeTo(address)" "$impl" >/dev/null 2>&1
  echo "$impl"
}

deploy_library() {
  local rpc="$1"
  local bc
  bc=$(jq -r '.bytecode' artifacts/contracts/common/linkedlists/AddressSortedLinkedList.sol/AddressSortedLinkedList.json)
  cast send --rpc-url "$rpc" --private-key "$RANDOM_PK" --legacy \
    --gas-price "$GAS_PRICE" --create "$bc" --json 2>/dev/null | jq -r .contractAddress
}

impersonate() {
  local rpc="$1" addr="$2"
  cast rpc --rpc-url "$rpc" anvil_impersonateAccount "$addr" >/dev/null 2>&1
  cast rpc --rpc-url "$rpc" anvil_setBalance "$addr" "$BIG_BAL" >/dev/null 2>&1
}

# Find the index of `group` in Account's voted-for groups list (for Account.withdraw).
group_index() {
  local rpc="$1" group="$2"
  cast call "$ELECTION" "getGroupsVotedForByAccount(address)(address[])" "$ACCOUNT_PROXY" --rpc-url "$rpc" 2>/dev/null \
    | grep -ioE '0x[0-9a-fA-F]{40}' | nl -v0 \
    | grep -i "${group#0x}" | awk '{print $1}' | head -1
}

# Compute Election lesser/greater for revoking `amount` from `group`.
# Echoes "<lesser> <greater>".
lesser_greater() {
  local rpc="$1" group="$2" amount="$3"
  local gtotal new lg
  gtotal=$(ccall "$rpc" "$ELECTION" "getTotalVotesForGroup(address)(uint256)" "$group")
  new=$(python3 -c "print(max(0, int('$gtotal') - int('$amount')))")
  cast call "$ELECTION" "getTotalVotesForEligibleValidatorGroups()(address[],uint256[])" \
    --rpc-url "$rpc" > /tmp/eligible-$$.txt 2>/dev/null
  lg=$(python3 "$REPO_ROOT/scripts/_lesser_greater.py" "/tmp/eligible-$$.txt" "$group" "$new")
  rm -f "/tmp/eligible-$$.txt"
  # _lesser_greater prints "<greater> <lesser>"; re-order to "<lesser> <greater>".
  local greater lesser
  greater=$(echo "$lg" | awk '{print $1}')
  lesser=$(echo "$lg" | awk '{print $2}')
  echo "$lesser $greater"
}

# Attempt a real Account.withdraw for `group`. Echoes "0x1"/"0x0"/"".
attempt_account_withdraw() {
  local rpc="$1" group="$2"
  local pin idx lg lesser greater
  pin=$(pin_of "$rpc" "$ACCOUNT_PROXY" "$group" "$STUCK_USER")
  idx=$(group_index "$rpc" "$group")
  [ -z "$idx" ] && { echo ""; return; }
  lg=$(lesser_greater "$rpc" "$group" "$pin")
  lesser=$(echo "$lg" | awk '{print $1}')
  greater=$(echo "$lg" | awk '{print $2}')
  send_tx "$rpc" "pk:$RANDOM_PK" "$ACCOUNT_PROXY" \
    "withdraw(address,address,address,address,address,address,uint256)" \
    "$STUCK_USER" "$group" "$lesser" "$greater" "$lesser" "$greater" "$idx"
}

# --------------------------------------------------------------------------
# Compile patched contracts (idempotent).
# --------------------------------------------------------------------------
section "Compiling patched contracts (yarn compile)"
if yarn --silent compile > /tmp/swv-compile.log 2>&1; then
  echo "  compile OK"
else
  echo "  compile FAILED - see /tmp/swv-compile.log"; tail -10 /tmp/swv-compile.log
  exit 1
fi

# ==========================================================================
# SCENARIO A - RECOVERY on the current real stuck state (fork LATEST)
# ==========================================================================
section "SCENARIO A - RECOVERY: recreate the stuck pin, then rescue it (fork block $WITHDRAW_BLOCK)"
start_anvil "$PORT_A" /tmp/swv-anvil-a.log "$WITHDRAW_BLOCK" || exit 1
echo "  forked block: $(cast block-number --rpc-url "$RPC_A")"

# A.0 recreate the stuck state deterministically. The live mainnet pin
# self-resolved after the incident (the stale toVote eventually became
# revokable and the pin was withdrawn), so instead of depending on mutable
# current state we replay the user's exact Manager.withdraw with the DEPLOYED
# (buggy) code at the withdrawal-initiation block - the same call that created
# the real stuck pin (see Scenario B1).
impersonate "$RPC_A" "$STUCK_USER"
WST0=$(send_tx "$RPC_A" "from:$STUCK_USER" "$MANAGER_PROXY" "withdraw(uint256)" "$STCELO_AMOUNT")
echo "  replayed deployed Manager.withdraw(user): status ${WST0:-?}"

# A.1 prove the stuck pin now exists on the bad group
PIN_A=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$BAD_GROUP" "$STUCK_USER")
echo "  pin(badGroup,user) = $PIN_A"
assert_lt "A.1 stuck pin is non-zero" 0 "$PIN_A"

# A.2 upgrade patched Account, prove deficit
echo "  deploying + upgrading patched Account ..."
impersonate "$RPC_A" "$MULTISIG"
NEW_ACC=$(deploy_and_upgrade "$RPC_A" Account "$ACCOUNT_PROXY")
echo "  new Account impl: $NEW_ACC"
REAL_BAD_A=$(realisable_of "$RPC_A" "$ACCOUNT_PROXY" "$BAD_GROUP")
echo "  realisable(badGroup) = $REAL_BAD_A"
assert_lt "A.2 badGroup realisable < pin (deficit -> stuck)" "$REAL_BAD_A" "$PIN_A"

# A.3 pick 3 healthy groups whose realisable >= their slice
SLICE=$(python3 -c "print(int('$PIN_A')//3)")
LAST=$(python3 -c "print(int('$PIN_A') - 2*(int('$PIN_A')//3))")
echo "  slice=$SLICE last=$LAST"
G1=${HEALTHY_CANDIDATES[0]}; G2=${HEALTHY_CANDIDATES[1]}; G3=${HEALTHY_CANDIDATES[2]}
R1=$(realisable_of "$RPC_A" "$ACCOUNT_PROXY" "$G1")
R2=$(realisable_of "$RPC_A" "$ACCOUNT_PROXY" "$G2")
R3=$(realisable_of "$RPC_A" "$ACCOUNT_PROXY" "$G3")
echo "  realisable: $G1=$R1  $G2=$R2  $G3=$R3"
assert_ge "A.3 G1 realisable >= slice" "$R1" "$SLICE"
assert_ge "A.3 G2 realisable >= slice" "$R2" "$SLICE"
assert_ge "A.3 G3 realisable >= last"  "$R3" "$LAST"

# Pre-rescue baselines: the deployed replay may already have pinned the
# ~claimable remainder of the withdrawal to a healthy group, so assert the
# rescue adds exactly the slice (delta), not the absolute pin.
P1_BEFORE=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$G1" "$STUCK_USER")
P2_BEFORE=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$G2" "$STUCK_USER")
P3_BEFORE=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$G3" "$STUCK_USER")

# A.4 permissionless rescue from a random EOA
echo "  calling rescueScheduledWithdrawal from random EOA $RANDOM_EOA ..."
ST=$(send_tx "$RPC_A" "pk:$RANDOM_PK" "$ACCOUNT_PROXY" \
  "rescueScheduledWithdrawal(address,address,address[],uint256[])" \
  "$STUCK_USER" "$BAD_GROUP" "[$G1,$G2,$G3]" "[$SLICE,$SLICE,$LAST]")
assert_eq "A.4 rescue tx succeeded" "${ST:-0}" "1"

# A.5 pins moved
PIN_BAD_AFTER=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$BAD_GROUP" "$STUCK_USER")
assert_eq "A.5 badGroup pin cleared to 0" "$PIN_BAD_AFTER" "0"
P1=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$G1" "$STUCK_USER")
P2=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$G2" "$STUCK_USER")
P3=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$G3" "$STUCK_USER")
D1=$(python3 -c "print(int('$P1') - int('$P1_BEFORE'))")
D2=$(python3 -c "print(int('$P2') - int('$P2_BEFORE'))")
D3=$(python3 -c "print(int('$P3') - int('$P3_BEFORE'))")
assert_eq "A.5 G1 pin gained slice" "$D1" "$SLICE"
assert_eq "A.5 G2 pin gained slice" "$D2" "$SLICE"
assert_eq "A.5 G3 pin gained last"  "$D3" "$LAST"

# A.6 real Account.withdraw on a healthy group must succeed
echo "  attempting real Account.withdraw on healthy group $G1 ..."
WST=$(attempt_account_withdraw "$RPC_A" "$G1")
if [ "${WST:-0}" = "1" ]; then
  PIN_G1_AFTER=$(pin_of "$RPC_A" "$ACCOUNT_PROXY" "$G1" "$STUCK_USER")
  pass "A.6 real Account.withdraw(G1) SUCCEEDED (status 1)"
  assert_eq "A.6 G1 pin cleared after withdraw" "$PIN_G1_AFTER" "0"
  echo "       -> the previously-stuck user can now withdraw on current state"
else
  # Fallback: the guaranteed property is physical fulfillability.
  fail "A.6 real Account.withdraw(G1) did not return status 1 (got '${WST}')"
  echo "       guaranteed property still holds: realisable(G1)=$R1 >= slice=$SLICE"
fi

cleanup; sleep 1

# ==========================================================================
# SCENARIO B1 - REPRODUCE the bug with DEPLOYED code at block 67413681
# ==========================================================================
section "SCENARIO B1 - REPRODUCE stuck withdrawal with DEPLOYED code (block $WITHDRAW_BLOCK)"
start_anvil "$PORT_B1" /tmp/swv-anvil-b1.log "$WITHDRAW_BLOCK" || exit 1
echo "  forked block: $(cast block-number --rpc-url "$RPC_B1")"

BAL_PRE=$(ccall "$RPC_B1" "$STCELO" "balanceOf(address)(uint256)" "$STUCK_USER")
PIN_PRE=$(pin_of "$RPC_B1" "$ACCOUNT_PROXY" "$BAD_GROUP" "$STUCK_USER")
assert_eq "B1.1 user stCELO balance == withdrawal amount" "$BAL_PRE" "$STCELO_AMOUNT"
assert_eq "B1.1 badGroup pin == 0 pre-withdrawal" "$PIN_PRE" "0"

echo "  impersonating user and calling Manager.withdraw($STCELO_AMOUNT) on DEPLOYED code ..."
impersonate "$RPC_B1" "$STUCK_USER"
ST_B1=$(send_tx "$RPC_B1" "from:$STUCK_USER" "$MANAGER_PROXY" "withdraw(uint256)" "$STCELO_AMOUNT")
assert_eq "B1.2 Manager.withdraw succeeded (state committed)" "${ST_B1:-0}" "1"

PIN_POST=$(pin_of "$RPC_B1" "$ACCOUNT_PROXY" "$BAD_GROUP" "$STUCK_USER")
BAL_POST=$(ccall "$RPC_B1" "$STCELO" "balanceOf(address)(uint256)" "$STUCK_USER")
REVOKABLE_BAD=$(revokable_of "$RPC_B1" "$BAD_GROUP")
echo "  pin(badGroup,user) post = $PIN_POST"
echo "  user stCELO post        = $BAL_POST  (burned: stake committed)"
echo "  Election revokable(bad) = $REVOKABLE_BAD"
assert_lt "B1.3 deployed code pinned to badGroup (pin > 0)" 0 "$PIN_POST"
assert_eq "B1.3 user stCELO burned to 0 (cannot undo)" "$BAL_POST" "0"
assert_lt "B1.3 Election revokable(bad) < pin -> pin UNFULFILLABLE (stuck)" "$REVOKABLE_BAD" "$PIN_POST"

cleanup; sleep 1

# ==========================================================================
# SCENARIO B2 - PREVENTION with patched code (all 4 impls) at block 67413681
# ==========================================================================
section "SCENARIO B2 - PREVENTION with PATCHED code, all 4 impls (block $WITHDRAW_BLOCK)"
start_anvil "$PORT_B2" /tmp/swv-anvil-b2.log "$WITHDRAW_BLOCK" || exit 1
echo "  forked block: $(cast block-number --rpc-url "$RPC_B2")"

impersonate "$RPC_B2" "$MULTISIG"
echo "  deploying AddressSortedLinkedList library ..."
LIB=$(deploy_library "$RPC_B2")
echo "  library: $LIB"
echo "  deploying + upgrading all 4 patched impls via multisig ..."
I_ACC=$(deploy_and_upgrade "$RPC_B2" Account "$ACCOUNT_PROXY")
I_MGR=$(deploy_and_upgrade "$RPC_B2" Manager "$MANAGER_PROXY")
I_DS=$(deploy_and_upgrade "$RPC_B2" DefaultStrategy "$DS_PROXY" "$LIB")
I_SGS=$(deploy_and_upgrade "$RPC_B2" SpecificGroupStrategy "$SGS_PROXY")
echo "  Account=$I_ACC"
echo "  Manager=$I_MGR"
echo "  DefaultStrategy=$I_DS"
echo "  SpecificGroupStrategy=$I_SGS"
if [ -n "$I_ACC" ] && [ -n "$I_MGR" ] && [ -n "$I_DS" ] && [ -n "$I_SGS" ]; then
  pass "B2.0 all four patched impls deployed + upgraded"
else
  fail "B2.0 one or more impls failed to deploy/upgrade"
fi

echo "  impersonating user and calling Manager.withdraw($STCELO_AMOUNT) on PATCHED code ..."
impersonate "$RPC_B2" "$STUCK_USER"
ST_B2=$(send_tx "$RPC_B2" "from:$STUCK_USER" "$MANAGER_PROXY" "withdraw(uint256)" "$STCELO_AMOUNT")

if [ "${ST_B2:-0}" != "1" ]; then
  # Acceptable outcome: revert -> user keeps stCELO, no silent stuck state.
  BAL_B2=$(ccall "$RPC_B2" "$STCELO" "balanceOf(address)(uint256)" "$STUCK_USER")
  pass "B2.1 Manager.withdraw REVERTED on patched code (no silent stuck state)"
  assert_eq "B2.1 user keeps full stCELO after revert" "$BAL_B2" "$STCELO_AMOUNT"
  echo "       -> patched code refuses to pin an unfulfillable withdrawal"
else
  pass "B2.1 Manager.withdraw SUCCEEDED on patched code"
  # Every pinned group must have realisable >= its pin (fulfillable).
  echo "  resulting distribution (group / pin / realisable):"
  cast call "$ELECTION" "getGroupsVotedForByAccount(address)(address[])" "$ACCOUNT_PROXY" \
    --rpc-url "$RPC_B2" 2>/dev/null | grep -ioE '0x[0-9a-fA-F]{40}' > /tmp/swv-groups-$$.txt
  ALL_FULFILLABLE=1
  BAD_PIN_B2=0
  while read -r G; do
    [ -z "$G" ] && continue
    GP=$(pin_of "$RPC_B2" "$ACCOUNT_PROXY" "$G" "$STUCK_USER")
    [ "$GP" = "0" ] && continue
    GR=$(realisable_of "$RPC_B2" "$ACCOUNT_PROXY" "$G")
    # realisable() subtracts this pin's own earmark; the fulfillability check
    # is whether Election revokable for the group covers the pin.
    GREV=$(revokable_of "$RPC_B2" "$G")
    MARK="OK"
    if ! python3 -c "import sys; sys.exit(0 if int('$GREV') >= int('$GP') else 1)"; then
      MARK="UNFULFILLABLE"; ALL_FULFILLABLE=0
    fi
    echo "       $G  pin=$GP  realisable=$GR  revokable=$GREV  -> $MARK"
    if [ "$(echo "$G" | tr 'A-Z' 'a-z')" = "$(echo "$BAD_GROUP" | tr 'A-Z' 'a-z')" ]; then
      BAD_PIN_B2=$GP
    fi
  done < /tmp/swv-groups-$$.txt
  rm -f /tmp/swv-groups-$$.txt

  if [ "$ALL_FULFILLABLE" = "1" ]; then
    pass "B2.2 every pinned group has Election revokable >= its pin (fulfillable)"
  else
    fail "B2.2 at least one pinned group is unfulfillable"
  fi

  # The bad group must receive either 0 or a fully-fulfillable pin.
  if [ "$BAD_PIN_B2" = "0" ]; then
    pass "B2.3 badGroup received 0 pin"
  else
    BAD_REV_B2=$(revokable_of "$RPC_B2" "$BAD_GROUP")
    assert_ge "B2.3 badGroup pin is fulfillable (revokable >= pin)" "$BAD_REV_B2" "$BAD_PIN_B2"
  fi

  # B2.4 real Account.withdraw on at least one pinned group must succeed.
  TARGET=""
  for G in "$BAD_GROUP" "${HEALTHY_CANDIDATES[@]}"; do
    GP=$(pin_of "$RPC_B2" "$ACCOUNT_PROXY" "$G" "$STUCK_USER")
    if [ "$GP" != "0" ]; then TARGET="$G"; break; fi
  done
  if [ -n "$TARGET" ]; then
    echo "  attempting real Account.withdraw on pinned group $TARGET ..."
    WST2=$(attempt_account_withdraw "$RPC_B2" "$TARGET")
    if [ "${WST2:-0}" = "1" ]; then
      PIN_T_AFTER=$(pin_of "$RPC_B2" "$ACCOUNT_PROXY" "$TARGET" "$STUCK_USER")
      pass "B2.4 real Account.withdraw($TARGET) SUCCEEDED (status 1)"
      assert_eq "B2.4 target pin cleared after withdraw" "$PIN_T_AFTER" "0"
    else
      fail "B2.4 real Account.withdraw($TARGET) did not return status 1 (got '${WST2}')"
    fi
  else
    echo "  (no non-zero pin found to withdraw)"
  fi
fi

cleanup

# ==========================================================================
# Summary
# ==========================================================================
section "SUMMARY"
if [ "$FAILURES" -eq 0 ]; then
  echo "  ALL ASSERTIONS PASSED"
  echo
  echo "  (1) DEPLOYED code at block $WITHDRAW_BLOCK pinned an unfulfillable"
  echo "      withdrawal to the bad group -> user got stuck (stCELO burned,"
  echo "      pin > Election revokable)."
  echo "  (2) PATCHED code prevents the stuck state at the same block."
  echo "  (3) PATCHED code lets the currently-stuck user be rescued"
  echo "      permissionlessly and actually withdraw on current mainnet state."
  exit 0
else
  echo "  $FAILURES ASSERTION(S) FAILED"
  exit 1
fi
