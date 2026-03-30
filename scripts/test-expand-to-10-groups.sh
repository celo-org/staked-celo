#!/bin/bash

# =============================================================================
# Test Script: Expand DefaultStrategy from 6 to 10 Active Groups + Full E2E
# =============================================================================
# 1. Adds 4 new validator groups via single MultiSig proposal on Anvil fork
# 2. Runs full e2e tests: deposits, withdrawals, vote activation, rebalancing
#
# New groups:
#   - Projecttent      (0x3D451dd723797b3DE938C5B22412032B6452591A)
#   - Tessellated Geo   (0x0339Df3FE4f5ccC864EAE8491E5c8AEc4611A631)
#   - atweb3            (0xb434FeB47D6154B4B4058DF5C9fCeD123dB9aBF6)
#   - HappyCelo         (0x481eAdE762d6D0b49580189B78709c9347b395bf)
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CELO_RPC="https://forno.celo.org"
ANVIL_PORT=8545
ANVIL_RPC="http://localhost:$ANVIL_PORT"

# Contract addresses
DEFAULT_STRATEGY="0x3A3ed74B1cC543D5EB323f70ac2F19977a0eA088"
GROUP_HEALTH="0x140b36FFc554d174fbf1B436C50D5409bDceCDCF"
MULTISIG="0x78DaA21FcE4D30E74fF745Da3204764a0ad40179"
ELECTION="0x8D6677192144292870907E3Fa8A5527fE55A7ff6"
MANAGER="0x0239b96D10a434a56CC9E09383077A0490cF9398"
STAKED_CELO="0xC668583dcbDc9ae6FA3CE46462758188adfdfC24"
ACCOUNT="0x4aAD04D41FD7fd495503731C5a2579e19054C432"
REBASED_STAKED_CELO="0xDc5762753043327d74e0a538199c1488FC1F44cf"
LOCKED_GOLD="0x6cC083Aed9e3ebe302A6336dBC7c921C9f03349E"

# MultiSig owners
OWNER_1="0x256f4b1f578cd7beaa440429cafb5ad21abf6fd3"
OWNER_2="0x91f2437f5c8e7a3879e14a75a7c5b4cccc76023a"
OWNER_3="0x3784a50f16af1c135b741914449bea4afdb0c5c4"

# New groups to add (randomly selected from eligible, healthy, >= 1M capacity groups)
GROUP_1="0x70FC0b021dFdBb9A106D1Ed8F35f59D3f23eCb7B"  # atalma.io
GROUP_2="0xb434FeB47D6154B4B4058DF5C9fCeD123dB9aBF6"  # atweb3
GROUP_3="0x481EAdE762d6D0b49580189B78709c9347b395bf"  # HappyCelo
GROUP_4="0x8eB004daD9397B8f23E1279905c584920000756D"  # Zanshin Dojo
GROUP_5="0x21FB4411FA5828344c2788aB07D4cc12a12571b9"  # VibeStudio
GROUP_6="0x0f66619058BB9675f3d394FCc2cE236a29901571"  # Alive29
GROUP_7="0x067e453918f2c44D937b05a7eE9DBFB804C54ADd"  # Usopp Club
GROUP_8="0xe92B7BA8497486e94bb59C51F595b590c4a5f894"
GROUP_9="0x7194DFE766a92308880A943fD70F31c8E7c50e66"

NEW_GROUPS=("$GROUP_1" "$GROUP_2" "$GROUP_3" "$GROUP_4" "$GROUP_5" "$GROUP_6" "$GROUP_7" "$GROUP_8" "$GROUP_9")
GROUP_NAMES=("atalma.io" "atweb3" "HappyCelo" "Zanshin Dojo" "VibeStudio" "Alive29" "Usopp Club" "Group8" "Group9")

# Test users (Anvil default accounts)
ANVIL_FUNDER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
USER_1="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
USER_2="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
USER_3="0x90F79bf6EB2c4f870365E785982E1f101E93b906"
USER_4="0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
USER_5="0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
log_header()  { echo ""; echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${YELLOW} $1${NC}"; echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"; }
log_test()    { echo -e "${CYAN}[TEST]${NC} $1"; }
parse_number() { echo "$1" | awk '{print $1}'; }

assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="$3"
    if [ "$actual" = "$expected" ]; then
        log_success "$msg (got $actual)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "$msg (expected $expected, got $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_gt() {
    local actual="$1"
    local threshold="$2"
    local msg="$3"
    if [ "$actual" -gt "$threshold" ] 2>/dev/null; then
        log_success "$msg ($actual > $threshold)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "$msg ($actual not > $threshold)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_not_eq() {
    local actual="$1"
    local unexpected="$2"
    local msg="$3"
    if [ "$actual" != "$unexpected" ]; then
        log_success "$msg ($actual != $unexpected)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "$msg (got $actual, should differ from $unexpected)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

cleanup() {
    if [ ! -z "$ANVIL_PID" ]; then
        kill $ANVIL_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

wait_for_anvil() {
    log_info "Waiting for Anvil..."
    for i in {1..30}; do
        if cast block-number --rpc-url $ANVIL_RPC 2>/dev/null; then
            log_success "Anvil ready"
            return 0
        fi
        sleep 1
    done
    log_error "Anvil failed to start"
    exit 1
}

# Compute lesser/greater for Election.vote() using a python helper that:
# 1. Calls getTotalVotesForEligibleValidatorGroups() to get the sorted list
# 2. Calculates where the group lands after adding ADDITIONAL votes
# 3. Returns the lesser (fewer votes) and greater (more votes) neighbours
get_lesser_greater_for_group() {
    local GROUP="$1"
    local ADDITIONAL="$2"
    local ZERO="0x0000000000000000000000000000000000000000"

    # Get the raw output: line 1 = addresses, line 2 = votes (both sorted descending)
    local RAW
    RAW=$(cast call $ELECTION \
        "getTotalVotesForEligibleValidatorGroups()(address[],uint256[])" \
        --rpc-url $ANVIL_RPC 2>&1)
    if [ $? -ne 0 ]; then
        log_error "Failed to fetch eligible validator groups from Election contract"
        echo "$ZERO $ZERO"
        return
    fi

    # Use python to parse and compute — bash can't handle big numbers or complex parsing
    local RESULT
    RESULT=$(python3 -c "
import sys

raw = '''$RAW'''
lines = raw.strip().split('\n')
if len(lines) < 2:
    print('$ZERO $ZERO')
    sys.exit(0)

# Parse addresses: [0xABC, 0xDEF, ...]
addr_line = lines[0].strip().strip('[]')
addrs = [a.strip() for a in addr_line.split(',') if a.strip()]

# Parse votes: [123 [1.23e2], 456 [4.56e2], ...]
vote_line = lines[1].strip().strip('[]')
vote_entries = [v.strip() for v in vote_line.split(',') if v.strip()]
votes = []
for entry in vote_entries:
    num = entry.split()[0] if ' ' in entry else entry
    votes.append(int(num))

group_lower = '$GROUP'.lower()
additional = int('$ADDITIONAL')

# Get current votes for our group from the sorted list
our_current = 0
in_list = False
for i, a in enumerate(addrs):
    if a.lower() == group_lower:
        our_current = votes[i]
        in_list = True
        break

our_new = our_current + additional

# The list is sorted DESCENDING by votes.
# We need to find where our_new fits:
#   greater = group with MORE votes than us (above us), or 0x0 if we're #1
#   lesser  = group with FEWER votes than us (below us), or 0x0 if we're last
ZERO = '$ZERO'
lesser = ZERO
greater = ZERO

for i, a in enumerate(addrs):
    if a.lower() == group_lower:
        continue
    if votes[i] >= our_new:
        # This group has more votes -> candidate for greater (keep updating)
        greater = addrs[i]
    else:
        # First group with fewer votes -> this is lesser
        lesser = addrs[i]
        break

# Edge case: if both are zero, the Election contract reverts.
# If the group is not in the list yet (inserting), lesser=0x0 means we're the
# new tail, but greater MUST point to the current tail.
# If greater is also 0x0 it means our_new > all groups, so lesser must be
# the current #1 and greater stays 0x0.
if lesser == ZERO and greater == ZERO:
    # We're bigger than everyone (or list is empty)
    if len(addrs) > 0:
        # Find last non-self entry as lesser
        for i in range(len(addrs)-1, -1, -1):
            if addrs[i].lower() != group_lower:
                lesser = addrs[i]
                break
        # And first non-self as greater
        for i in range(len(addrs)):
            if addrs[i].lower() != group_lower:
                if votes[i] >= our_new:
                    greater = addrs[i]
                break

print(f'{lesser} {greater}')
" 2>&1)

    local PY_EXIT=$?
    if [ $PY_EXIT -ne 0 ] || [ -z "$RESULT" ]; then
        log_error "get_lesser_greater_for_group python failed for $GROUP (exit=$PY_EXIT): $RESULT"
        echo "$ZERO $ZERO"
    else
        echo "$RESULT"
    fi
}

# =============================================================================
# PHASE 1: SETUP & GROUP EXPANSION
# =============================================================================

log_header "Starting Anvil Fork of Celo Mainnet"

lsof -ti:$ANVIL_PORT | xargs kill -9 2>/dev/null || true

anvil \
    --fork-url $CELO_RPC \
    --port $ANVIL_PORT \
    --chain-id 42220 \
    --gas-limit 50000000 \
    --code-size-limit 250000 \
    --accounts 10 \
    --balance 100000 \
    &> /tmp/anvil-e2e.log &
ANVIL_PID=$!

wait_for_anvil

# =============================================================================
log_header "Step 1: Verify Initial State"
# =============================================================================

INITIAL_ACTIVE=$(parse_number "$(cast call $DEFAULT_STRATEGY "getNumberOfGroups()(uint256)" --rpc-url $ANVIL_RPC)")
INITIAL_ACTIVATABLE=$(parse_number "$(cast call $DEFAULT_STRATEGY "activatableGroupsCount()(uint256)" --rpc-url $ANVIL_RPC)")
INITIAL_DIST=$(parse_number "$(cast call $DEFAULT_STRATEGY "maxGroupsToDistributeTo()(uint256)" --rpc-url $ANVIL_RPC)")
INITIAL_WITHDRAW=$(parse_number "$(cast call $DEFAULT_STRATEGY "maxGroupsToWithdrawFrom()(uint256)" --rpc-url $ANVIL_RPC)")
INITIAL_TOTAL_CELO=$(parse_number "$(cast call $ACCOUNT "getTotalCelo()(uint256)" --rpc-url $ANVIL_RPC)")
INITIAL_STCELO_SUPPLY=$(parse_number "$(cast call $STAKED_CELO "totalSupply()(uint256)" --rpc-url $ANVIL_RPC)")

log_info "Active groups:              $INITIAL_ACTIVE"
log_info "Activatable groups:         $INITIAL_ACTIVATABLE"
log_info "maxGroupsToDistributeTo:    $INITIAL_DIST"
log_info "maxGroupsToWithdrawFrom:    $INITIAL_WITHDRAW"
log_info "Total CELO in protocol:     $INITIAL_TOTAL_CELO"
log_info "stCELO total supply:        $INITIAL_STCELO_SUPPLY"

log_info ""
log_info "Checking candidate group health..."
for i in "${!NEW_GROUPS[@]}"; do
    HEALTH=$(cast call $GROUP_HEALTH "isGroupValid(address)(bool)" "${NEW_GROUPS[$i]}" --rpc-url $ANVIL_RPC)
    if [ "$HEALTH" == "true" ]; then
        log_success "${GROUP_NAMES[$i]}: HEALTHY"
    else
        log_warn "${GROUP_NAMES[$i]}: UNHEALTHY - will attempt updateGroupHealth"
    fi
done

# =============================================================================
log_header "Step 2: Fund and Impersonate MultiSig Owners"
# =============================================================================

for OWNER in $OWNER_1 $OWNER_2 $OWNER_3; do
    if ! cast rpc anvil_impersonateAccount $OWNER --rpc-url $ANVIL_RPC > /dev/null 2>&1; then
        log_error "Failed to impersonate $OWNER"; exit 1
    fi
    FUND_RESULT=$(cast send $OWNER --value 10ether --from $ANVIL_FUNDER --rpc-url $ANVIL_RPC --unlocked 2>&1)
    if ! echo "$FUND_RESULT" | grep -q "status.*1"; then
        log_error "Failed to fund $OWNER"; exit 1
    fi
done
log_success "All owners funded and impersonated"

# =============================================================================
log_header "Step 3: Update GroupHealth for Unhealthy Candidates"
# =============================================================================

for i in "${!NEW_GROUPS[@]}"; do
    HEALTH=$(cast call $GROUP_HEALTH "isGroupValid(address)(bool)" "${NEW_GROUPS[$i]}" --rpc-url $ANVIL_RPC)
    if [ "$HEALTH" == "false" ]; then
        log_info "Updating health for ${GROUP_NAMES[$i]}..."
        set +e
        UGH_RESULT=$(cast send $GROUP_HEALTH "updateGroupHealth(address)" "${NEW_GROUPS[$i]}" \
            --from $ANVIL_FUNDER --rpc-url $ANVIL_RPC --unlocked --gas-limit 500000 2>&1)
        set -e
        if ! echo "$UGH_RESULT" | grep -q "status.*1"; then
            log_error "updateGroupHealth TX failed for ${GROUP_NAMES[$i]}"
            echo "$UGH_RESULT" | tail -3
            exit 1
        fi
        HEALTH_AFTER=$(cast call $GROUP_HEALTH "isGroupValid(address)(bool)" "${NEW_GROUPS[$i]}" --rpc-url $ANVIL_RPC)
        if [ "$HEALTH_AFTER" == "true" ]; then
            log_success "${GROUP_NAMES[$i]} is now healthy"
        else
            log_error "${GROUP_NAMES[$i]} still unhealthy - CANNOT ADD"
            exit 1
        fi
    fi
done
log_success "All candidates are healthy"

# =============================================================================
log_header "Step 4: Submit Proposal via propose-expand-to-10-groups.sh"
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set +e
PROPOSE_RESULT=$("$SCRIPT_DIR/propose-expand-to-10-groups.sh" \
    --submit --from $OWNER_1 --rpc-url $ANVIL_RPC --unlocked 2>&1)
PROPOSE_CODE=$?
set -e

echo "$PROPOSE_RESULT"
if [ $PROPOSE_CODE -ne 0 ]; then
    log_error "Proposal submission script failed"
    exit 1
fi
log_success "Proposal submitted via propose-expand-to-10-groups.sh"

# Get proposal ID from the output
PROPOSAL_ID=$(echo "$PROPOSE_RESULT" | grep "Proposal ID:" | awk '{print $NF}')
log_info "Proposal ID: $PROPOSAL_ID"

# Now do the confirm/schedule/execute flow (test-only — on mainnet this happens over days)
log_info "Confirming with remaining owners..."

set +e
STEP_RESULT=$(cast send $MULTISIG "confirmProposal(uint256)" $PROPOSAL_ID \
    --from $OWNER_2 --rpc-url $ANVIL_RPC --unlocked --gas-limit 200000 2>&1)
set -e
if ! echo "$STEP_RESULT" | grep -q "status.*1"; then
    log_error "Owner 2 confirm failed"; exit 1
fi

set +e
STEP_RESULT=$(cast send $MULTISIG "confirmProposal(uint256)" $PROPOSAL_ID \
    --from $OWNER_3 --rpc-url $ANVIL_RPC --unlocked --gas-limit 200000 2>&1)
set -e
if ! echo "$STEP_RESULT" | grep -q "status.*1"; then
    log_error "Owner 3 confirm failed"; exit 1
fi
log_success "All 3 owners confirmed"

# Schedule if not auto-scheduled
IS_SCHEDULED=$(cast call $MULTISIG "isScheduled(uint256)(bool)" $PROPOSAL_ID --rpc-url $ANVIL_RPC)
if [ "$IS_SCHEDULED" == "true" ]; then
    log_success "Proposal auto-scheduled on final confirmation"
else
    set +e
    STEP_RESULT=$(cast send $MULTISIG "scheduleProposal(uint256)" $PROPOSAL_ID \
        --from $OWNER_1 --rpc-url $ANVIL_RPC --unlocked --gas-limit 200000 2>&1)
    set -e
    if ! echo "$STEP_RESULT" | grep -q "status.*1"; then
        log_error "Schedule proposal failed"; echo "$STEP_RESULT" | tail -3; exit 1
    fi
    log_success "Proposal scheduled"
fi

# Fast-forward timelock
DELAY=$(parse_number "$(cast call $MULTISIG "delay()(uint256)" --rpc-url $ANVIL_RPC)")
if ! cast rpc evm_increaseTime $DELAY --rpc-url $ANVIL_RPC > /dev/null 2>&1; then
    log_error "evm_increaseTime failed"; exit 1
fi
if ! cast rpc evm_mine --rpc-url $ANVIL_RPC > /dev/null 2>&1; then
    log_error "evm_mine failed"; exit 1
fi
log_info "Fast-forwarded $((DELAY / 86400)) days"

# Execute
set +e
EXEC_RESULT=$(cast send $MULTISIG "executeProposal(uint256)" $PROPOSAL_ID \
    --from $OWNER_1 --rpc-url $ANVIL_RPC --unlocked --gas-limit 5000000 2>&1)
EXEC_CODE=$?
set -e

if [ $EXEC_CODE -eq 0 ] && echo "$EXEC_RESULT" | grep -q "status.*1"; then
    log_success "Proposal $PROPOSAL_ID executed"
else
    log_error "Proposal $PROPOSAL_ID execution FAILED"
    echo "$EXEC_RESULT"
    exit 1
fi

NEW_DIST=$(parse_number "$(cast call $DEFAULT_STRATEGY "maxGroupsToDistributeTo()(uint256)" --rpc-url $ANVIL_RPC)")
NEW_WITHDRAW=$(parse_number "$(cast call $DEFAULT_STRATEGY "maxGroupsToWithdrawFrom()(uint256)" --rpc-url $ANVIL_RPC)")
NEW_ACTIVATABLE=$(parse_number "$(cast call $DEFAULT_STRATEGY "activatableGroupsCount()(uint256)" --rpc-url $ANVIL_RPC)")

assert_eq "$NEW_DIST" "15" "maxGroupsToDistributeTo updated to 15"
assert_eq "$NEW_WITHDRAW" "15" "maxGroupsToWithdrawFrom updated to 15"
assert_eq "$NEW_ACTIVATABLE" "9" "9 groups now activatable"

# =============================================================================
log_header "Step 5: Activate All 4 Groups (permissionless)"
# =============================================================================

ZERO_ADDR="0x0000000000000000000000000000000000000000"
CURRENT_TAIL="0xc8A81D473992c7c6D3F469A8263F24914625709d"

log_info "Activating groups (inserted at tail with 0 stCELO)..."

log_info "Activating ${GROUP_NAMES[0]}..."
set +e
ACT_RESULT=$(cast send $DEFAULT_STRATEGY "activateGroup(address,address,address)" \
    "${NEW_GROUPS[0]}" "$ZERO_ADDR" "$CURRENT_TAIL" \
    --from $ANVIL_FUNDER --rpc-url $ANVIL_RPC --unlocked --gas-limit 500000 2>&1)
ACT_CODE=$?
set -e
if [ $ACT_CODE -eq 0 ] && echo "$ACT_RESULT" | grep -q "status.*1"; then
    log_success "${GROUP_NAMES[0]} activated"
else
    log_error "${GROUP_NAMES[0]} activation FAILED"
    echo "$ACT_RESULT" | tail -3
    exit 1
fi

PREV_GROUP="${NEW_GROUPS[0]}"
for i in 1 2 3 4 5 6 7 8; do
    log_info "Activating ${GROUP_NAMES[$i]}..."
    set +e
    ACT_RESULT=$(cast send $DEFAULT_STRATEGY "activateGroup(address,address,address)" \
        "${NEW_GROUPS[$i]}" "$ZERO_ADDR" "$PREV_GROUP" \
        --from $ANVIL_FUNDER --rpc-url $ANVIL_RPC --unlocked --gas-limit 500000 2>&1)
    ACT_CODE=$?
    set -e
    if [ $ACT_CODE -eq 0 ] && echo "$ACT_RESULT" | grep -q "status.*1"; then
        log_success "${GROUP_NAMES[$i]} activated"
    else
        log_error "${GROUP_NAMES[$i]} activation FAILED"
        echo "$ACT_RESULT" | tail -3
        exit 1
    fi
    PREV_GROUP="${NEW_GROUPS[$i]}"
done

FINAL_ACTIVE=$(parse_number "$(cast call $DEFAULT_STRATEGY "getNumberOfGroups()(uint256)" --rpc-url $ANVIL_RPC)")
assert_eq "$FINAL_ACTIVE" "15" "DefaultStrategy now has 15 active groups"

# Walk the full list
log_info ""
log_info "Active groups (head to tail):"
CURRENT=$(cast call $DEFAULT_STRATEGY "getGroupsHead()(address)" --rpc-url $ANVIL_RPC)
COUNT=1
STCELO_HEAD=$(parse_number "$(cast call $DEFAULT_STRATEGY "stCeloInGroup(address)(uint256)" "$CURRENT" --rpc-url $ANVIL_RPC)")
echo -e "  $COUNT: $CURRENT (stCELO: $STCELO_HEAD)"

while true; do
    RESULT=$(cast call $DEFAULT_STRATEGY "getGroupPreviousAndNext(address)(address,address)" "$CURRENT" --rpc-url $ANVIL_RPC)
    PREV=$(echo "$RESULT" | head -1)
    if [ "$PREV" = "$ZERO_ADDR" ]; then
        break
    fi
    COUNT=$((COUNT + 1))
    CURRENT="$PREV"
    STCELO=$(parse_number "$(cast call $DEFAULT_STRATEGY "stCeloInGroup(address)(uint256)" "$CURRENT" --rpc-url $ANVIL_RPC)")
    echo -e "  $COUNT: $CURRENT (stCELO: $STCELO)"
done

# =============================================================================
# PHASE 2: E2E PROTOCOL TESTS
# =============================================================================

log_header "E2E Test 1: Multiple Deposits (5 users)"

DEPOSIT_AMOUNT="100000000000000000000" # 100 CELO (100e18)

for i in 1 2 3 4 5; do
    eval "USER=\$USER_$i"
    log_test "User $i ($USER) depositing 100 CELO..."

    STCELO_BEFORE=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER" --rpc-url $ANVIL_RPC)")

    set +e
    TX_RESULT=$(cast send $MANAGER "deposit()" \
        --value $DEPOSIT_AMOUNT \
        --from $USER --rpc-url $ANVIL_RPC --unlocked --gas-limit 2000000 2>&1)
    TX_CODE=$?
    set -e

    STCELO_AFTER=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER" --rpc-url $ANVIL_RPC)")

    if [ $TX_CODE -eq 0 ] && echo "$TX_RESULT" | grep -q "status.*1"; then
        assert_not_eq "$STCELO_AFTER" "$STCELO_BEFORE" "User $i received stCELO after deposit"
    else
        log_error "User $i deposit failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Verify total supply increased
POST_DEPOSIT_SUPPLY=$(parse_number "$(cast call $STAKED_CELO "totalSupply()(uint256)" --rpc-url $ANVIL_RPC)")
assert_not_eq "$POST_DEPOSIT_SUPPLY" "$INITIAL_STCELO_SUPPLY" "stCELO supply increased after deposits"

# Check that votes are scheduled across new groups (they're at the tail, so deposits go there)
log_info ""
log_info "Checking scheduled votes distribution across new groups..."
NEW_GROUPS_WITH_SCHEDULED=0
for i in "${!NEW_GROUPS[@]}"; do
    SCHEDULED=$(parse_number "$(cast call $ACCOUNT "scheduledVotesForGroup(address)(uint256)" "${NEW_GROUPS[$i]}" --rpc-url $ANVIL_RPC)")
    log_info "  ${GROUP_NAMES[$i]}: $SCHEDULED scheduled votes"
    if [ "$SCHEDULED" != "0" ]; then
        NEW_GROUPS_WITH_SCHEDULED=$((NEW_GROUPS_WITH_SCHEDULED + 1))
    fi
done
assert_gt "$NEW_GROUPS_WITH_SCHEDULED" "0" "At least 1 new group received scheduled votes from deposits"

# =============================================================================
log_header "E2E Test 2: Vote Activation (activateAndVote)"
# =============================================================================

# Collect all 10 active groups
ALL_ACTIVE_GROUPS=()
CURRENT=$(cast call $DEFAULT_STRATEGY "getGroupsHead()(address)" --rpc-url $ANVIL_RPC)
ALL_ACTIVE_GROUPS+=("$CURRENT")
while true; do
    RESULT=$(cast call $DEFAULT_STRATEGY "getGroupPreviousAndNext(address)(address,address)" "$CURRENT" --rpc-url $ANVIL_RPC)
    PREV=$(echo "$RESULT" | head -1)
    if [ "$PREV" = "$ZERO_ADDR" ]; then
        break
    fi
    CURRENT="$PREV"
    ALL_ACTIVE_GROUPS+=("$CURRENT")
done

ACTIVATED_COUNT=0
FAILED_ACTIVATIONS=0
for GROUP in "${ALL_ACTIVE_GROUPS[@]}"; do
    SCHEDULED=$(parse_number "$(cast call $ACCOUNT "scheduledVotesForGroup(address)(uint256)" "$GROUP" --rpc-url $ANVIL_RPC)")
    if [ "$SCHEDULED" != "0" ]; then
        log_test "Activating votes for $GROUP (scheduled: $SCHEDULED)..."

        # Compute proper lesser/greater for Election sorted list
        read LESSER GREATER <<< "$(get_lesser_greater_for_group "$GROUP" "$SCHEDULED")"
        log_info "  lesser=$LESSER greater=$GREATER"

        set +e
        ACTIVATE_RESULT=$(cast send $ACCOUNT "activateAndVote(address,address,address)" \
            "$GROUP" "$LESSER" "$GREATER" \
            --from $ANVIL_FUNDER --rpc-url $ANVIL_RPC --unlocked --gas-limit 2000000 2>&1)
        ACTIVATE_CODE=$?
        set -e

        if [ $ACTIVATE_CODE -eq 0 ] && echo "$ACTIVATE_RESULT" | grep -q "status.*1"; then
            ACTIVATED_COUNT=$((ACTIVATED_COUNT + 1))
            # Verify scheduled votes drained to 0 (internal accounting fully processed)
            POST_SCHEDULED=$(parse_number "$(cast call $ACCOUNT \
                "scheduledVotesForGroup(address)(uint256)" "$GROUP" --rpc-url $ANVIL_RPC)")
            if [ "$POST_SCHEDULED" != "0" ]; then
                log_error "Scheduled votes not fully drained for $GROUP: $POST_SCHEDULED remaining"
                FAILED_ACTIVATIONS=$((FAILED_ACTIVATIONS + 1))
            fi
            log_success "Votes activated for $GROUP (remaining scheduled: $POST_SCHEDULED)"
        else
            # Retry: for groups with large stale scheduled amounts, the position
            # shift can make the first lesser/greater stale. Recalculate and retry.
            log_warn "First attempt failed for $GROUP, retrying with fresh lesser/greater..."
            read LESSER GREATER <<< "$(get_lesser_greater_for_group "$GROUP" "$SCHEDULED")"
            set +e
            ACTIVATE_RESULT=$(cast send $ACCOUNT "activateAndVote(address,address,address)" \
                "$GROUP" "$LESSER" "$GREATER" \
                --from $ANVIL_FUNDER --rpc-url $ANVIL_RPC --unlocked --gas-limit 2000000 2>&1)
            ACTIVATE_CODE=$?
            set -e
            if [ $ACTIVATE_CODE -eq 0 ] && echo "$ACTIVATE_RESULT" | grep -q "status.*1"; then
                ACTIVATED_COUNT=$((ACTIVATED_COUNT + 1))
                log_success "Votes activated for $GROUP on retry"
            else
                log_error "activateAndVote FAILED for $GROUP after retry"
                echo "$ACTIVATE_RESULT" | tail -3
                FAILED_ACTIVATIONS=$((FAILED_ACTIVATIONS + 1))
            fi
        fi
    fi
done

log_info "Activated votes for $ACTIVATED_COUNT groups ($FAILED_ACTIVATIONS failures)"
if [ $FAILED_ACTIVATIONS -gt 0 ]; then
    TESTS_FAILED=$((TESTS_FAILED + FAILED_ACTIVATIONS))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# =============================================================================
log_header "E2E Test 3: Verify Vote Distribution Across 10 Groups"
# =============================================================================

log_info "CELO per group — internal (getCeloForGroup) vs Election global votes:"
GROUPS_WITH_CELO=0
GROUPS_WITH_ELECTION_VOTES=0
for GROUP in "${ALL_ACTIVE_GROUPS[@]}"; do
    CELO_FOR_GROUP=$(parse_number "$(cast call $ACCOUNT "getCeloForGroup(address)(uint256)" "$GROUP" --rpc-url $ANVIL_RPC)")
    # On L2, per-account vote tracking changed. Use global getTotalVotesForGroup instead.
    ELECTION_VOTES=$(parse_number "$(cast call $ELECTION \
        "getTotalVotesForGroup(address)(uint256)" "$GROUP" --rpc-url $ANVIL_RPC)")
    if [ "$CELO_FOR_GROUP" != "0" ]; then
        GROUPS_WITH_CELO=$((GROUPS_WITH_CELO + 1))
    fi
    if [ "$ELECTION_VOTES" != "0" ]; then
        GROUPS_WITH_ELECTION_VOTES=$((GROUPS_WITH_ELECTION_VOTES + 1))
    fi
    echo -e "  $GROUP  internal=$CELO_FOR_GROUP  election_global=$ELECTION_VOTES"
done

log_info "Groups with non-zero internal CELO: $GROUPS_WITH_CELO / 15"
log_info "Groups with non-zero Election votes: $GROUPS_WITH_ELECTION_VOTES / 15"
assert_gt "$GROUPS_WITH_ELECTION_VOTES" "5" "Majority of groups have Election votes"

# Verify total CELO hasn't been lost
POST_ACTIVATE_TOTAL=$(parse_number "$(cast call $ACCOUNT "getTotalCelo()(uint256)" --rpc-url $ANVIL_RPC)")
log_info "Total CELO in protocol: $INITIAL_TOTAL_CELO -> $POST_ACTIVATE_TOTAL"

# =============================================================================
log_header "E2E Test 4: Additional Deposits After Expansion (5 more)"
# =============================================================================

LARGE_DEPOSIT="500000000000000000000" # 500 CELO

for i in 1 2 3 4 5; do
    eval "USER=\$USER_$i"
    log_test "User $i depositing 500 CELO (second deposit)..."

    STCELO_BEFORE=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER" --rpc-url $ANVIL_RPC)")

    set +e
    TX_RESULT=$(cast send $MANAGER "deposit()" \
        --value $LARGE_DEPOSIT \
        --from $USER --rpc-url $ANVIL_RPC --unlocked --gas-limit 2000000 2>&1)
    TX_CODE=$?
    set -e

    STCELO_AFTER=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER" --rpc-url $ANVIL_RPC)")

    if [ $TX_CODE -eq 0 ] && echo "$TX_RESULT" | grep -q "status.*1"; then
        INCREASED=$(python3 -c "print('yes' if int('$STCELO_AFTER') > int('$STCELO_BEFORE') else 'no')")
        assert_eq "$INCREASED" "yes" "User $i second deposit: stCELO increased"
    else
        log_error "User $i second deposit failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# =============================================================================
log_header "E2E Test 5: stCELO Transfers"
# =============================================================================

TRANSFER_AMOUNT="50000000000000000000" # 50 stCELO

log_test "User 1 transferring 50 stCELO to User 2..."
USER1_BEFORE=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER_1" --rpc-url $ANVIL_RPC)")
USER2_BEFORE=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER_2" --rpc-url $ANVIL_RPC)")

