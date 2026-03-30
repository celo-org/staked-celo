#!/bin/bash

# =============================================================================
# Submit MultiSig Proposal: Expand DefaultStrategy from 6 to 10 Active Groups
# =============================================================================
#
# This script submits a single MultiSig proposal that:
#   1. setSortingParams(15, 15, 17) on DefaultStrategy
#   2. addActivatableGroup(Projecttent)
#   3. addActivatableGroup(Tessellated Geometry)
#   4. addActivatableGroup(atweb3)
#   5. addActivatableGroup(HappyCelo)
#
# After the proposal is executed (3 confirmations + 7-day timelock), anyone
# can call activateGroup() for each new group (permissionless).
#
# Usage:
#   # Dry run — encode calldata and print, no TX sent
#   ./propose-expand-to-10-groups.sh
#
#   # Submit from a specific signer (requires private key or hardware wallet)
#   ./propose-expand-to-10-groups.sh --submit --from <SIGNER_ADDRESS> --rpc-url <RPC>
#
#   # Submit with a private key (DANGEROUS — use hardware wallet in production)
#   ./propose-expand-to-10-groups.sh --submit --private-key <KEY> --rpc-url <RPC>
#
#   # Called from the test script (Anvil fork, impersonated accounts)
#   ./propose-expand-to-10-groups.sh --submit --from <OWNER> --rpc-url <RPC> --unlocked
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

# Contract addresses (Celo mainnet)
DEFAULT_STRATEGY="0x3A3ed74B1cC543D5EB323f70ac2F19977a0eA088"
GROUP_HEALTH="0x140b36FFc554d174fbf1B436C50D5409bDceCDCF"
MULTISIG="0x78DaA21FcE4D30E74fF745Da3204764a0ad40179"

# New groups (randomly selected from eligible, healthy, >= 1M capacity groups)
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

# Parse arguments
SUBMIT=false
CAST_ARGS=()
RPC_URL="https://forno.celo.org"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --submit)
            SUBMIT=true
            shift
            ;;
        --rpc-url)
            RPC_URL="$2"
            CAST_ARGS+=("--rpc-url" "$2")
            shift 2
            ;;
        --from)
            CAST_ARGS+=("--from" "$2")
            shift 2
            ;;
        --private-key)
            CAST_ARGS+=("--private-key" "$2")
            shift 2
            ;;
        --unlocked)
            CAST_ARGS+=("--unlocked")
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# If no --rpc-url was passed via args, add default
if ! printf '%s\n' "${CAST_ARGS[@]}" | grep -q -- '--rpc-url'; then
    CAST_ARGS+=("--rpc-url" "$RPC_URL")
fi

# =============================================================================
# Build proposal calldata
# =============================================================================

log_info "Building proposal: setSortingParams(15, 15, 17) + addActivatableGroup x4"
log_info ""

# 1. setSortingParams(15, 15, 17)
SORTING_PAYLOAD=$(cast calldata "setSortingParams(uint256,uint256,uint256)" 15 15 17)
log_info "Action 1: setSortingParams(15, 15, 17)"
log_info "  Target:  $DEFAULT_STRATEGY"
log_info "  Payload: $SORTING_PAYLOAD"

DESTINATIONS="$DEFAULT_STRATEGY"
VALUES="0"
PAYLOADS="$SORTING_PAYLOAD"

# 2-5. addActivatableGroup for each new group
for i in "${!NEW_GROUPS[@]}"; do
    PAYLOAD=$(cast calldata "addActivatableGroup(address)" "${NEW_GROUPS[$i]}")
    DESTINATIONS="$DESTINATIONS,$DEFAULT_STRATEGY"
    VALUES="$VALUES,0"
    PAYLOADS="$PAYLOADS,$PAYLOAD"
    log_info "Action $((i + 2)): addActivatableGroup(${GROUP_NAMES[$i]})"
    log_info "  Target:  $DEFAULT_STRATEGY"
    log_info "  Group:   ${NEW_GROUPS[$i]}"
    log_info "  Payload: $PAYLOAD"
done

log_info ""

# Encode the full submitProposal calldata
SUBMIT_CALLDATA=$(cast calldata "submitProposal(address[],uint256[],bytes[])" \
    "[$DESTINATIONS]" "[$VALUES]" "[$PAYLOADS]")

log_info "MultiSig: $MULTISIG"
log_info "Full submitProposal calldata:"
echo "$SUBMIT_CALLDATA"
log_info ""

# =============================================================================
# Pre-flight checks
# =============================================================================

log_info "Running pre-flight checks against $RPC_URL ..."

