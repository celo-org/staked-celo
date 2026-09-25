// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskInterfaces.sol";
import "./TaskVm.sol";

/**
 * @title ManagerTaskLib
 * @notice Solidity port of lib/manager-tasks/*.ts. Holds the body of the deposit, withdraw
 *         and voteProposal tasks so that the forge scripts and the tests run the same code.
 */
library ManagerTaskLib {
    /// @notice Deposits `amount` CELO into the protocol.
    /// @param manager The Manager contract.
    /// @param amount The amount of CELO to deposit, in wei.
    function deposit(IManagerTask manager, uint256 amount) internal {
        manager.deposit{value: amount}();
        TaskConsole.log("Deposited CELO", amount);
    }

    /// @notice Withdraws `amount` stCELO from the protocol.
    /// @param manager The Manager contract.
    /// @param amount The amount of stCELO to withdraw, in wei.
    function withdraw(IManagerTask manager, uint256 amount) internal {
        manager.withdraw(amount);
        TaskConsole.log("Withdrew stCELO", amount);
    }

    /**
     * @notice Votes on a governance proposal with the caller's stCELO.
     * @dev The index of the proposal within the governance dequeue is resolved first,
     *      exactly as the Hardhat task did through the ContractKit Governance wrapper.
     * @param manager The Manager contract.
     * @param governance The Celo Governance contract.
     * @param proposalId The ID of the governance proposal.
     * @param yesVotes The yes vote weight.
     * @param noVotes The no vote weight.
     * @param abstainVotes The abstain vote weight.
     */
    function voteProposal(
        IManagerTask manager,
        IGovernanceLookup governance,
        uint256 proposalId,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) internal {
        require(
            yesVotes > 0 || noVotes > 0 || abstainVotes > 0,
            "At least one vote choice needs to be > 0."
        );

        uint256 index = dequeueIndex(governance, proposalId);
        manager.voteProposal(proposalId, index, yesVotes, noVotes, abstainVotes);
        TaskConsole.log("Voted on proposal", proposalId);
    }

    /// @notice Index of `proposalId` in Governance's dequeued proposal list.
    /// @param governance The Celo Governance contract.
    /// @param proposalId The ID of the governance proposal.
    /// @return The index of the proposal in the dequeue.
    function dequeueIndex(IGovernanceLookup governance, uint256 proposalId)
        internal
        view
        returns (uint256)
    {
        uint256[] memory dequeue = governance.getDequeue();
        for (uint256 i = 0; i < dequeue.length; i++) {
            if (dequeue[i] == proposalId) {
                return i;
            }
        }
        revert("Proposal is not dequeued!");
    }
}
