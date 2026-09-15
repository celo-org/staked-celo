// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/MultiSigTaskLib.sol";

/**
 * @title ScheduleProposalScript
 * @notice Schedule a proposal. Replaces
 *         `yarn hardhat stakedCelo:multiSig:scheduleProposal --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/ScheduleProposal.s.sol \
 *     --rpc-url celo --broadcast --ledger --sender <ledger address>
 */
contract ScheduleProposalScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and schedules as the broadcaster.
    function run() external {
        IMultiSigTask multiSigContract = multiSig();
        uint256 proposalId = vm.envUint("PROPOSAL_ID");

        vm.startBroadcast();
        execute(multiSigContract, proposalId);
        vm.stopBroadcast();
    }

    /// @notice Schedules `proposalId`.
    /// @param multiSigContract The MultiSig contract to schedule on.
    /// @param proposalId The ID of the proposal.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal {
        MultiSigTaskLib.scheduleProposal(multiSigContract, proposalId);
    }
}