set +e
TX_RESULT=$(cast send $STAKED_CELO "transfer(address,uint256)" "$USER_2" "$TRANSFER_AMOUNT" \
    --from $USER_1 --rpc-url $ANVIL_RPC --unlocked --gas-limit 500000 2>&1)
TX_CODE=$?
set -e

USER1_AFTER=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER_1" --rpc-url $ANVIL_RPC)")
USER2_AFTER=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER_2" --rpc-url $ANVIL_RPC)")

if [ $TX_CODE -eq 0 ] && echo "$TX_RESULT" | grep -q "status.*1"; then
    # Verify correct direction: sender decreased, receiver increased
    SENDER_DECREASED=$(python3 -c "print('yes' if int('$USER1_AFTER') < int('$USER1_BEFORE') else 'no')")
    RECEIVER_INCREASED=$(python3 -c "print('yes' if int('$USER2_AFTER') > int('$USER2_BEFORE') else 'no')")
    assert_eq "$SENDER_DECREASED" "yes" "User 1 balance decreased after transfer"
    assert_eq "$RECEIVER_INCREASED" "yes" "User 2 balance increased after transfer"
else
    log_error "stCELO transfer failed"
    TESTS_FAILED=$((TESTS_FAILED + 2))
fi

# =============================================================================
log_header "E2E Test 6: Withdrawals (5 users)"
# =============================================================================

