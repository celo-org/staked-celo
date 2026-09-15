// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/MultiSigTaskLib.sol";

/**
 * @title ExecuteProposalScript
 * @notice Execute a multiSig proposal. Replaces
 *         `yarn hardhat stakedCelo:multiSig:executeProposal --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/ExecuteProposal.s.sol \
 *     --rpc-url celo --broadcast --ledger --sender <ledger address>
 */
contract ExecuteProposalScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and executes as the broadcaster.
    function run() external {
        IMultiSigTask multiSigContract = multiSig();
        uint256 proposalId = vm.envUint("PROPOSAL_ID");

        vm.startBroadcast();
        execute(multiSigContract, proposalId);
        vm.stopBroadcast();
    }

    /**
     * @notice Executes `proposalId` after checking that its time-lock has elapsed.
     * @dev The pre-check mirrors the Hardhat task, which reported the earliest execution
     *      time instead of letting the MultiSig modifier revert without context.
     * @param multiSigContract The MultiSig contract to execute on.
     * @param proposalId The ID of the proposal.
     */
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal {
        MultiSigTaskLib.executeProposal(multiSigContract, proposalId);
    }
}
