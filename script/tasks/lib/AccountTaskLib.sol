// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskInterfaces.sol";
import "./ElectionLib.sol";
import "./GroupsLib.sol";

/**
 * @title AccountTaskLib
 * @notice Solidity port of lib/account-tasks/helpers/*.ts. Holds the logic of the
 *         activateAndVote, revoke, withdraw and finishPendingWithdrawal tasks so that both
 *         the forge scripts and the tests run exactly the same code.
 * @dev The functions are `internal`, so they are inlined into the caller: the external
 *      calls they make originate from the script (inside vm.startBroadcast) or from the
 *      test contract (so vm.prank applies), never from the library itself.
 */
library AccountTaskLib {
    /// @dev The four neighbour hints Account.withdraw / Account.revokeVotes take.
    struct RevokeNeighbours {
        address lesserAfterPendingRevoke;
        address greaterAfterPendingRevoke;
        address lesserAfterActiveRevoke;
        address greaterAfterActiveRevoke;
    }

    // =========================================================================
    //                           ACTIVATE AND VOTE
    // =========================================================================

    /**
     * @notice Activates pending votes and votes with the scheduled CELO of every group the
     *         protocol is voting for.
     * @param account The StakedCelo Account contract.
     * @param defaultStrategy The DefaultStrategy contract.
     * @param specificGroupStrategy The SpecificGroupStrategy contract.
     * @param electionContract The Celo Election contract.
     */
    function activateAndVote(
        IAccountTask account,
        IDefaultStrategyTask defaultStrategy,
        ISpecificGroupStrategyTask specificGroupStrategy,
        IElectionLookup electionContract
    ) internal {
        address[] memory groups = GroupsLib.allGroups(defaultStrategy, specificGroupStrategy);
        for (uint256 i = 0; i < groups.length; i++) {
            _activateAndVoteForGroup(account, electionContract, groups[i]);
        }
    }

    /// @dev Election is asked per group, so groups with nothing to do are skipped.
    function _activateAndVoteForGroup(
        IAccountTask account,
        IElectionLookup electionContract,
        address group
    ) private {
        uint256 amountScheduled = account.scheduledVotesForGroup(group);
        bool canActivateForGroup = electionContract.hasActivatablePendingVotes(
            address(account),
            group
        );
        if (amountScheduled == 0 && !canActivateForGroup) {
            return;
        }

        (address lesser, address greater) = ElectionLib.findLesserAndGreaterAfterVote(
            electionContract,
            group,
            int256(amountScheduled)
        );
        account.activateAndVote(group, lesser, greater);
    }

    // =========================================================================
    //                                 REVOKE
    // =========================================================================

    /**
     * @notice Revokes the votes scheduled to be revoked for every group.
     * @param account The StakedCelo Account contract.
     * @param defaultStrategy The DefaultStrategy contract.
     * @param specificGroupStrategy The SpecificGroupStrategy contract.
     * @param electionContract The Celo Election contract.
     */
    function revoke(
        IAccountTask account,
        IDefaultStrategyTask defaultStrategy,
        ISpecificGroupStrategyTask specificGroupStrategy,
        IElectionLookup electionContract
    ) internal {
        address[] memory groups = GroupsLib.allGroups(defaultStrategy, specificGroupStrategy);
        for (uint256 i = 0; i < groups.length; i++) {
            uint256 scheduledToRevokeAmount = account.scheduledRevokeForGroup(groups[i]);
            if (scheduledToRevokeAmount == 0) {
                continue;
            }
            _revokeForGroup(account, electionContract, groups[i], scheduledToRevokeAmount);
        }
    }

    /// @dev One Account.revokeVotes call with the neighbour hints for the group.
    function _revokeForGroup(
        IAccountTask account,
        IElectionLookup electionContract,
        address group,
        uint256 scheduledToRevokeAmount
    ) private {
        RevokeNeighbours memory neighbours = revokeNeighbours(
            account,
            electionContract,
            group,
            scheduledToRevokeAmount
        );
        uint256 index = ElectionLib.findAddressIndex(electionContract, address(account), group);

        account.revokeVotes(
            group,
            neighbours.lesserAfterPendingRevoke,
            neighbours.greaterAfterPendingRevoke,
            neighbours.lesserAfterActiveRevoke,
            neighbours.greaterAfterActiveRevoke,
            index
        );
    }

    // =========================================================================
    //                                WITHDRAW
    // =========================================================================

    /**
     * @notice Withdraws the CELO scheduled for `beneficiary` from every group.
     * @param account The StakedCelo Account contract.
     * @param defaultStrategy The DefaultStrategy contract.
     * @param specificGroupStrategy The SpecificGroupStrategy contract.
     * @param electionContract The Celo Election contract.
     * @param beneficiary The address the withdrawal was scheduled for.
     */
    function withdraw(
        IAccountTask account,
        IDefaultStrategyTask defaultStrategy,
        ISpecificGroupStrategyTask specificGroupStrategy,
        IElectionLookup electionContract,
        address beneficiary
    ) internal {
        address[] memory groups = GroupsLib.allGroups(defaultStrategy, specificGroupStrategy);
        for (uint256 i = 0; i < groups.length; i++) {
            uint256 scheduledWithdrawalAmount = account
                .scheduledWithdrawalsForGroupAndBeneficiary(groups[i], beneficiary);
            if (scheduledWithdrawalAmount == 0) {
                continue;
            }
            _withdrawFromGroup(
                account,
                electionContract,
                groups[i],
                beneficiary,
                scheduledWithdrawalAmount
            );
        }
    }

    /// @dev One Account.withdraw call with the neighbour hints for the group.
    function _withdrawFromGroup(
        IAccountTask account,
        IElectionLookup electionContract,
        address group,
        address beneficiary,
        uint256 scheduledWithdrawalAmount
    ) private {
        RevokeNeighbours memory neighbours = revokeNeighbours(
            account,
            electionContract,
            group,
            scheduledWithdrawalAmount
        );
        uint256 index = ElectionLib.findAddressIndex(electionContract, address(account), group);

        account.withdraw(
            beneficiary,
            group,
            neighbours.lesserAfterPendingRevoke,
            neighbours.greaterAfterPendingRevoke,
            neighbours.lesserAfterActiveRevoke,
            neighbours.greaterAfterActiveRevoke,
            index
        );
    }

    // =========================================================================
    //                          NEIGHBOUR COMPUTATION
    // =========================================================================

    /**
     * @notice Computes the lesser/greater hints for revoking `scheduledAmount` from `group`.
     * @dev Ports the shared body of revokeHelper.ts and withdrawalHelper.ts. The CELO that
     *      is still scheduled to vote is withdrawn immediately and never revoked, so only
     *      the remainder moves the group in Election's sorted list. Pending votes are
     *      revoked before active ones within the same transaction, so the active hints are
     *      computed against the full remainder rather than against what is left after the
     *      pending revoke.
     * @param account The StakedCelo Account contract.
     * @param electionContract The Celo Election contract.
     * @param group The validator group being revoked from.
     * @param scheduledAmount The scheduled revoke or withdrawal amount for the group.
     * @return neighbours The four neighbour hints; all zero when nothing has to be revoked.
     */
    function revokeNeighbours(
        IAccountTask account,
        IElectionLookup electionContract,
        address group,
        uint256 scheduledAmount
    ) internal view returns (RevokeNeighbours memory neighbours) {
        uint256 immediateWithdrawalAmount = account.scheduledVotesForGroup(group);
        if (immediateWithdrawalAmount >= scheduledAmount) {
            return neighbours;
        }

        uint256 remainingRevokeAmount = scheduledAmount - immediateWithdrawalAmount;
        uint256 pendingVotes = electionContract.getPendingVotesForGroupByAccount(
            group,
            address(account)
        );
        uint256 toRevokeFromPending = remainingRevokeAmount < pendingVotes
            ? remainingRevokeAmount
            : pendingVotes;

        (
            neighbours.lesserAfterPendingRevoke,
            neighbours.greaterAfterPendingRevoke
        ) = ElectionLib.findLesserAndGreaterAfterVote(
            electionContract,
            group,
            -int256(toRevokeFromPending)
        );

        (
            neighbours.lesserAfterActiveRevoke,
            neighbours.greaterAfterActiveRevoke
        ) = ElectionLib.findLesserAndGreaterAfterVote(
            electionContract,
            group,
            -int256(remainingRevokeAmount)
        );
    }

    // =========================================================================
    //                       FINISH PENDING WITHDRAWALS
    // =========================================================================

    /**
     * @notice Finishes every released pending withdrawal of `beneficiary`.
     * @param account The StakedCelo Account contract.
     * @param lockedGoldContract The Celo LockedGold contract.
     * @param beneficiary The address the pending withdrawals belong to.
     */
    function finishPendingWithdrawals(
        IAccountTask account,
        ILockedGoldLookup lockedGoldContract,
        address beneficiary
    ) internal {
        while (true) {
            (bool found, uint256 localIndex, uint256 lockedGoldIndex) = pendingWithdrawalIndexes(
                account,
                lockedGoldContract,
                beneficiary
            );
            if (!found) {
                return;
            }
            account.finishPendingWithdrawal(beneficiary, localIndex, lockedGoldIndex);
        }
    }

    /**
     * @notice Finds the first released pending withdrawal of `beneficiary` and its matching
     *         entry in LockedGold.
     * @param account The StakedCelo Account contract.
     * @param lockedGoldContract The Celo LockedGold contract.
     * @param beneficiary The address the pending withdrawals belong to.
     * @return found Whether a released pending withdrawal exists.
     * @return localIndex Its index in Account's pending withdrawal array.
     * @return lockedGoldIndex The index of the matching LockedGold pending withdrawal.
     */
    function pendingWithdrawalIndexes(
        IAccountTask account,
        ILockedGoldLookup lockedGoldContract,
        address beneficiary
    )
        internal
        view
        returns (
            bool found,
            uint256 localIndex,
            uint256 lockedGoldIndex
        )
    {
        (uint256[] memory values, uint256[] memory timestamps) = account.getPendingWithdrawals(
            beneficiary
        );
        require(values.length == timestamps.length, "mismatched list");

        for (uint256 i = 0; i < timestamps.length; i++) {
            if (timestamps[i] < block.timestamp) {
                found = true;
                localIndex = i;
                break;
            }
        }
        if (!found) {
            return (false, 0, 0);
        }

        lockedGoldIndex = _matchingLockedGoldIndex(
            lockedGoldContract,
            address(account),
            values[localIndex],
            timestamps[localIndex]
        );
    }

    /// @dev Index of the LockedGold pending withdrawal with the same value and timestamp.
    function _matchingLockedGoldIndex(
        ILockedGoldLookup lockedGoldContract,
        address accountAddress,
        uint256 value,
        uint256 timestamp
    ) private view returns (uint256) {
        (uint256[] memory values, uint256[] memory timestamps) = lockedGoldContract
            .getPendingWithdrawals(accountAddress);
        for (uint256 i = 0; i < values.length; i++) {
            if (timestamps[i] == timestamp && values[i] == value) {
                return i;
            }
        }
        revert("No matching pending withdrawal. Locked Gold index not found.");
    }
}