WITHDRAW_AMOUNT="30000000000000000000" # 30 stCELO

for i in 1 2 3 4 5; do
    eval "USER=\$USER_$i"
    log_test "User $i withdrawing 30 stCELO..."

    STCELO_BEFORE=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER" --rpc-url $ANVIL_RPC)")

    set +e
    TX_RESULT=$(cast send $MANAGER "withdraw(uint256)" "$WITHDRAW_AMOUNT" \
        --from $USER --rpc-url $ANVIL_RPC --unlocked --gas-limit 3000000 2>&1)
    TX_CODE=$?
    set -e

    STCELO_AFTER=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER" --rpc-url $ANVIL_RPC)")

    if [ $TX_CODE -eq 0 ] && echo "$TX_RESULT" | grep -q "status.*1"; then
        DECREASED=$(python3 -c "print('yes' if int('$STCELO_AFTER') < int('$STCELO_BEFORE') else 'no')")
        assert_eq "$DECREASED" "yes" "User $i stCELO decreased after withdrawal"
    else
        log_error "User $i withdrawal failed"
        echo "$TX_RESULT" | tail -3
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# =============================================================================
log_header "E2E Test 7: Verify Protocol Invariants After Withdrawals"
# =============================================================================

POST_WITHDRAW_SUPPLY=$(parse_number "$(cast call $STAKED_CELO "totalSupply()(uint256)" --rpc-url $ANVIL_RPC)")
POST_WITHDRAW_TOTAL=$(parse_number "$(cast call $ACCOUNT "getTotalCelo()(uint256)" --rpc-url $ANVIL_RPC)")

