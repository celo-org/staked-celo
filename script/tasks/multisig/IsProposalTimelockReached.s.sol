// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";

/**
 * @title IsProposalTimelockReachedScript
 * @notice Check if a proposal time-lock has been reached. Replaces
 *         `yarn hardhat stakedCelo:multiSig:isProposalTimelockReached --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/IsProposalTimelockReached.s.sol \
 *     --rpc-url celo
 */
contract IsProposalTimelockReachedScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and prints the time-lock state.
    function run() external view {
        execute(multiSig(), vm.envUint("PROPOSAL_ID"));
    }

    /// @notice Prints whether the time-lock of `proposalId` has been reached.
    /// @param multiSigContract The MultiSig contract to read from.
    /// @param proposalId The ID of the proposal.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal view {
        TaskConsole.log(
            "is timelock reached:",
            multiSigContract.isProposalTimelockReached(proposalId)
        );
    }
}
