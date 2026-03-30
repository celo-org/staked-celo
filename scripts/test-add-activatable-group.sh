#!/bin/bash

# =============================================================================
# Test Script: Add Activatable Group via MultiSig Proposal
# =============================================================================
# This script tests the multisig proposal to add a validator group to 
# active groups on an Anvil fork of Celo mainnet.
#
# Group to add: 0xE09632da4dEAFb3DA2Cd6939F31c98607fCCdBC5
# Target contract: DefaultStrategy (0x3A3ed74B1cC543D5EB323f70ac2F19977a0eA088)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CELO_RPC="https://forno.celo.org"
ANVIL_PORT=8545
ANVIL_RPC="http://localhost:$ANVIL_PORT"

# Contract addresses on Celo mainnet
DEFAULT_STRATEGY="0x3A3ed74B1cC543D5EB323f70ac2F19977a0eA088"
MULTISIG="0x78DaA21FcE4D30E74fF745Da3204764a0ad40179"

# Group to add
NEW_GROUP="0xE09632da4dEAFb3DA2Cd6939F31c98607fCCdBC5"

# Multisig owners (from mainnet deployment)
OWNER_1="0x256f4b1f578cd7beaa440429cafb5ad21abf6fd3"
OWNER_2="0x91f2437f5c8e7a3879e14a75a7c5b4cccc76023a"
OWNER_3="0x3784a50f16af1c135b741914449bea4afdb0c5c4"

# Encoded payload for addActivatableGroup(0xE09632da4dEAFb3DA2Cd6939F31c98607fCCdBC5)
PAYLOAD="0xb95de2d6000000000000000000000000e09632da4deafb3da2cd6939f31c98607fccdbc5"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo ""
    echo -e "${YELLOW}=============================================================================${NC}"
    echo -e "${YELLOW} $1${NC}"
    echo -e "${YELLOW}=============================================================================${NC}"
}