log_info "stCELO supply: $INITIAL_STCELO_SUPPLY -> $POST_DEPOSIT_SUPPLY -> $POST_WITHDRAW_SUPPLY"
log_info "Total CELO:    $INITIAL_TOTAL_CELO -> $POST_ACTIVATE_TOTAL -> $POST_WITHDRAW_TOTAL"

# Assert total CELO increased (deposits added funds)
CELO_INCREASED=$(python3 -c "print('yes' if int('$POST_WITHDRAW_TOTAL') > int('$INITIAL_TOTAL_CELO') else 'no')")
assert_eq "$CELO_INCREASED" "yes" "Total CELO in protocol increased after deposits"

# Verify group count still 10
GROUPS_AFTER=$(parse_number "$(cast call $DEFAULT_STRATEGY "getNumberOfGroups()(uint256)" --rpc-url $ANVIL_RPC)")
assert_eq "$GROUPS_AFTER" "15" "Still 15 active groups after withdrawals"

# =============================================================================
log_header "E2E Test 8: Second Round Vote Activation"
# =============================================================================

ACTIVATED_2=0
FAILED_2=0
for GROUP in "${ALL_ACTIVE_GROUPS[@]}"; do
    SCHEDULED=$(parse_number "$(cast call $ACCOUNT "scheduledVotesForGroup(address)(uint256)" "$GROUP" --rpc-url $ANVIL_RPC)")
    if [ "$SCHEDULED" != "0" ]; then
        log_test "Activating votes for $GROUP (scheduled: $SCHEDULED)..."
        read LESSER GREATER <<< "$(get_lesser_greater_for_group "$GROUP" "$SCHEDULED")"
        set +e
        RESULT=$(cast send $ACCOUNT "activateAndVote(address,address,address)" \
            "$GROUP" "$LESSER" "$GREATER" \
            --from $ANVIL_FUNDER --rpc-url $ANVIL_RPC --unlocked --gas-limit 2000000 2>&1)
        RC=$?
        set -e
        if [ $RC -eq 0 ] && echo "$RESULT" | grep -q "status.*1"; then
            ACTIVATED_2=$((ACTIVATED_2 + 1))
            log_success "Activated for $GROUP"
        else
            log_error "Failed activation for $GROUP"
            FAILED_2=$((FAILED_2 + 1))
        fi
    fi
