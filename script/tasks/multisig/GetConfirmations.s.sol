// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";

/**
 * @title GetConfirmationsScript
 * @notice Get list of addresses that have confirmed a proposal.
 *         Replaces `yarn hardhat stakedCelo:multiSig:getConfirmations --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/GetConfirmations.s.sol --rpc-url celo
 */
contract GetConfirmationsScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and prints the confirming owners.
    function run() external view {
        execute(multiSig(), vm.envUint("PROPOSAL_ID"));
    }

    /// @notice Prints the addresses that have confirmed `proposalId`.
    /// @param multiSigContract The MultiSig contract to read from.
    /// @param proposalId The ID of the proposal.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal view {
        address[] memory confirmations = multiSigContract.getConfirmations(proposalId);
        TaskConsole.log("Addresses that have confirmed the proposal:", confirmations.length);
        for (uint256 i = 0; i < confirmations.length; i++) {
            TaskConsole.log("confirmed by", confirmations[i]);
        }
    }
}
