// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#withdraw()")`.
contract AccountWithdrawTest is AccountTestBase {
    // =========================================================================
    //                   when there are scheduled votes
    // =========================================================================

    function _setupScheduledVotes() private {
        _scheduleVotes(groupAddresses[0], 100);
        _scheduleWithdrawals(beneficiary, groupAddresses[0], 60);
    }

    function test_withdraw_WhenThereAreScheduledVotes_EmitsCeloWithdrawalStarted() public {
        _setupScheduledVotes();
        vm.expectEmit(true, true, true, true);
        emit CeloWithdrawalStarted(beneficiary, groupAddresses[0], 60);
        _withdraw(beneficiary, groupAddresses[0]);
    }

    function test_withdraw_WhenThereAreScheduledVotes_ImmediatelyTransfersOutScheduledCelo()
        public
    {
        _setupScheduledVotes();
        uint256 balanceBefore = beneficiary.balance;
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(beneficiary.balance - balanceBefore, 60);
    }

    function test_withdraw_WhenThereAreScheduledVotes_DecrementsScheduledVotes() public {
        _setupScheduledVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 40);
    }

    // =========================================================================
    //                    when there are pending votes
    // =========================================================================

    function _setupPendingVotes() private {
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
        _scheduleWithdrawals(beneficiary, groupAddresses[0], 60);
    }

    function test_withdraw_WhenThereArePendingVotes_RevokesPendingVotes() public {
        _setupPendingVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(_pendingVotes(groupAddresses[0]), 40);
    }

    function test_withdraw_WhenThereArePendingVotes_UnlocksCelo() public {
        _setupPendingVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        _assertSingleLockedGoldWithdrawal(60);
    }

    function test_withdraw_WhenThereArePendingVotes_InternallyAssignsTheWithdrawalToBeneficiary()
        public
    {
        _setupPendingVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        (uint256 value, ) = account.getPendingWithdrawal(beneficiary, 0);
        assertEq(value, 60);
    }

    // =========================================================================
    //             when there are pending and revoked votes
    // =========================================================================

    function _setupPendingAndRevokedVotes() private {
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
        _scheduleVotes(groupAddresses[0], 50);
        _scheduleTransfer(groupAddresses[0], groupAddresses[1], 40);
        _scheduleWithdrawals(beneficiary, groupAddresses[0], 60);
    }

    function test_withdraw_WhenThereArePendingAndRevokedVotes_RevokesPendingVotes() public {
        _setupPendingAndRevokedVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(_pendingVotes(groupAddresses[0]), 50);
    }

    function test_withdraw_WhenThereArePendingAndRevokedVotes_UnlocksCelo() public {
        _setupPendingAndRevokedVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        _assertSingleLockedGoldWithdrawal(50);
    }

    function test_withdraw_WhenThereArePendingAndRevokedVotes_InternallyAssignsTheWithdrawalToBeneficiary()
        public
    {
        _setupPendingAndRevokedVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        (uint256 value, ) = account.getPendingWithdrawal(beneficiary, 0);
        assertEq(value, 50);
    }

    function test_withdraw_WhenThereArePendingAndRevokedVotes_ImmediatelyTransferOutScheduledNonRevokedCelo()
        public
    {
        _setupPendingAndRevokedVotes();
        uint256 balanceBefore = beneficiary.balance;
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(beneficiary.balance - balanceBefore, 10);
    }

    // =========================================================================
    //                    when there are active votes
    // =========================================================================

    function _setupActiveVotes() private {
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
        mineToNextEpoch();
        _activateAndVote(groupAddresses[0]);
        _scheduleWithdrawals(beneficiary, groupAddresses[0], 60);
    }

    function test_withdraw_WhenThereAreActiveVotes_RevokesActiveVotes() public {
        _setupActiveVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(_activeVotes(groupAddresses[0]), 40);
    }

    function test_withdraw_WhenThereAreActiveVotes_UnlocksCelo() public {
        _setupActiveVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        _assertSingleLockedGoldWithdrawal(60);
    }

    function test_withdraw_WhenThereAreActiveVotes_InternallyAssignsTheWithdrawalToBeneficiary()
        public
    {
        _setupActiveVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        (uint256 value, ) = account.getPendingWithdrawal(beneficiary, 0);
        assertEq(value, 60);
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
        _scheduleWithdrawals(beneficiary, groupAddresses[0], 250);
    }

    function test_withdraw_WhenThereAreScheduledPendingAndActiveVotes_ImmediatelyTransfersOutScheduledCelo()
        public
    {
        _setupScheduledPendingAndActiveVotes();
        uint256 balanceBefore = beneficiary.balance;
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(beneficiary.balance - balanceBefore, 100);
    }

    function test_withdraw_WhenThereAreScheduledPendingAndActiveVotes_RevokesPendingVotes()
        public
    {
        _setupScheduledPendingAndActiveVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(_pendingVotes(groupAddresses[0]), 0);
    }

    function test_withdraw_WhenThereAreScheduledPendingAndActiveVotes_RevokesActiveVotes() public {
        _setupScheduledPendingAndActiveVotes();
        _withdraw(beneficiary, groupAddresses[0]);
        assertEq(_activeVotes(groupAddresses[0]), 50);
    }

    // =========================================================================
    //                        INTERNAL HELPERS
    // =========================================================================

    function _assertSingleLockedGoldWithdrawal(uint256 expectedValue) private view {
        (uint256[] memory values, ) = celoLockedGold.getPendingWithdrawals(address(account));
        assertEq(values.length, 1);
        assertEq(values[0], expectedValue);
    }
}