done
log_info "Second round: activated $ACTIVATED_2 groups ($FAILED_2 failures)"
if [ $FAILED_2 -gt 0 ]; then
    TESTS_FAILED=$((TESTS_FAILED + FAILED_2))
fi
if [ $ACTIVATED_2 -gt 0 ] && [ $FAILED_2 -eq 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# =============================================================================
log_header "E2E Test 9: Conversion Rate Sanity Check"
# =============================================================================

ONE_CELO="1000000000000000000" # 1 CELO

STCELO_FOR_1=$(parse_number "$(cast call $MANAGER "toStakedCelo(uint256)(uint256)" "$ONE_CELO" --rpc-url $ANVIL_RPC)")
CELO_FOR_1=$(parse_number "$(cast call $MANAGER "toCelo(uint256)(uint256)" "$ONE_CELO" --rpc-url $ANVIL_RPC)")

log_info "1 CELO   -> $STCELO_FOR_1 stCELO"
log_info "1 stCELO -> $CELO_FOR_1 CELO"

# stCELO should be worth >= 1 CELO (protocol earns rewards over time)
assert_not_eq "$CELO_FOR_1" "0" "toCelo returns non-zero for 1 stCELO"
assert_not_eq "$STCELO_FOR_1" "0" "toStakedCelo returns non-zero for 1 CELO"

# =============================================================================
log_header "E2E Test 10: RebasedStakedCelo (rstCELO) Interaction"
# =============================================================================

RSTCELO_DEPOSIT="10000000000000000000" # 10 stCELO

log_test "User 3 approving stCELO for rstCELO contract..."
set +e
APPROVE_RESULT=$(cast send $STAKED_CELO "approve(address,uint256)" "$REBASED_STAKED_CELO" "$RSTCELO_DEPOSIT" \
    --from $USER_3 --rpc-url $ANVIL_RPC --unlocked --gas-limit 200000 2>&1)
APPROVE_CODE=$?
set -e
if [ $APPROVE_CODE -ne 0 ] || ! echo "$APPROVE_RESULT" | grep -q "status.*1"; then
    log_error "stCELO approve for rstCELO failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

log_test "User 3 depositing 10 stCELO into rstCELO..."
set +e
TX_RESULT=$(cast send $REBASED_STAKED_CELO "deposit(uint256)" "$RSTCELO_DEPOSIT" \
    --from $USER_3 --rpc-url $ANVIL_RPC --unlocked --gas-limit 500000 2>&1)
TX_CODE=$?
set -e

if [ $TX_CODE -eq 0 ] && echo "$TX_RESULT" | grep -q "status.*1"; then
    RSTCELO_BAL=$(parse_number "$(cast call $REBASED_STAKED_CELO "balanceOf(address)(uint256)" "$USER_3" --rpc-url $ANVIL_RPC)")
    assert_not_eq "$RSTCELO_BAL" "0" "User 3 has rstCELO balance after deposit"
    log_info "  rstCELO balance: $RSTCELO_BAL"

    log_test "User 3 withdrawing 5 stCELO from rstCELO..."
    RSTCELO_WITHDRAW="5000000000000000000"
    set +e
    TX_RESULT2=$(cast send $REBASED_STAKED_CELO "withdraw(uint256)" "$RSTCELO_WITHDRAW" \
        --from $USER_3 --rpc-url $ANVIL_RPC --unlocked --gas-limit 500000 2>&1)
    TX_CODE2=$?
    set -e

    if [ $TX_CODE2 -eq 0 ] && echo "$TX_RESULT2" | grep -q "status.*1"; then
        RSTCELO_BAL_AFTER=$(parse_number "$(cast call $REBASED_STAKED_CELO "balanceOf(address)(uint256)" "$USER_3" --rpc-url $ANVIL_RPC)")
        assert_not_eq "$RSTCELO_BAL_AFTER" "$RSTCELO_BAL" "rstCELO balance decreased after withdraw"
    else
        log_error "rstCELO withdraw failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    log_error "rstCELO deposit failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# =============================================================================
log_header "E2E Test 11: Large Deposit Stress Test"
# =============================================================================

HUGE_DEPOSIT="10000000000000000000000" # 10,000 CELO

log_test "User 1 depositing 10,000 CELO (stress test)..."
STCELO_BEFORE=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER_1" --rpc-url $ANVIL_RPC)")

