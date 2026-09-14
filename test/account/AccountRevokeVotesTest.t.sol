// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#revokeVotes()")`.
contract AccountRevokeVotesTest is AccountTestBase {
    uint256 private constant ORIGINAL_AMOUNT = 100;
    uint256 private constant TRANSFER_AMOUNT = 30;
    uint256 private constant TRANSFER_AMOUNT_2 = 15;

    /// @dev `true` reproduces "when there are active votes for group", `false` the
    ///      "when there are pending votes for group" block.
    bool private constant PENDING = false;
    bool private constant ACTIVE = true;

    // =========================================================================
    //                           TOP-LEVEL CASE
    // =========================================================================

    function test_revokeVotes_ShouldSucceedWhenThereIsNothingToRevoke() public {
        account.revokeVotes(
            groupAddresses[0],
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            0
        );
    }

    // =========================================================================
    //                    when there are scheduled votes
    // =========================================================================

    function test_revokeVotes_WhenThereAreScheduledVotes_ShouldReturnScheduledVotesForOriginalGroup()
        public
    {
        _scheduleVotes(groupAddresses[0], ORIGINAL_AMOUNT);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), ORIGINAL_AMOUNT);
    }

    function _setupScheduledTransferToNewGroup() private {
        _scheduleVotes(groupAddresses[0], ORIGINAL_AMOUNT);
        _scheduleTransfer(groupAddresses[0], groupAddresses[1], TRANSFER_AMOUNT);
        _revokeVotesForGroup(groupAddresses[0]);
        _revokeVotesForGroup(groupAddresses[1]);
    }

    function test_revokeVotes_WhenThereAreScheduledVotes_WhenThereIsTransferToNewGroup_ShouldReturnCorrectAmountOfScheduledVotes()
        public
    {
        _setupScheduledTransferToNewGroup();
        assertEq(
            account.scheduledVotesForGroup(groupAddresses[0]),
            ORIGINAL_AMOUNT - TRANSFER_AMOUNT
        );
        assertEq(account.scheduledVotesForGroup(groupAddresses[1]), TRANSFER_AMOUNT);
    }

    function test_revokeVotes_WhenThereAreScheduledVotes_WhenThereIsTransferToNewGroup_ShouldReturnCorrectAmountOfRevokedVotes()
        public
    {
        _setupScheduledTransferToNewGroup();
        assertEq(account.scheduledRevokeForGroup(groupAddresses[0]), 0);
        assertEq(account.scheduledRevokeForGroup(groupAddresses[1]), 0);
    }

    function _setupScheduledSendingToThirdGroup() private {
        _setupScheduledTransferToNewGroup();
        _scheduleTransfer(groupAddresses[1], groupAddresses[2], TRANSFER_AMOUNT_2);
        _revokeVotesForGroup(groupAddresses[0]);
        _revokeVotesForGroup(groupAddresses[1]);
    }

    function test_revokeVotes_WhenThereAreScheduledVotes_WhenThereIsTransferToNewGroup_WhenSendingToThirdGroup_ShouldReturnCorrectAmountOfScheduledVotes()
        public
    {
        _setupScheduledSendingToThirdGroup();
        assertEq(
            account.scheduledVotesForGroup(groupAddresses[1]),
            TRANSFER_AMOUNT - TRANSFER_AMOUNT_2
        );
        assertEq(account.scheduledVotesForGroup(groupAddresses[2]), TRANSFER_AMOUNT_2);
    }

    function test_revokeVotes_WhenThereAreScheduledVotes_WhenThereIsTransferToNewGroup_WhenSendingToThirdGroup_ShouldReturnCorrectAmountOfRevokedVotes()
        public
    {
        _setupScheduledSendingToThirdGroup();
        assertEq(account.scheduledRevokeForGroup(groupAddresses[1]), 0);
        assertEq(account.scheduledRevokeForGroup(groupAddresses[2]), 0);
    }

    // =========================================================================
    //           SHARED FIXTURES OF THE PENDING / ACTIVE BLOCKS
    // =========================================================================

    function _setupVotedGroup(bool activated) private {
        _scheduleVotes(groupAddresses[0], ORIGINAL_AMOUNT);
        _activateAndVote(groupAddresses[0]);
        if (activated) {
            mineToNextEpoch();
            _activateAndVote(groupAddresses[0]);
        }
    }

    function _setupTransferToNewGroup(bool activated) private {
        _setupVotedGroup(activated);
        _scheduleTransfer(groupAddresses[0], groupAddresses[1], TRANSFER_AMOUNT);
        _revokeVotesForGroup(groupAddresses[0]);
        _revokeVotesForGroup(groupAddresses[1]);
    }

    function _setupRevokeAndActivateImmediately(bool activated) private {
        _setupTransferToNewGroup(activated);
        _revokeVotesForGroup(groupAddresses[0]);
        _revokeVotesForGroup(groupAddresses[1]);
        _activateAndVote(groupAddresses[0]);
        _activateAndVote(groupAddresses[1]);
    }

    function _setupSendingToThirdGroupBeforeRevokeAndActivate(bool activated) private {
        _setupTransferToNewGroup(activated);
        _scheduleTransfer(groupAddresses[1], groupAddresses[2], TRANSFER_AMOUNT_2);
        _revokeVotesForGroup(groupAddresses[0]);
        _revokeVotesForGroup(groupAddresses[1]);
        _revokeVotesForGroup(groupAddresses[2]);
        _activateAndVote(groupAddresses[0]);
        _activateAndVote(groupAddresses[1]);
        _activateAndVote(groupAddresses[2]);
    }

    function _assertNoScheduledVotesForTwoGroups() private view {
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 0);
        assertEq(account.scheduledVotesForGroup(groupAddresses[1]), 0);
    }

    function _assertNoRevokedVotesForTwoGroups() private view {
        assertEq(account.scheduledRevokeForGroup(groupAddresses[0]), 0);
        assertEq(account.scheduledRevokeForGroup(groupAddresses[1]), 0);
    }

    function _assertActiveVotesAfterTransfer() private view {
        assertEq(_totalVotes(groupAddresses[0]), ORIGINAL_AMOUNT - TRANSFER_AMOUNT);
        assertEq(_totalVotes(groupAddresses[1]), TRANSFER_AMOUNT);
    }

    function _assertNoScheduledVotesForThreeGroups() private view {
        _assertNoScheduledVotesForTwoGroups();
        assertEq(account.scheduledVotesForGroup(groupAddresses[2]), 0);
    }

    function _assertNoRevokedVotesForThreeGroups() private view {
        _assertNoRevokedVotesForTwoGroups();
        assertEq(account.scheduledRevokeForGroup(groupAddresses[2]), 0);
    }

    function _assertActiveVotesAfterThirdTransfer() private view {
        assertEq(_totalVotes(groupAddresses[0]), ORIGINAL_AMOUNT - TRANSFER_AMOUNT);
        assertEq(_totalVotes(groupAddresses[1]), TRANSFER_AMOUNT - TRANSFER_AMOUNT_2);
        assertEq(_totalVotes(groupAddresses[2]), TRANSFER_AMOUNT_2);
    }

    // =========================================================================
    //                when there are pending votes for group
    // =========================================================================

    function test_revokeVotes_WhenThereArePendingVotesForGroup_ShouldReturnNoScheduledVotesForOriginalGroup()
        public
    {
        _setupVotedGroup(PENDING);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 0);
    }

    function test_revokeVotes_WhenThereArePendingVotesForGroup_ShouldReturnActiveVotesForOriginalGroup()
        public
    {
        _setupVotedGroup(PENDING);
        assertEq(_totalVotes(groupAddresses[0]), ORIGINAL_AMOUNT);
    }

    function test_revokeVotes_WhenThereArePendingVotesForGroup_WhenThereIsTransferToNewGroup_WhenRevokeAndActivateIsCalledImmediatelyAfterScheduleTransfer_ShouldReturnCorrectAmountOfScheduledVotes()
        public
    {
        _setupRevokeAndActivateImmediately(PENDING);
        _assertNoScheduledVotesForTwoGroups();
    }

    function test_revokeVotes_WhenThereArePendingVotesForGroup_WhenThereIsTransferToNewGroup_WhenRevokeAndActivateIsCalledImmediatelyAfterScheduleTransfer_ShouldReturnCorrectAmountOfRevokedVotes()
        public
    {
        _setupRevokeAndActivateImmediately(PENDING);
        _assertNoRevokedVotesForTwoGroups();
    }

    function test_revokeVotes_WhenThereArePendingVotesForGroup_WhenThereIsTransferToNewGroup_WhenRevokeAndActivateIsCalledImmediatelyAfterScheduleTransfer_ShouldReturnCorrectAmountOfActiveVotes()
        public
    {
        _setupRevokeAndActivateImmediately(PENDING);
        _assertActiveVotesAfterTransfer();
    }

    function test_revokeVotes_WhenThereArePendingVotesForGroup_WhenThereIsTransferToNewGroup_WhenSendingToThirdGroupBeforeRevokeAndActivate_ShouldReturnCorrectAmountOfScheduledVotes()
        public
    {
        _setupSendingToThirdGroupBeforeRevokeAndActivate(PENDING);
        _assertNoScheduledVotesForThreeGroups();
    }

    function test_revokeVotes_WhenThereArePendingVotesForGroup_WhenThereIsTransferToNewGroup_WhenSendingToThirdGroupBeforeRevokeAndActivate_ShouldReturnCorrectAmountOfRevokedVotes()
        public
    {
        _setupSendingToThirdGroupBeforeRevokeAndActivate(PENDING);
        _assertNoRevokedVotesForThreeGroups();
    }

    function test_revokeVotes_WhenThereArePendingVotesForGroup_WhenThereIsTransferToNewGroup_WhenSendingToThirdGroupBeforeRevokeAndActivate_ShouldReturnCorrectAmountOfActiveVotes()
        public
    {
        _setupSendingToThirdGroupBeforeRevokeAndActivate(PENDING);
        _assertActiveVotesAfterThirdTransfer();
    }

    // =========================================================================
    //                when there are active votes for group
    // =========================================================================

    function test_revokeVotes_WhenThereAreActiveVotesForGroup_ShouldReturnNoScheduledVotesForOriginalGroup()
        public
    {
        _setupVotedGroup(ACTIVE);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 0);
    }

    function test_revokeVotes_WhenThereAreActiveVotesForGroup_ShouldReturnActiveVotesForOriginalGroup()
        public
    {
        _setupVotedGroup(ACTIVE);
        assertEq(_totalVotes(groupAddresses[0]), ORIGINAL_AMOUNT);
    }

    function test_revokeVotes_WhenThereAreActiveVotesForGroup_WhenThereIsTransferToNewGroup_WhenRevokeAndActivateIsCalledImmediatelyAfterScheduleTransfer_ShouldReturnCorrectAmountOfScheduledVotes()
        public
    {
        _setupRevokeAndActivateImmediately(ACTIVE);
        _assertNoScheduledVotesForTwoGroups();
    }

    function test_revokeVotes_WhenThereAreActiveVotesForGroup_WhenThereIsTransferToNewGroup_WhenRevokeAndActivateIsCalledImmediatelyAfterScheduleTransfer_ShouldReturnCorrectAmountOfRevokedVotes()
        public
    {
        _setupRevokeAndActivateImmediately(ACTIVE);
        _assertNoRevokedVotesForTwoGroups();
    }

    function test_revokeVotes_WhenThereAreActiveVotesForGroup_WhenThereIsTransferToNewGroup_WhenRevokeAndActivateIsCalledImmediatelyAfterScheduleTransfer_ShouldReturnCorrectAmountOfActiveVotes()
        public
    {
        _setupRevokeAndActivateImmediately(ACTIVE);
        _assertActiveVotesAfterTransfer();
    }

    function test_revokeVotes_WhenThereAreActiveVotesForGroup_WhenThereIsTransferToNewGroup_WhenSendingToThirdGroupBeforeRevokeAndActivate_ShouldReturnCorrectAmountOfScheduledVotes()
        public
    {
        _setupSendingToThirdGroupBeforeRevokeAndActivate(ACTIVE);
        _assertNoScheduledVotesForThreeGroups();
    }

    function test_revokeVotes_WhenThereAreActiveVotesForGroup_WhenThereIsTransferToNewGroup_WhenSendingToThirdGroupBeforeRevokeAndActivate_ShouldReturnCorrectAmountOfRevokedVotes()
        public
    {
        _setupSendingToThirdGroupBeforeRevokeAndActivate(ACTIVE);
        _assertNoRevokedVotesForThreeGroups();
    }

    function test_revokeVotes_WhenThereAreActiveVotesForGroup_WhenThereIsTransferToNewGroup_WhenSendingToThirdGroupBeforeRevokeAndActivate_ShouldReturnCorrectAmountOfActiveVotes()
        public
    {
        _setupSendingToThirdGroupBeforeRevokeAndActivate(ACTIVE);
        _assertActiveVotesAfterThirdTransfer();
    }
}
