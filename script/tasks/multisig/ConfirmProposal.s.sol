// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/MultiSigTaskLib.sol";

/**
 * @title ConfirmProposalScript
 * @notice Confirm a multiSig proposal. Replaces
 *         `yarn hardhat stakedCelo:multiSig:confirmProposal --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/ConfirmProposal.s.sol \
 *     --rpc-url celo --broadcast --ledger --sender <ledger address>
 */
contract ConfirmProposalScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and confirms as the broadcaster.
    function run() external {
        IMultiSigTask multiSigContract = multiSig();
        uint256 proposalId = vm.envUint("PROPOSAL_ID");

        vm.startBroadcast();
        execute(multiSigContract, proposalId);
        vm.stopBroadcast();
    }

    /// @notice Confirms `proposalId`.
    /// @param multiSigContract The MultiSig contract to confirm on.
    /// @param proposalId The ID of the proposal to confirm.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal {
        MultiSigTaskLib.confirmProposal(multiSigContract, proposalId);
    }
}