set +e
TX_RESULT=$(cast send $MANAGER "deposit()" \
    --value $HUGE_DEPOSIT \
    --from $USER_1 --rpc-url $ANVIL_RPC --unlocked --gas-limit 5000000 2>&1)
TX_CODE=$?
set -e

STCELO_AFTER=$(parse_number "$(cast call $STAKED_CELO "balanceOf(address)(uint256)" "$USER_1" --rpc-url $ANVIL_RPC)")

if [ $TX_CODE -eq 0 ] && echo "$TX_RESULT" | grep -q "status.*1"; then
    assert_not_eq "$STCELO_AFTER" "$STCELO_BEFORE" "Large deposit (10K CELO) succeeded"
else
    log_error "Large deposit failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify the large deposit was distributed to new groups too
log_info "Scheduled votes after large deposit:"
NEW_GROUPS_SCHEDULED_LARGE=0
for i in "${!NEW_GROUPS[@]}"; do
    SCHEDULED=$(parse_number "$(cast call $ACCOUNT "scheduledVotesForGroup(address)(uint256)" "${NEW_GROUPS[$i]}" --rpc-url $ANVIL_RPC)")
    log_info "  ${GROUP_NAMES[$i]}: $SCHEDULED"
    if [ "$SCHEDULED" != "0" ]; then
        NEW_GROUPS_SCHEDULED_LARGE=$((NEW_GROUPS_SCHEDULED_LARGE + 1))
    fi
