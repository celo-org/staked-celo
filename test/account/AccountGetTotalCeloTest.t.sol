// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#getTotalCelo()")`.
contract AccountGetTotalCeloTest is AccountTestBase {
    function test_getTotalCelo_Returns0WhenThereWereNoVotes() public view {
        assertEq(account.getTotalCelo(), 0);
    }

    /// @dev The `when some of them have been withdrawn` block, identical in every parent block.
    function _withdrawFromFirstGroup(uint256 amount) private {
        _scheduleWithdrawals(beneficiary, groupAddresses[0], amount);
        _withdraw(beneficiary, groupAddresses[0]);
    }

    // =========================================================================
    //                   when there are scheduled votes
    // =========================================================================

    function test_getTotalCelo_WhenThereAreScheduledVotes_ReportsThem() public {
        _scheduleVotes(groupAddresses[0], 100);
        assertEq(account.getTotalCelo(), 100);
    }

    function test_getTotalCelo_WhenThereAreScheduledVotes_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _scheduleVotes(groupAddresses[0], 100);
        _withdrawFromFirstGroup(60);
        assertEq(account.getTotalCelo(), 40);
    }

    // =========================================================================
    //                    when there are pending votes
    // =========================================================================

    function _setupPendingVotes() private {
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
    }

    function test_getTotalCelo_WhenThereArePendingVotes_ReportsThem() public {
        _setupPendingVotes();
        assertEq(account.getTotalCelo(), 100);
    }

    function test_getTotalCelo_WhenThereArePendingVotes_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _setupPendingVotes();
        _withdrawFromFirstGroup(60);
        assertEq(account.getTotalCelo(), 40);
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

    function test_getTotalCelo_WhenThereAreActiveVotes_ReportsThem() public {
        _setupActiveVotes();
        assertEq(account.getTotalCelo(), 100);
    }

    function test_getTotalCelo_WhenThereAreActiveVotes_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _setupActiveVotes();
        _withdrawFromFirstGroup(60);
        assertEq(account.getTotalCelo(), 40);
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

    function test_getTotalCelo_WhenThereAreScheduledPendingAndActiveVotes_ReportsAllOfThem()
        public
    {
        _setupScheduledPendingAndActiveVotes();
        assertEq(account.getTotalCelo(), 300);
    }

    function test_getTotalCelo_WhenThereAreScheduledPendingAndActiveVotes_WhenSomeOfThemHaveBeenWithdrawn_ReportsOnlyTheRemainingVotes()
        public
    {
        _setupScheduledPendingAndActiveVotes();
        _withdrawFromFirstGroup(260);
        assertEq(account.getTotalCelo(), 40);
    }
}
