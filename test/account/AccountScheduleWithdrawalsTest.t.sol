// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/**
 * @notice Port of `describe("Account") > describe("#scheduleWithdrawals()")`.
 * @dev Deviation: the original shares one `scheduleWithdrawalTests()` factory between the three
 *      blocks "when votes are scheduled", "when votes are locked and pending" and "when votes
 *      are active", so the eight `it()` cases it declares run three times each. To keep one
 *      `test_` function per declared `it()`, every case here runs its body against all three
 *      vote states in turn, using `snapshotState` / `revertToState` to reset in between. No
 *      assertion of the original is lost.
 *
 *      Because the assertion helpers take no failure message, every iteration emits
 *      `VoteStateUnderTest` first so that `forge test -vvvv` shows which of the three states
 *      a failure belongs to. `revertToState` does not undo cheatcode state, so each revert is
 *      followed by `syncEpochMock()` to put the mocked epoch number back in step with
 *      `devchainEpochNumber` (the "active" state calls `mineToNextEpoch()`).
 */
contract AccountScheduleWithdrawalsTest is AccountTestBase {
    uint256 private constant VOTE_STATE_SCHEDULED = 0;
    uint256 private constant VOTE_STATE_LOCKED_AND_PENDING = 1;
    uint256 private constant VOTE_STATE_ACTIVE = 2;

    /// @dev Marks which of the three vote states an iteration runs against.
    event VoteStateUnderTest(uint256 voteState);

    // =========================================================================
    //                   when called by a non-manager
    // =========================================================================

    function test_scheduleWithdrawals_WhenCalledByANonManager_RevertsWithACallerNotManagerError()
        public
    {
        address[] memory groups = _allGroups();
        uint256[] memory amounts = _amounts(40, 40, 40);
        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        account.scheduleWithdrawals(beneficiary, groups, amounts);
    }

    // =========================================================================
    //                        SHARED FIXTURES
    // =========================================================================

    /// @dev The `beforeEach` of "when votes are scheduled" / "... locked and pending" /
    ///      "... active", which all start from 100 / 200 / 300 CELO scheduled.
    function _setupVoteState(uint256 voteState) private {
        _scheduleVotes(_allGroups(), _amounts(100, 200, 300), 600);
        if (voteState == VOTE_STATE_SCHEDULED) {
            return;
        }
        for (uint256 i = 0; i < 3; i++) {
            _activateAndVote(groupAddresses[i]);
        }
        if (voteState == VOTE_STATE_LOCKED_AND_PENDING) {
            return;
        }
        mineToNextEpoch();
        for (uint256 i = 0; i < 3; i++) {
            _activateAndVote(groupAddresses[i]);
        }
    }

    function _firstWithdrawal() private {
        _scheduleWithdrawals(beneficiary, _allGroups(), _amounts(40, 40, 40));
    }

    function _secondWithdrawal() private {
        _scheduleWithdrawals(otherBeneficiary, _allGroups(), _amounts(30, 30, 30));
    }

    // =========================================================================
    //              when the withdrawal amount is too high
    // =========================================================================

    function test_scheduleWithdrawals_WhenTheWithdrawalAmountIsTooHigh_RevertsWithAWithdrawalAmountTooHighError()
        public
    {
        for (uint256 voteState = 0; voteState < 3; voteState++) {
            emit VoteStateUnderTest(voteState);
            uint256 snapshotId = avm.snapshotState();
            _setupVoteState(voteState);
            _bodyRevertsWithAWithdrawalAmountTooHighError();
            avm.revertToState(snapshotId);
            syncEpochMock();
            assertEq(celoEpochManager.getCurrentEpochNumber(), devchainEpochNumber);
        }
    }

    function _bodyRevertsWithAWithdrawalAmountTooHighError() private {
        address[] memory groups = _allGroups();
        uint256[] memory amounts = _amounts(40, 40, 310);
        vm.prank(managerSigner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Account.WithdrawalAmountTooHigh.selector,
                groupAddresses[2],
                300,
                310
            )
        );
        account.scheduleWithdrawals(beneficiary, groups, amounts);
    }

    // =========================================================================
    //              when the withdrawal amount is in range
    // =========================================================================

    function test_scheduleWithdrawals_WhenTheWithdrawalAmountIsInRange_EmitsAnEventForEachGroup()
        public
    {
        for (uint256 voteState = 0; voteState < 3; voteState++) {
            emit VoteStateUnderTest(voteState);
            uint256 snapshotId = avm.snapshotState();
            _setupVoteState(voteState);
            _bodyEmitsAnEventForEachGroup();
            avm.revertToState(snapshotId);
            syncEpochMock();
            assertEq(celoEpochManager.getCurrentEpochNumber(), devchainEpochNumber);
        }
    }

    function _bodyEmitsAnEventForEachGroup() private {
        for (uint256 i = 0; i < 3; i++) {
            vm.expectEmit(true, true, true, true);
            emit CeloWithdrawalScheduled(beneficiary, groupAddresses[i], 40);
        }
        _firstWithdrawal();
    }

    function test_scheduleWithdrawals_WhenTheWithdrawalAmountIsInRange_IncrementsTotalScheduledWithdrawals()
        public
    {
        for (uint256 voteState = 0; voteState < 3; voteState++) {
            emit VoteStateUnderTest(voteState);
            uint256 snapshotId = avm.snapshotState();
            _setupVoteState(voteState);
            _firstWithdrawal();
            assertEq(account.totalScheduledWithdrawals(), 120);
            avm.revertToState(snapshotId);
            syncEpochMock();
            assertEq(celoEpochManager.getCurrentEpochNumber(), devchainEpochNumber);
        }
    }

    function test_scheduleWithdrawals_WhenTheWithdrawalAmountIsInRange_IncrementsScheduledVotesGroupToWithdraw()
        public
    {
        for (uint256 voteState = 0; voteState < 3; voteState++) {
            emit VoteStateUnderTest(voteState);
            uint256 snapshotId = avm.snapshotState();
            _setupVoteState(voteState);
            _firstWithdrawal();
            for (uint256 i = 0; i < 3; i++) {
                assertEq(account.scheduledWithdrawalsForGroup(groupAddresses[i]), 40);
            }
            avm.revertToState(snapshotId);
            syncEpochMock();
            assertEq(celoEpochManager.getCurrentEpochNumber(), devchainEpochNumber);
        }
    }

    function test_scheduleWithdrawals_WhenTheWithdrawalAmountIsInRange_IncrementsScheduledVotesGroupToWithdrawForBeneficiary()
        public
    {
        for (uint256 voteState = 0; voteState < 3; voteState++) {
            emit VoteStateUnderTest(voteState);
            uint256 snapshotId = avm.snapshotState();
            _setupVoteState(voteState);
            _firstWithdrawal();
            for (uint256 i = 0; i < 3; i++) {
                assertEq(
                    account.scheduledWithdrawalsForGroupAndBeneficiary(
                        groupAddresses[i],
                        beneficiary
                    ),
                    40
                );
            }
            avm.revertToState(snapshotId);
            syncEpochMock();
            assertEq(celoEpochManager.getCurrentEpochNumber(), devchainEpochNumber);
        }
    }

    // =========================================================================
    //                and a second withdrawal happens
    // =========================================================================

    function test_scheduleWithdrawals_WhenTheWithdrawalAmountIsInRange_AndASecondWithdrawalHappens_IncrementsTotalScheduledWithdrawals()
        public
    {
        for (uint256 voteState = 0; voteState < 3; voteState++) {
            emit VoteStateUnderTest(voteState);
            uint256 snapshotId = avm.snapshotState();
            _setupVoteState(voteState);
            _firstWithdrawal();
            _secondWithdrawal();
            assertEq(account.totalScheduledWithdrawals(), 210);
            avm.revertToState(snapshotId);
            syncEpochMock();
            assertEq(celoEpochManager.getCurrentEpochNumber(), devchainEpochNumber);
        }
    }

    function test_scheduleWithdrawals_WhenTheWithdrawalAmountIsInRange_AndASecondWithdrawalHappens_IncrementsScheduledVotesGroupToWithdraw()
        public
    {
        for (uint256 voteState = 0; voteState < 3; voteState++) {
            emit VoteStateUnderTest(voteState);
            uint256 snapshotId = avm.snapshotState();
            _setupVoteState(voteState);
            _firstWithdrawal();
            _secondWithdrawal();
            for (uint256 i = 0; i < 3; i++) {
                assertEq(account.scheduledWithdrawalsForGroup(groupAddresses[i]), 70);
            }
            avm.revertToState(snapshotId);
            syncEpochMock();
            assertEq(celoEpochManager.getCurrentEpochNumber(), devchainEpochNumber);
        }
    }

    function test_scheduleWithdrawals_WhenTheWithdrawalAmountIsInRange_AndASecondWithdrawalHappens_IncrementsScheduledVotesGroupToWithdrawForBeneficiary()
        public
    {
        for (uint256 voteState = 0; voteState < 3; voteState++) {
            emit VoteStateUnderTest(voteState);
            uint256 snapshotId = avm.snapshotState();
            _setupVoteState(voteState);
            _firstWithdrawal();
            _secondWithdrawal();
            _assertPerBeneficiaryWithdrawals();
            avm.revertToState(snapshotId);
            syncEpochMock();
            assertEq(celoEpochManager.getCurrentEpochNumber(), devchainEpochNumber);
        }
    }

    function _assertPerBeneficiaryWithdrawals() private view {
        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                account.scheduledWithdrawalsForGroupAndBeneficiary(groupAddresses[i], beneficiary),
                40
            );
            assertEq(
                account.scheduledWithdrawalsForGroupAndBeneficiary(
                    groupAddresses[i],
                    otherBeneficiary
                ),
                30
            );
        }
    }
}