# Check current state
CURRENT_GROUPS=$(cast call $DEFAULT_STRATEGY "getNumberOfGroups()(uint256)" --rpc-url "$RPC_URL" | awk '{print $1}')
CURRENT_DIST=$(cast call $DEFAULT_STRATEGY "maxGroupsToDistributeTo()(uint256)" --rpc-url "$RPC_URL" | awk '{print $1}')
CURRENT_WITHDRAW=$(cast call $DEFAULT_STRATEGY "maxGroupsToWithdrawFrom()(uint256)" --rpc-url "$RPC_URL" | awk '{print $1}')

log_info "Current active groups:         $CURRENT_GROUPS"
log_info "Current maxGroupsToDistribute: $CURRENT_DIST"
log_info "Current maxGroupsToWithdraw:   $CURRENT_WITHDRAW"

# Check all new groups are healthy
ALL_HEALTHY=true
for i in "${!NEW_GROUPS[@]}"; do
    HEALTH=$(cast call $GROUP_HEALTH "isGroupValid(address)(bool)" "${NEW_GROUPS[$i]}" --rpc-url "$RPC_URL")
    if [ "$HEALTH" == "true" ]; then
        log_success "${GROUP_NAMES[$i]} (${NEW_GROUPS[$i]}): HEALTHY"
    else
        log_error "${GROUP_NAMES[$i]} (${NEW_GROUPS[$i]}): UNHEALTHY"
        ALL_HEALTHY=false
    fi
done

if [ "$ALL_HEALTHY" != "true" ]; then
    log_error "Not all groups are healthy. Fix health before submitting proposal."
    exit 1
fi

# Check groups are not already active or activatable
for i in "${!NEW_GROUPS[@]}"; do
    IS_ACTIVE=$(cast call $DEFAULT_STRATEGY "isActive(address)(bool)" "${NEW_GROUPS[$i]}" --rpc-url "$RPC_URL")
    if [ "$IS_ACTIVE" == "true" ]; then
        log_error "${GROUP_NAMES[$i]} is already active — remove from proposal"
        exit 1
    fi
done

log_success "All pre-flight checks passed"
log_info ""

# =============================================================================
# Submit or dry-run
# =============================================================================

if [ "$SUBMIT" = true ]; then
    log_info "Submitting proposal to MultiSig..."

    CURRENT_COUNT=$(cast call $MULTISIG "proposalCount()(uint256)" --rpc-url "$RPC_URL" | awk '{print $1}')
    log_info "Current proposal count: $CURRENT_COUNT (new proposal ID will be $CURRENT_COUNT)"

    set +e
    TX_RESULT=$(cast send $MULTISIG $SUBMIT_CALLDATA "${CAST_ARGS[@]}" --gas-limit 3000000 2>&1)
    TX_CODE=$?
    set -e

    if [ $TX_CODE -eq 0 ] && echo "$TX_RESULT" | grep -q "status.*1"; then
        TX_HASH=$(echo "$TX_RESULT" | grep "transactionHash" | awk '{print $2}')
        log_success "Proposal submitted!"
        log_info "Proposal ID: $CURRENT_COUNT"
        log_info "TX hash:     $TX_HASH"
        log_info ""
        log_info "Next steps:"
        log_info "  1. Owner 2 confirms: cast send $MULTISIG 'confirmProposal(uint256)' $CURRENT_COUNT --rpc-url $RPC_URL"
        log_info "  2. Owner 3 confirms: cast send $MULTISIG 'confirmProposal(uint256)' $CURRENT_COUNT --rpc-url $RPC_URL"
        log_info "  3. Schedule (if not auto-scheduled): cast send $MULTISIG 'scheduleProposal(uint256)' $CURRENT_COUNT --rpc-url $RPC_URL"
        log_info "  4. Wait 7 days for timelock"
        log_info "  5. Execute: cast send $MULTISIG 'executeProposal(uint256)' $CURRENT_COUNT --rpc-url $RPC_URL"
        log_info "  6. Activate groups (anyone can call):"
        log_info "     cast send $DEFAULT_STRATEGY 'activateGroup(address,address,address)' <group> <lesser> <greater> --rpc-url $RPC_URL"
    else
        log_error "Proposal submission failed"
        echo "$TX_RESULT"
        exit 1
    fi
else
    log_info "DRY RUN — no transaction sent"
    log_info ""
    log_info "To submit, run:"
    log_info "  $0 --submit --from <SIGNER_ADDRESS> --rpc-url https://forno.celo.org"
    log_info ""
    log_info "Or with a private key (DANGEROUS):"
    log_info "  $0 --submit --private-key <KEY> --rpc-url https://forno.celo.org"
    log_info ""
    log_info "To test on Anvil fork first:"
    log_info "  anvil --fork-url https://forno.celo.org --port 8545"
    log_info "  $0 --submit --from $OWNER_1 --rpc-url http://localhost:8545 --unlocked"
fi