cleanup() {
    log_info "Cleaning up..."
    if [ ! -z "$ANVIL_PID" ]; then
        kill $ANVIL_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

wait_for_anvil() {
    log_info "Waiting for Anvil to be ready..."
    for i in {1..30}; do
        if cast block-number --rpc-url $ANVIL_RPC 2>/dev/null; then
            log_success "Anvil is ready!"
            return 0
        fi
        sleep 1
    done
    log_error "Anvil failed to start"
    exit 1
}

# Extract just the number from cast output (removes [scientific notation] suffix)
parse_number() {
    echo "$1" | awk '{print $1}'
}

# =============================================================================
# Main Script
# =============================================================================

log_header "Starting Anvil Fork of Celo Mainnet"

# Check if anvil is installed
if ! command -v anvil &> /dev/null; then
    log_error "Anvil is not installed. Please install Foundry: https://getfoundry.sh"
    exit 1
fi

# Check if cast is installed
if ! command -v cast &> /dev/null; then
    log_error "Cast is not installed. Please install Foundry: https://getfoundry.sh"
    exit 1
fi

# Kill any existing anvil process on the port
lsof -ti:$ANVIL_PORT | xargs kill -9 2>/dev/null || true

# Start Anvil with Celo mainnet fork
log_info "Starting Anvil fork of Celo mainnet at $CELO_RPC..."
anvil \
    --fork-url $CELO_RPC \
    --port $ANVIL_PORT \
    --chain-id 42220 \
    --gas-limit 50000000 \
    --code-size-limit 250000 \
    --accounts 10 \
    --balance 10000 \
    &> /tmp/anvil.log &
ANVIL_PID=$!

wait_for_anvil

log_info "Anvil PID: $ANVIL_PID"

# =============================================================================
log_header "Step 1: Verify Current State"
# =============================================================================

log_info "Checking current activatable groups count..."
CURRENT_COUNT_RAW=$(cast call $DEFAULT_STRATEGY "activatableGroupsCount()(uint256)" --rpc-url $ANVIL_RPC)
CURRENT_COUNT=$(parse_number "$CURRENT_COUNT_RAW")
log_info "Current activatable groups count: $CURRENT_COUNT"

log_info "Checking MultiSig owners..."
cast call $MULTISIG "getOwners()(address[])" --rpc-url $ANVIL_RPC

log_info "Checking required confirmations..."
REQUIRED_RAW=$(cast call $MULTISIG "required()(uint256)" --rpc-url $ANVIL_RPC)
REQUIRED=$(parse_number "$REQUIRED_RAW")
log_info "Required confirmations: $REQUIRED"

log_info "Checking current proposal count..."
PROPOSAL_COUNT_RAW=$(cast call $MULTISIG "proposalCount()(uint256)" --rpc-url $ANVIL_RPC)
PROPOSAL_COUNT=$(parse_number "$PROPOSAL_COUNT_RAW")
log_info "Current proposal count: $PROPOSAL_COUNT"

# The new proposal ID will be the current proposal count (0-indexed counting)
# After submission, proposalCount will be current + 1, and the new proposal ID is current
EXPECTED_PROPOSAL_ID=$PROPOSAL_COUNT
log_info "Expected new proposal ID: $EXPECTED_PROPOSAL_ID"

# =============================================================================
log_header "Step 2: Fund and Impersonate MultiSig Owners"
# =============================================================================

# Anvil's default funded account (first account)
ANVIL_FUNDER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

log_info "Funding and impersonating multisig owners..."

# Impersonate and fund each owner
for OWNER in $OWNER_1 $OWNER_2 $OWNER_3; do
    log_info "Impersonating $OWNER..."
    cast rpc anvil_impersonateAccount $OWNER --rpc-url $ANVIL_RPC > /dev/null
    
    log_info "Funding $OWNER..."
    cast send $OWNER --value 10ether --from $ANVIL_FUNDER --rpc-url $ANVIL_RPC --unlocked > /dev/null
done

log_success "All owners funded and impersonated"

# =============================================================================
log_header "Step 3: Submit Proposal (Owner 1)"
# =============================================================================

log_info "Owner 1 ($OWNER_1) submitting proposal..."
log_info "Target: $DEFAULT_STRATEGY"
log_info "Payload: $PAYLOAD"

# Submit the proposal using raw calldata
SUBMIT_CALLDATA=$(cast calldata "submitProposal(address[],uint256[],bytes[])" "[$DEFAULT_STRATEGY]" "[0]" "[$PAYLOAD]")
log_info "Submit calldata: ${SUBMIT_CALLDATA:0:100}..."

TX_RESULT=$(cast send $MULTISIG $SUBMIT_CALLDATA \
    --from $OWNER_1 \
    --rpc-url $ANVIL_RPC \
    --unlocked \
    --gas-limit 500000 \
    2>&1)

echo "$TX_RESULT"

# Check if transaction was successful
if echo "$TX_RESULT" | grep -q "status.*1"; then
    log_success "Transaction successful"
else
    log_error "Transaction may have failed"
fi

# The proposal ID is the count BEFORE submission (0-indexed)
PROPOSAL_ID=$EXPECTED_PROPOSAL_ID
log_success "Proposal ID: $PROPOSAL_ID"

# Verify new proposal count
NEW_PROPOSAL_COUNT_RAW=$(cast call $MULTISIG "proposalCount()(uint256)" --rpc-url $ANVIL_RPC)
NEW_PROPOSAL_COUNT=$(parse_number "$NEW_PROPOSAL_COUNT_RAW")
log_info "New proposal count: $NEW_PROPOSAL_COUNT"

# Verify proposal was created
log_info "Verifying proposal was created..."
PROPOSAL_EXISTS=$(cast call $MULTISIG "getProposal(uint256)(address[],uint256[],bytes[])" $PROPOSAL_ID --rpc-url $ANVIL_RPC 2>&1 || echo "error")
echo "Proposal details: $PROPOSAL_EXISTS"

# =============================================================================
log_header "Step 4: Confirm Proposal (Owners 1, 2, 3)"
# =============================================================================

# Check current confirmations
log_info "Checking current confirmations..."
CONFIRMATIONS=$(cast call $MULTISIG "getConfirmations(uint256)(address[])" $PROPOSAL_ID --rpc-url $ANVIL_RPC)
log_info "Current confirmations: $CONFIRMATIONS"

# Owner 1 already confirmed during submission (check the event logs - ProposalConfirmed)
log_info "Checking if Owner 1 already confirmed..."
IS_CONFIRMED_1=$(cast call $MULTISIG "isConfirmedBy(uint256,address)(bool)" $PROPOSAL_ID $OWNER_1 --rpc-url $ANVIL_RPC)
log_info "Owner 1 confirmed: $IS_CONFIRMED_1"

if [ "$IS_CONFIRMED_1" == "false" ]; then
    log_info "Owner 1 confirming proposal..."
    cast send $MULTISIG "confirmProposal(uint256)" $PROPOSAL_ID \
        --from $OWNER_1 --rpc-url $ANVIL_RPC --unlocked --gas-limit 200000 > /dev/null
    log_success "Owner 1 confirmed"
else
    log_info "Owner 1 already confirmed from submission"
fi

# Owner 2 confirms
log_info "Owner 2 ($OWNER_2) confirming proposal..."
cast send $MULTISIG "confirmProposal(uint256)" $PROPOSAL_ID \
    --from $OWNER_2 --rpc-url $ANVIL_RPC --unlocked --gas-limit 200000 > /dev/null
log_success "Owner 2 confirmed"

# Owner 3 confirms
log_info "Owner 3 ($OWNER_3) confirming proposal..."
cast send $MULTISIG "confirmProposal(uint256)" $PROPOSAL_ID \
    --from $OWNER_3 --rpc-url $ANVIL_RPC --unlocked --gas-limit 200000 > /dev/null
log_success "Owner 3 confirmed"

# Check if fully confirmed
IS_FULLY_CONFIRMED=$(cast call $MULTISIG "isFullyConfirmed(uint256)(bool)" $PROPOSAL_ID --rpc-url $ANVIL_RPC)
log_info "Is fully confirmed: $IS_FULLY_CONFIRMED"

# Get confirmations
log_info "Getting all confirmations..."
cast call $MULTISIG "getConfirmations(uint256)(address[])" $PROPOSAL_ID --rpc-url $ANVIL_RPC

# =============================================================================
log_header "Step 5: Schedule Proposal"
# =============================================================================

log_info "Scheduling proposal..."
cast send $MULTISIG "scheduleProposal(uint256)" $PROPOSAL_ID \
    --from $OWNER_1 --rpc-url $ANVIL_RPC --unlocked --gas-limit 200000 > /dev/null
log_success "Proposal scheduled"

# Check timestamp
TIMESTAMP_RAW=$(cast call $MULTISIG "getTimestamp(uint256)(uint256)" $PROPOSAL_ID --rpc-url $ANVIL_RPC)
TIMESTAMP=$(parse_number "$TIMESTAMP_RAW")
log_info "Proposal executable timestamp: $TIMESTAMP"

# Check if scheduled
IS_SCHEDULED=$(cast call $MULTISIG "isScheduled(uint256)(bool)" $PROPOSAL_ID --rpc-url $ANVIL_RPC)
log_info "Is scheduled: $IS_SCHEDULED"

# =============================================================================
log_header "Step 6: Wait for Timelock (Fast-forward time)"
# =============================================================================

# Get the delay
DELAY_RAW=$(cast call $MULTISIG "delay()(uint256)" --rpc-url $ANVIL_RPC)
DELAY=$(parse_number "$DELAY_RAW")
log_info "Timelock delay: $DELAY seconds ($((DELAY / 86400)) days)"

# Fast forward time using Anvil's evm_increaseTime
log_info "Fast-forwarding time by $DELAY seconds..."
cast rpc evm_increaseTime $DELAY --rpc-url $ANVIL_RPC > /dev/null
cast rpc evm_mine --rpc-url $ANVIL_RPC > /dev/null
log_success "Time fast-forwarded"

# Check if timelock is reached
IS_TIMELOCK_REACHED=$(cast call $MULTISIG "isProposalTimelockReached(uint256)(bool)" $PROPOSAL_ID --rpc-url $ANVIL_RPC)
log_info "Is timelock reached: $IS_TIMELOCK_REACHED"

# =============================================================================
log_header "Step 7: Execute Proposal"
# =============================================================================

log_info "Executing proposal..."
set +e  # Don't exit on error
EXEC_RESULT=$(cast send $MULTISIG "executeProposal(uint256)" $PROPOSAL_ID \
    --from $OWNER_1 --rpc-url $ANVIL_RPC --unlocked --gas-limit 1000000 2>&1)
EXEC_EXIT_CODE=$?
set -e

echo "$EXEC_RESULT"

if [ $EXEC_EXIT_CODE -eq 0 ] && echo "$EXEC_RESULT" | grep -q "status.*1"; then
    log_success "Proposal executed successfully!"
else
    log_warn "Execution may have failed - checking results..."
fi

# =============================================================================
log_header "Step 8: Verify Result"
# =============================================================================

log_info "Checking new activatable groups count..."
NEW_COUNT_RAW=$(cast call $DEFAULT_STRATEGY "activatableGroupsCount()(uint256)" --rpc-url $ANVIL_RPC)
NEW_COUNT=$(parse_number "$NEW_COUNT_RAW")
log_info "New activatable groups count: $NEW_COUNT"

# Convert to decimal for comparison
OLD_DECIMAL=$((CURRENT_COUNT))
NEW_DECIMAL=$((NEW_COUNT))

if [ "$NEW_DECIMAL" -gt "$OLD_DECIMAL" ]; then
    log_success "Group was successfully added! Count increased from $OLD_DECIMAL to $NEW_DECIMAL"
else
    log_warn "Activatable groups count did not change (was $OLD_DECIMAL, now $NEW_DECIMAL)"
    log_info "This might indicate the execution failed or the group couldn't be added"
    
    # Check anvil logs for more info
    log_info "Last 20 lines of anvil log:"
    tail -20 /tmp/anvil.log
fi

# Try to get the group at the last index (if there are any groups)
if [ "$NEW_DECIMAL" -gt 0 ]; then
    LAST_INDEX=$((NEW_DECIMAL - 1))
    log_info "Checking group at index $LAST_INDEX..."
    ADDED_GROUP=$(cast call $DEFAULT_STRATEGY "getActivatableGroupAt(uint256)(address)" $LAST_INDEX --rpc-url $ANVIL_RPC)
    log_info "Group at last index: $ADDED_GROUP"
fi

# =============================================================================
log_header "TEST COMPLETED!"
# =============================================================================

echo ""
if [ "$NEW_DECIMAL" -gt "$OLD_DECIMAL" ]; then
    log_success "The multisig proposal test PASSED!"
else
    log_warn "The multisig proposal test completed with warnings"
fi
echo ""
echo "Summary:"
echo "  - Proposal ID: $PROPOSAL_ID"
echo "  - Target: DefaultStrategy ($DEFAULT_STRATEGY)"
echo "  - Function: addActivatableGroup($NEW_GROUP)"
echo "  - Activatable groups count: $OLD_DECIMAL -> $NEW_DECIMAL"
echo ""
