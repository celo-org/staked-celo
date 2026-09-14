// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/FormatLib.sol";

/**
 * @title GetProposalScript
 * @notice Get a multiSig proposal by its ID.
 *         Replaces `yarn hardhat stakedCelo:multiSig:getProposal --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/GetProposal.s.sol --rpc-url celo
 */
contract GetProposalScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and prints the proposal.
    function run() external view {
        execute(multiSig(), vm.envUint("PROPOSAL_ID"));
    }

    /// @notice Prints the destinations, values and payloads of `proposalId`.
    /// @param multiSigContract The MultiSig contract to read from.
    /// @param proposalId The ID of the proposal.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal view {
        (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        ) = multiSigContract.getProposal(proposalId);

        TaskConsole.log("Proposal", proposalId);
        TaskConsole.log("destinations", FormatLib.join(destinations));
        TaskConsole.log("values", FormatLib.join(values));
        TaskConsole.log("payloads", FormatLib.join(payloads));
    }
}