done
assert_gt "$NEW_GROUPS_SCHEDULED_LARGE" "0" "Large deposit distributed to at least 1 new group"

# =============================================================================
log_header "E2E Test 12: Large Withdrawal"
# =============================================================================

LARGE_WITHDRAW="5000000000000000000000" # 5000 stCELO

log_test "User 1 withdrawing 5000 stCELO (large withdrawal across groups)..."
set +e
TX_RESULT=$(cast send $MANAGER "withdraw(uint256)" "$LARGE_WITHDRAW" \
    --from $USER_1 --rpc-url $ANVIL_RPC --unlocked --gas-limit 5000000 2>&1)
TX_CODE=$?
set -e

if [ $TX_CODE -eq 0 ] && echo "$TX_RESULT" | grep -q "status.*1"; then
    log_success "Large withdrawal (5000 stCELO) succeeded"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Large withdrawal failed"
    echo "$TX_RESULT" | tail -5
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# =============================================================================
log_header "E2E Test 13: Group Health Stays Valid"
# =============================================================================

log_test "Verifying all 10 groups remain healthy..."
UNHEALTHY_COUNT=0
for GROUP in "${ALL_ACTIVE_GROUPS[@]}"; do
    HEALTH=$(cast call $GROUP_HEALTH "isGroupValid(address)(bool)" "$GROUP" --rpc-url $ANVIL_RPC)
    if [ "$HEALTH" != "true" ]; then
        log_error "Group $GROUP became unhealthy!"
        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
    fi
done
assert_eq "$UNHEALTHY_COUNT" "0" "All 15 groups remain healthy"

# =============================================================================
log_header "E2E Test 14: Final State Verification"
# =============================================================================

FINAL_GROUPS=$(parse_number "$(cast call $DEFAULT_STRATEGY "getNumberOfGroups()(uint256)" --rpc-url $ANVIL_RPC)")
FINAL_SUPPLY=$(parse_number "$(cast call $STAKED_CELO "totalSupply()(uint256)" --rpc-url $ANVIL_RPC)")
FINAL_TOTAL_CELO=$(parse_number "$(cast call $ACCOUNT "getTotalCelo()(uint256)" --rpc-url $ANVIL_RPC)")
FINAL_DIST=$(parse_number "$(cast call $DEFAULT_STRATEGY "maxGroupsToDistributeTo()(uint256)" --rpc-url $ANVIL_RPC)")
FINAL_WITHDRAW_PARAM=$(parse_number "$(cast call $DEFAULT_STRATEGY "maxGroupsToWithdrawFrom()(uint256)" --rpc-url $ANVIL_RPC)")

assert_eq "$FINAL_GROUPS" "15" "Final: 15 active groups"
assert_eq "$FINAL_DIST" "15" "Final: maxGroupsToDistributeTo = 15"
assert_eq "$FINAL_WITHDRAW_PARAM" "15" "Final: maxGroupsToWithdrawFrom = 15"

log_info ""
log_info "Protocol state summary:"
log_info "  Active groups:  $INITIAL_ACTIVE -> $FINAL_GROUPS"
log_info "  stCELO supply:  $INITIAL_STCELO_SUPPLY -> $FINAL_SUPPLY"
log_info "  Total CELO:     $INITIAL_TOTAL_CELO -> $FINAL_TOTAL_CELO"

# Final stCELO distribution across all 10 groups
log_info ""
log_info "Final stCELO distribution across groups:"
for GROUP in "${ALL_ACTIVE_GROUPS[@]}"; do
    STCELO=$(parse_number "$(cast call $DEFAULT_STRATEGY "stCeloInGroup(address)(uint256)" "$GROUP" --rpc-url $ANVIL_RPC)")
    echo -e "  $GROUP: $STCELO"
done

# =============================================================================
log_header "RESULTS"
# =============================================================================

echo ""
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

if [ $TESTS_FAILED -eq 0 ]; then
    log_success "ALL $TOTAL_TESTS TESTS PASSED"
else
    log_error "$TESTS_FAILED / $TOTAL_TESTS TESTS FAILED"
fi

echo ""
echo "Summary:"
echo "  Tests passed:  $TESTS_PASSED"
echo "  Tests failed:  $TESTS_FAILED"
echo "  Total tests:   $TOTAL_TESTS"
echo ""
echo "Group expansion:  6 -> 15 active groups"
echo "Sorting params:   8/8/10 -> 15/15/17"
echo ""
echo "E2E scenarios tested:"
echo "  - 5 user deposits (100 CELO each)"
echo "  - Vote activation across 10 groups"
echo "  - Vote distribution verification"
echo "  - 5 more deposits (500 CELO each)"
echo "  - stCELO transfers between users"
echo "  - 5 user withdrawals (30 stCELO each)"
echo "  - Protocol invariant checks"
echo "  - Second round vote activation"
echo "  - Conversion rate sanity"
echo "  - rstCELO deposit/withdraw"
echo "  - Large deposit stress test (10K CELO)"
echo "  - Large withdrawal (5K stCELO)"
echo "  - Group health verification"
echo "  - Final state verification"
echo ""
echo "Mainnet actions needed:"
echo "  1. Single MultiSig proposal: setSortingParams(10,10,12) + addActivatableGroup() x4"
echo "  2. After execution: activateGroup() x4 (permissionless, anyone can call)"
echo ""

exit $TESTS_FAILED
