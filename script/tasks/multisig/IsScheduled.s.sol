// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";

/**
 * @title IsScheduledScript
 * @notice Check if a proposal is scheduled.
 *         Replaces `yarn hardhat stakedCelo:multiSig:isScheduled --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/IsScheduled.s.sol --rpc-url celo
 */
contract IsScheduledScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and prints the schedule state.
    function run() external view {
        execute(multiSig(), vm.envUint("PROPOSAL_ID"));
    }

    /// @notice Prints whether `proposalId` is scheduled.
    /// @param multiSigContract The MultiSig contract to read from.
    /// @param proposalId The ID of the proposal.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal view {
        TaskConsole.log("Is Proposal scheduled:", multiSigContract.isScheduled(proposalId));
    }
}
