// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./ManagerTestBase.sol";

/**
 * @title ManagerDepositOverflowTest
 * @notice Ports the `#deposit() > when groups are close to their voting limit` and
 *         `#deposit() > When depositing originally healthy overflowing specific group that
 *         became unhealthy` blocks of test-ts/manager.test.ts.
 */
contract ManagerDepositOverflowTest is ManagerTestBase {
    /// @dev `depositAmount` of `When voting for specific strategy with overflow`.
    uint256 private constant SPECIFIC_OVERFLOW_DEPOSIT = 100 ether;

    /// @dev `depositOverCapacity` / `deposit2` of the unhealthy overflow block.
    uint256 private constant DEPOSIT_OVER_CAPACITY = 10 ether;
    uint256 private constant DEPOSIT2 = 5 ether;

    /// @dev `firstGroupScheduled` / `secondGroupScheduled` / `thirdGroupScheduled`.
    uint256 private constant FIRST_GROUP_SCHEDULED = 30 ether;
    uint256 private constant SECOND_GROUP_SCHEDULED = 50 ether;
    uint256 private constant THIRD_GROUP_SCHEDULED = 170 ether;

    // =========================================================================
    //            when groups are close to their voting limit
    // =========================================================================

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_DepositToOnlyOneGroupIfWithinCapacity()
        public
    {
        prepareOverflowAndReadCapacities(true);

        vm.prank(depositor);
        manager.deposit{value: 30 ether}();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(groupAddresses[0]));
        assertEq(votes, arr(uint256(30 ether)));
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_DepositTo2GroupsWhenOverCapacityOfFirst()
        public
    {
        prepareOverflowAndReadCapacities(true);

        vm.prank(depositor);
        manager.deposit{value: 50 ether}();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(groupAddresses[0], groupAddresses[1]));
        assertEq(votes, arr(firstGroupCapacity, 50 ether - firstGroupCapacity));
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_DepositTo3GroupsWhenOverCapacityOfFirstAndSecond()
        public
    {
        prepareOverflowAndReadCapacities(true);

        vm.prank(depositor);
        manager.deposit{value: 150 ether}();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertMembers(groups, groupSlice(3));
        assertMembers(
            votes,
            arr(
                firstGroupCapacity,
                secondGroupCapacity,
                150 ether - firstGroupCapacity - secondGroupCapacity
            )
        );
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_RevertsWhenTheDepositTotalWouldPushAllGroupsOverTheirCapacity()
        public
    {
        prepareOverflowAndReadCapacities(true);

        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(DefaultStrategy.NotAbleToDistributeVotes.selector));
        manager.deposit{value: 350 ether}();
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenThereAreScheduledVotesForTheGroups_DepositToOnlyOneGroupIfWithinCapacity()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpScheduledVotes();

        vm.prank(depositor);
        manager.deposit{value: 5 ether}();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(groupAddresses[0]));
        assertEq(votes, arr(uint256(5 ether)));
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenThereAreScheduledVotesForTheGroups_DepositTo2GroupsWhenOverCapacityOfFirst()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpScheduledVotes();

        vm.prank(depositor);
        manager.deposit{value: 50 ether}();

        uint256 firstLeft = firstGroupCapacity - FIRST_GROUP_SCHEDULED;
        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(groupAddresses[0], groupAddresses[1]));
        assertEq(votes, arr(firstLeft, 50 ether - firstLeft));
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenThereAreScheduledVotesForTheGroups_DepositTo3GroupsWhenOverCapacityOfFirstAndSecond()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpScheduledVotes();

        vm.prank(depositor);
        manager.deposit{value: 80 ether}();

        uint256 firstLeft = firstGroupCapacity - FIRST_GROUP_SCHEDULED;
        uint256 secondLeft = secondGroupCapacity - SECOND_GROUP_SCHEDULED;
        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, groupSlice(3));
        assertEq(votes, arr(firstLeft, secondLeft, 80 ether - firstLeft - secondLeft));
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenThereAreScheduledVotesForTheGroups_RevertsWhenTheDepositTotalWouldPushAllGroupsOverTheirCapacity()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpScheduledVotes();

        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(DefaultStrategy.NotAbleToDistributeVotes.selector));
        manager.deposit{value: 100 ether}();
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_When11_ShouldOverflowToDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        depositSpecificOverflow();

        (uint256 stCeloInStrategy, uint256 overflowAmount,) =
            specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(stCeloInStrategy, SPECIFIC_OVERFLOW_DEPOSIT);
        assertEq(overflowAmount, SPECIFIC_OVERFLOW_DEPOSIT - firstGroupCapacity);
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_When11_ShouldScheduleTheOverflowToDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        depositSpecificOverflow();

        assertOverflowScheduled();
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_When11_ShouldNotChangeTotalStCeloOfDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        depositSpecificOverflow();

        assertEq(
            mockDefaultStrategy.totalStCeloInStrategy(),
            SPECIFIC_OVERFLOW_DEPOSIT - firstGroupCapacity
        );
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldOverflowToDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        uint256 capacityInStCelo = setUpRatioAndDeposit(200 ether);

        (uint256 stCeloInStrategy, uint256 overflowAmount,) =
            specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(stCeloInStrategy, SPECIFIC_OVERFLOW_DEPOSIT / 2);
        assertEq(overflowAmount, SPECIFIC_OVERFLOW_DEPOSIT / 2 - capacityInStCelo);
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldScheduleTheOverflowToDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        setUpRatioAndDeposit(200 ether);

        assertOverflowScheduled();
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldNotChangeTotalStCeloOfDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        uint256 capacityInStCelo = setUpRatioAndDeposit(200 ether);

        assertEq(
            mockDefaultStrategy.totalStCeloInStrategy(),
            SPECIFIC_OVERFLOW_DEPOSIT / 2 - capacityInStCelo
        );
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldOverflowToDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        uint256 capacityInStCelo = setUpRatioAndDeposit(50 ether);

        (uint256 stCeloInStrategy, uint256 overflowAmount,) =
            specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(stCeloInStrategy, SPECIFIC_OVERFLOW_DEPOSIT * 2);
        assertEq(overflowAmount, SPECIFIC_OVERFLOW_DEPOSIT * 2 - capacityInStCelo);
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldScheduleTheOverflowToDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        setUpRatioAndDeposit(50 ether);

        assertOverflowScheduled();
    }

    function test_deposit_WhenGroupsAreCloseToTheirVotingLimit_WhenVotingForSpecificStrategyWithOverflow_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldNotChangeTotalStCeloOfDefaultStrategy()
        public
    {
        prepareOverflowAndReadCapacities(true);
        setUpSpecificStrategyWithOverflow();
        uint256 capacityInStCelo = setUpRatioAndDeposit(50 ether);

        assertEq(
            mockDefaultStrategy.totalStCeloInStrategy(),
            SPECIFIC_OVERFLOW_DEPOSIT * 2 - capacityInStCelo
        );
    }

    // =========================================================================
    //   When depositing originally healthy overflowing specific group that
    //   became unhealthy
    // =========================================================================

    function test_deposit_WhenDepositingOriginallyHealthyOverflowingSpecificGroupThatBecameUnhealthy_WhenDifferentRatiosOfCeloVsStCelo_When11_ShouldScheduleTransfersCorrectly()
        public
    {
        setUpUnhealthyOverflow();
        address nextToTail = depositSecondTime();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(nextToTail));
        assertEq(votes, arr(DEPOSIT2));
    }

    function test_deposit_WhenDepositingOriginallyHealthyOverflowingSpecificGroupThatBecameUnhealthy_WhenDifferentRatiosOfCeloVsStCelo_When11_ShouldHaveStCeloInStrategy()
        public
    {
        uint256 deposit = setUpUnhealthyOverflow();
        depositSecondTime();

        (uint256 total, uint256 overflow, uint256 unhealthy) =
            specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(total, DEPOSIT2 + deposit);
        assertEq(overflow, DEPOSIT_OVER_CAPACITY);
        // there is only deposit2 since rebalanceWhenHealthChanged was not called
        assertEq(unhealthy, DEPOSIT2);
    }

    function test_deposit_WhenDepositingOriginallyHealthyOverflowingSpecificGroupThatBecameUnhealthy_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldScheduleTransfersCorrectly()
        public
    {
        uint256 deposit = setUpUnhealthyOverflow();
        mockAccount.setTotalCelo(deposit * 2);
        address nextToTail = depositSecondTime();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(nextToTail));
        assertEq(votes, arr(DEPOSIT2));
    }

    function test_deposit_WhenDepositingOriginallyHealthyOverflowingSpecificGroupThatBecameUnhealthy_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldHaveStCeloInStrategy()
        public
    {
        uint256 deposit = setUpUnhealthyOverflow();
        mockAccount.setTotalCelo(deposit * 2);
        uint256 deposit2InStCelo = manager.toStakedCelo(DEPOSIT2);
        depositSecondTime();

        (uint256 total, uint256 overflow, uint256 unhealthy) =
            specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(total, deposit + deposit2InStCelo);
        assertEq(overflow, DEPOSIT_OVER_CAPACITY);
        assertEq(unhealthy, deposit2InStCelo);
    }

    // =========================================================================
    //                          BLOCK FIXTURES
    // =========================================================================

    /// @dev `beforeEach` of `when there are scheduled votes for the groups`.
    function setUpScheduledVotes() private {
        mockAccount.setCeloForGroup(groupAddresses[0], FIRST_GROUP_SCHEDULED);
        mockAccount.setCeloForGroup(groupAddresses[1], SECOND_GROUP_SCHEDULED);
        mockAccount.setCeloForGroup(groupAddresses[2], THIRD_GROUP_SCHEDULED);
    }

    /// @dev `beforeEach` of `When voting for specific strategy with overflow`.
    function setUpSpecificStrategyWithOverflow() private {
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);
    }

    /// @dev `beforeEach` of the nested `When 1:1` block.
    function depositSpecificOverflow() private {
        vm.prank(depositor);
        manager.deposit{value: SPECIFIC_OVERFLOW_DEPOSIT}();
    }

    /// @dev `beforeEach` of the nested ratio blocks; returns `firstGroupCapacityInStCelo`.
    function setUpRatioAndDeposit(uint256 totalCelo) private returns (uint256 capacityInStCelo) {
        mockAccount.setTotalCelo(totalCelo);
        mockStakedCelo.mint(someone, 100 ether);
        capacityInStCelo = manager.toStakedCelo(firstGroupCapacity);
        depositSpecificOverflow();
    }

    /// @dev `beforeEach` of `When depositing originally healthy overflowing specific group
    ///      that became unhealthy`.
    function setUpUnhealthyOverflow() private returns (uint256 deposit) {
        prepareOverflowAndReadCapacities(true);
        deposit = firstGroupCapacity + DEPOSIT_OVER_CAPACITY;

        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);
        vm.prank(depositor);
        manager.deposit{value: deposit}();

        revokeElection(groupAddresses[0]);
    }

    /// @dev The `deposit2` of the nested ratio blocks.
    function depositSecondTime() private returns (address nextToTail) {
        vm.prank(depositor);
        manager.deposit{value: DEPOSIT2}();
        (, nextToTail) = mockDefaultStrategy.getGroupsTail();
    }

    // =========================================================================
    //                              HELPERS
    // =========================================================================

    /// @dev The `should schedule the overflow to default strategy` assertion, which is the
    ///      same for all three CELO / stCELO ratios.
    function assertOverflowScheduled() private view {
        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertMembers(groups, arr(groupAddresses[0], groupAddresses[1]));
        assertMembers(
            votes, arr(firstGroupCapacity, SPECIFIC_OVERFLOW_DEPOSIT - firstGroupCapacity)
        );
    }
}
