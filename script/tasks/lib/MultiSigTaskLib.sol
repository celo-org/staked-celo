// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskInterfaces.sol";
import "./TaskVm.sol";

/**
 * @title MultiSigTaskLib
 * @notice Solidity port of lib/multiSig-tasks/*.ts. Holds the body of every multiSig task so
 *         that the forge scripts and the tests run the same code.
 * @dev The functions are `internal` and therefore inlined into the caller: the MultiSig
 *      calls originate from the script (inside vm.startBroadcast) or from the test contract
 *      (so vm.prank applies), never from the library itself.
 */
library MultiSigTaskLib {
    /**
     * @notice Submits a proposal and returns its ID.
     * @dev The Hardhat task read the ID out of the ProposalScheduled event; submitProposal
     *      returns it directly.
     * @param multiSig The MultiSig contract.
     * @param destinations The addresses at which the operations are targeted.
     * @param values The CELO values involved in the proposal if any.
     * @param payloads The payloads of the proposal.
     * @return proposalId The ID of the submitted proposal.
     */
    function submitProposal(
        IMultiSigTask multiSig,
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory payloads
    ) internal returns (uint256 proposalId) {
        require(
            destinations.length == values.length && values.length == payloads.length,
            "Destinations, values and payloads need to have same length"
        );
        proposalId = multiSig.submitProposal(destinations, values, payloads);
        TaskConsole.log("Proposal id:", proposalId);
    }

    /// @notice Confirms `proposalId`.
    /// @param multiSig The MultiSig contract.
    /// @param proposalId The ID of the proposal to confirm.
    function confirmProposal(IMultiSigTask multiSig, uint256 proposalId) internal {
        multiSig.confirmProposal(proposalId);
        TaskConsole.log("Confirmed proposal", proposalId);
    }

    /// @notice Revokes the caller's confirmation of `proposalId`.
    /// @param multiSig The MultiSig contract.
    /// @param proposalId The ID of the proposal.
    function revokeConfirmation(IMultiSigTask multiSig, uint256 proposalId) internal {
        multiSig.revokeConfirmation(proposalId);
        TaskConsole.log("Revoked confirmation of proposal", proposalId);
    }

    /// @notice Schedules `proposalId` and reports when it becomes executable.
    /// @param multiSig The MultiSig contract.
    /// @param proposalId The ID of the proposal.
    function scheduleProposal(IMultiSigTask multiSig, uint256 proposalId) internal {
        multiSig.scheduleProposal(proposalId);
        TaskConsole.log("Scheduled proposal", proposalId);
        TaskConsole.log("executable at (unix seconds)", multiSig.getTimestamp(proposalId));
    }

    /**
     * @notice Executes `proposalId` after checking that its time-lock has elapsed.
     * @dev The pre-check mirrors the Hardhat task, which reported the earliest execution
     *      time instead of letting the MultiSig modifier revert without context.
     * @param multiSig The MultiSig contract.
     * @param proposalId The ID of the proposal.
     */
    function executeProposal(IMultiSigTask multiSig, uint256 proposalId) internal {
        if (!multiSig.isProposalTimelockReached(proposalId)) {
            TaskConsole.log("proposal", proposalId);
            TaskConsole.log(
                "executable soonest at (unix seconds)",
                multiSig.getTimestamp(proposalId)
            );
            revert("Timelock of proposal has not been reached yet");
        }

        multiSig.executeProposal(proposalId);
        TaskConsole.log("Executed proposal", proposalId);
    }
}
