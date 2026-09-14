// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#finishPendingWithdrawal()")`.
contract AccountFinishPendingWithdrawalTest is AccountTestBase {
    /// @dev The original waited `LOCKED_GOLD_UNLOCKING_PERIOD` (3 days on the ganache
    ///      devchain); the unlocking period is read from LockedGold here because the anvil
    ///      devchain uses 6 hours.
    function _setupPendingWithdrawalReady() private {
        _scheduleVotes(groupAddresses[0], 100);
        _activateAndVote(groupAddresses[0]);
        _scheduleWithdrawals(beneficiary, groupAddresses[0], 60);
        _withdraw(beneficiary, groupAddresses[0]);
        timeTravel(celoLockedGold.unlockingPeriod());
    }

    function test_finishPendingWithdrawal_WhenThereIsAPendingWithdrawalReady_TransfersOutCelo()
        public
    {
        _setupPendingWithdrawalReady();
        uint256 balanceBefore = beneficiary.balance;
        account.finishPendingWithdrawal(beneficiary, 0, 0);
        assertEq(beneficiary.balance - balanceBefore, 60);
    }

    function test_finishPendingWithdrawal_WhenThereIsAPendingWithdrawalReady_HasToBeCalledWithTheCorrectBeneficiary()
        public
    {
        _setupPendingWithdrawalReady();
        vm.expectRevert(
            abi.encodeWithSelector(Account.PendingWithdrawalIndexTooHigh.selector, 0, 0)
        );
        account.finishPendingWithdrawal(nonBeneficiary, 0, 0);
    }

    function test_finishPendingWithdrawal_WhenThereIsAPendingWithdrawalReady_RemovesThePendingWithdrawal()
        public
    {
        _setupPendingWithdrawalReady();
        account.finishPendingWithdrawal(beneficiary, 0, 0);
        assertEq(account.getNumberPendingWithdrawals(beneficiary), 0);
    }
}
