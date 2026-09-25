// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#getCeloForGroup()")`.
contract AccountGetCeloForGroupTest is AccountTestBase {
    function test_getCeloForGroup_Returns0WhenThereWereNoVotes() public view {
        assertEq(account.getCeloForGroup(groupAddresses[0]), 0);
    }

    /// @dev The `when some of them have been withdrawn` block, which is identical in the
    ///      scheduled / pending / active / mixed blocks.
    function _withdrawFromFirstGroup(uint256 amount) private {
        _scheduleWithdrawals(beneficiary, groupAddresses[0], amount);
        _withdraw(beneficiary, groupAddresses[0]);
    }

    // =========================================================================
    //                   when there are scheduled votes
    // =========================================================================

    function test_getCeloForGroup_WhenThereAreScheduledVotes_ReportsThem() public {
        _scheduleVotes(groupAddresses[0], 100);
        assertEq(account.getCeloForGroup(groupAddresses[0]), 100);
    }

    function test_getCeloForGroup_WhenThereAreScheduledVotes_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _scheduleVotes(groupAddresses[0], 100);
        _withdrawFromFirstGroup(60);
        assertEq(account.getCeloForGroup(groupAddresses[0]), 40);
    }

    // =========================================================================
    //                    when there are pending votes
    // =========================================================================

    function _setupPendingVotes() private {
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
    }

    function test_getCeloForGroup_WhenThereArePendingVotes_ReportsThem() public {
        _setupPendingVotes();
        assertEq(account.getCeloForGroup(groupAddresses[0]), 100);
    }

    function test_getCeloForGroup_WhenThereArePendingVotes_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _setupPendingVotes();
        _withdrawFromFirstGroup(60);
        assertEq(account.getCeloForGroup(groupAddresses[0]), 40);
    }

    // =========================================================================
    //                    when there are revoked votes
    // =========================================================================

    function _setupRevokedVotes() private {
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
        _scheduleTransfer(groupAddresses[0], groupAddresses[1], 30);
        _revokeVotesForGroup(groupAddresses[0]);
        _revokeVotesForGroup(groupAddresses[1]);
        _activateAndVote(groupAddresses[1]);
    }

    function test_getCeloForGroup_WhenThereAreRevokedVotes_WhenThereIsEnoughStCeloLockedFromPreviousTransfers_ReportsThem()
        public
    {
        _setupRevokedVotes();
        assertEq(account.getCeloForGroup(groupAddresses[0]), 70);
        assertEq(account.getCeloForGroup(groupAddresses[1]), 30);
    }

    function test_getCeloForGroup_WhenThereAreRevokedVotes_WhenThereIsEnoughStCeloLockedFromPreviousTransfers_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _setupRevokedVotes();
        _scheduleWithdrawals(beneficiary, groupAddresses[1], 20);
        _withdraw(beneficiary, groupAddresses[1]);
        assertEq(account.getCeloForGroup(groupAddresses[1]), 10);
    }

    // =========================================================================
    //                     when there are active votes
    // =========================================================================

    function _setupActiveVotes() private {
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
        mineToNextEpoch();
        _activateAndVote(groupAddresses[0]);
    }

    function test_getCeloForGroup_WhenThereAreActiveVotes_ReportsThem() public {
        _setupActiveVotes();
        assertEq(account.getCeloForGroup(groupAddresses[0]), 100);
    }

    function test_getCeloForGroup_WhenThereAreActiveVotes_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _setupActiveVotes();
        _withdrawFromFirstGroup(60);
        assertEq(account.getCeloForGroup(groupAddresses[0]), 40);
    }

    // =========================================================================
    //        when there are scheduled, pending, and active votes
    // =========================================================================

    function _setupScheduledPendingAndActiveVotes() private {
        // These votes will be activated.
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
        mineToNextEpoch();
        _activateAndVote(groupAddresses[0]);
        // These votes will be cast but remain pending in Elections.
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
        // These votes will remain scheduled in Account.
        _scheduleVotes(groupAddresses[0], 100);
    }

    function test_getCeloForGroup_WhenThereAreScheduledPendingAndActiveVotes_ReportsAllOfThem()
        public
    {
        _setupScheduledPendingAndActiveVotes();
        assertEq(account.getCeloForGroup(groupAddresses[0]), 300);
    }

    function test_getCeloForGroup_WhenThereAreScheduledPendingAndActiveVotes_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _setupScheduledPendingAndActiveVotes();
        _withdrawFromFirstGroup(260);
        assertEq(account.getCeloForGroup(groupAddresses[0]), 40);
    }
}
