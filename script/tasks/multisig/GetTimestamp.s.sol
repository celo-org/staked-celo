// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";

/**
 * @title GetTimestampScript
 * @notice Get a proposal timestamp.
 *         Replaces `yarn hardhat stakedCelo:multiSig:getTimestamp --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/GetTimestamp.s.sol --rpc-url celo
 */
contract GetTimestampScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and prints the executable timestamp.
    function run() external view {
        execute(multiSig(), vm.envUint("PROPOSAL_ID"));
    }

    /// @notice Prints the timestamp at which `proposalId` becomes executable.
    /// @param multiSigContract The MultiSig contract to read from.
    /// @param proposalId The ID of the proposal.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal view {
        TaskConsole.log("Proposal", proposalId);
        TaskConsole.log("timestamp", multiSigContract.getTimestamp(proposalId));
    }
}
