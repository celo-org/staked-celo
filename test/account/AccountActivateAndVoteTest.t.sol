// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#activateAndVote()")`.
contract AccountActivateAndVoteTest is AccountTestBase {
    // =========================================================================
    //                 when there are scheduled votes
    // =========================================================================

    /// @dev The `beforeEach` shared by every block of `#activateAndVote()`.
    function _scheduleTwoRounds() internal {
        _scheduleVotes(_allGroups(), _amounts(100, 30, 70), 200);
        _scheduleVotes(_allGroups(), _amounts(40, 50, 20), 110);
    }

    function test_activateAndVote_WhenThereAreScheduledVotes_LocksCelo() public {
        _scheduleTwoRounds();
        _activateAndVote(groupAddresses[0]);
        assertEq(celoLockedGold.getAccountTotalLockedGold(address(account)), 140);
    }

    function test_activateAndVote_WhenThereAreScheduledVotes_ResetsPendingVotesForTheGroup()
        public
    {
        _scheduleTwoRounds();
        _activateAndVote(groupAddresses[0]);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 0);
    }

    function test_activateAndVote_WhenThereAreScheduledVotes_CastsVotesForTheGroup() public {
        _scheduleTwoRounds();
        _activateAndVote(groupAddresses[0]);
        assertEq(_pendingVotes(groupAddresses[0]), 140);
    }

    // =========================================================================
    //                when there are activatable votes
    // =========================================================================

    function test_activateAndVote_WhenThereAreActivatableVotes_ActivatesVotes() public {
        _scheduleTwoRounds();
        _activateAndVote(groupAddresses[0]);
        mineToNextEpoch();

        _activateAndVote(groupAddresses[0]);
        assertEq(_activeVotes(groupAddresses[0]), 140);
    }

    // =========================================================================
    //      when there are both scheduled and activatable votes
    // =========================================================================

    function _setupScheduledAndActivatable() internal {
        _scheduleTwoRounds();
        _activateAndVote(groupAddresses[0]);
        _scheduleVotes(_allGroups(), _amounts(10, 20, 30), 60);
        mineToNextEpoch();
        _scheduleVotes(_allGroups(), _amounts(30, 20, 10), 60);
    }

    function test_activateAndVote_WhenThereAreBothScheduledAndActivatableVotes_LocksAdditionalCelo()
        public
    {
        _setupScheduledAndActivatable();
        _activateAndVote(groupAddresses[0]);
        assertEq(celoLockedGold.getAccountTotalLockedGold(address(account)), 180);
    }

    function test_activateAndVote_WhenThereAreBothScheduledAndActivatableVotes_ResetsPendingVotesForTheGroup()
        public
    {
        _setupScheduledAndActivatable();
        _activateAndVote(groupAddresses[0]);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 0);
    }

    function test_activateAndVote_WhenThereAreBothScheduledAndActivatableVotes_ActivatesPreviouslyCastVotesForTheGroup()
        public
    {
        _setupScheduledAndActivatable();
        _activateAndVote(groupAddresses[0]);
        assertEq(_activeVotes(groupAddresses[0]), 140);
    }

    function test_activateAndVote_WhenThereAreBothScheduledAndActivatableVotes_CastsNewPendingVotesForTheGroup()
        public
    {
        _setupScheduledAndActivatable();
        _activateAndVote(groupAddresses[0]);
        assertEq(_pendingVotes(groupAddresses[0]), 40);
    }

    // =========================================================================
    //            When group doesnt have enough of Celo
    // =========================================================================

    function _setupAllGroupsActivated() internal {
        _scheduleTwoRounds();
        for (uint256 i = 0; i < 3; i++) {
            _activateAndVote(groupAddresses[i]);
        }
        mineToNextEpoch();
        for (uint256 i = 0; i < 3; i++) {
            _activateAndVote(groupAddresses[i]);
        }
    }

    function test_activateAndVote_WhenGroupDoesntHaveEnoughOfCelo_ShouldActivateWhenNotEnoughOfCeloInAccount()
        public
    {
        _setupAllGroupsActivated();

        _scheduleTransfer(groupAddresses[0], groupAddresses[1], 100);
        _scheduleVotes(groupAddresses[1], 5);

        assertEq(account.scheduledVotesForGroup(groupAddresses[1]), 105);
        assertEq(account.scheduledRevokeForGroup(groupAddresses[1]), 0);
        assertEq(account.scheduledWithdrawalsForGroup(groupAddresses[1]), 0);
        assertEq(account.votesForGroup(groupAddresses[1]), 80);
        assertEq(address(account).balance, 5);

        _activateAndVote(groupAddresses[1]);

        assertEq(account.scheduledVotesForGroup(groupAddresses[1]), 100);
        assertEq(account.scheduledRevokeForGroup(groupAddresses[1]), 0);
        assertEq(account.scheduledWithdrawalsForGroup(groupAddresses[1]), 0);
        assertEq(account.votesForGroup(groupAddresses[1]), 85);
        assertEq(address(account).balance, 0);
    }
}
