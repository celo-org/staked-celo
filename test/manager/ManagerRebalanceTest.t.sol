// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./ManagerTestBase.sol";

/**
 * @title ManagerRebalanceTest
 * @notice Ports `#getExpectedAndActualCeloForGroup()`, `#rebalance()`,
 *         `#scheduleTransferWithinStrategy()`, `#getReceivableVotesForGroup()` and
 *         `#rebalanceOverflow()` of test-ts/manager.test.ts.
 */
contract ManagerRebalanceTest is ManagerTestBase {
    uint256 private constant FROM_GROUP_DEPOSITED_VALUE = 100;
    uint256 private constant TO_GROUP_DEPOSITED_VALUE = 77;

    // =========================================================================
    //                  #getExpectedAndActualCeloForGroup()
    // =========================================================================

    function test_getExpectedAndActualCeloForGroup_WhenStrategyIsBlocked_ShouldReturnCorrectAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        manager.changeStrategy(groupAddresses[2]);
        manager.deposit{value: 100}();
        mockAccount.setVotesForGroup(groupAddresses[2], 50);
        mockAccount.setScheduledVotes(groupAddresses[2], 50);
        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[2]);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[2]
        );
        assertEq(expected, 0);
        assertEq(real, 100);
    }

    function test_getExpectedAndActualCeloForGroup_WhenValidatorGroupHasNegativeAmountOfCeloMoreScheduledToRevokeWithdrawThanOwning_ShouldReturnCorrectAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        manager.changeStrategy(groupAddresses[2]);
        manager.deposit{value: 100}();
        mockAccount.setVotesForGroup(groupAddresses[2], 50);
        mockAccount.setScheduledVotes(groupAddresses[2], 50);
        mockAccount.setScheduledRevokeForGroup(groupAddresses[2], 50);
        mockAccount.setScheduledWithdrawalsForGroup(groupAddresses[2], 51);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[2]
        );
        assertEq(expected, 1);
        assertEq(real, 0);
    }

    function test_getExpectedAndActualCeloForGroup_WhenSpecificStrategyIsOverflowingAndUnhealthy_ShouldReturnCorrectAmountForRealAndExpectedInSpecificStrategy()
        public
    {
        setUpOverflowingSpecificStrategy();

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, firstGroupCapacity);
        assertEq(real, firstGroupCapacity);
    }

    function test_getExpectedAndActualCeloForGroup_WhenSpecificStrategyIsOverflowingAndUnhealthy_ShouldReturnCorrectAmountForRealAndExpectedInDefaultStrategy()
        public
    {
        address originalTail = setUpOverflowingSpecificStrategy();

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(originalTail);
        assertEq(expected, DEPOSIT_OVER_CAPACITY);
        assertEq(real, DEPOSIT_OVER_CAPACITY);
    }

    function test_getExpectedAndActualCeloForGroup_WhenSpecificStrategyIsOverflowingAndUnhealthy_WhenGroupBecomesUnhealthy_ShouldReturnCorrectAmountForRealAndExpectedInSpecificStrategy()
        public
    {
        setUpOverflowingSpecificStrategy();
        setUpGroupBecomesUnhealthy();

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, 0);
        assertEq(real, 0);
    }

    function test_getExpectedAndActualCeloForGroup_WhenSpecificStrategyIsOverflowingAndUnhealthy_WhenGroupBecomesUnhealthy_ShouldReturnCorrectAmountForRealAndExpectedInDefaultStrategy()
        public
    {
        address originalTail = setUpOverflowingSpecificStrategy();
        address newTail = setUpGroupBecomesUnhealthy();

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(originalTail);
        assertEq(expected, DEPOSIT_OVER_CAPACITY);
        assertEq(real, DEPOSIT_OVER_CAPACITY);

        (uint256 expected2, uint256 real2) = manager.getExpectedAndActualCeloForGroup(newTail);
        assertEq(expected2, firstGroupCapacity);
        assertEq(real2, firstGroupCapacity);
    }

    function test_getExpectedAndActualCeloForGroup_WhenGroupIsDeactivated_ShouldReturnCorrectAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        manager.deposit{value: 100}();
        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(groupAddresses[0]);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, 0);
        assertEq(real, 50);
    }

    function test_getExpectedAndActualCeloForGroup_WhenGroupIsOnlyInSpecificGroupStrategy_ShouldReturnSameAmountForRealAndExpected()
        public
    {
        setUpOnlyInSpecificGroupStrategy();

        mockAccount.setVotesForGroup(groupAddresses[0], 50);
        mockAccount.setScheduledVotes(groupAddresses[0], 50);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, real);
    }

    function test_getExpectedAndActualCeloForGroup_WhenGroupIsOnlyInSpecificGroupStrategy_ShouldReturnDifferentAmountForRealAndExpected()
        public
    {
        setUpOnlyInSpecificGroupStrategy();

        mockAccount.setVotesForGroup(groupAddresses[0], 25);
        mockAccount.setScheduledVotes(groupAddresses[0], 25);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, 100);
        assertEq(real, 50);
    }

    function test_getExpectedAndActualCeloForGroup_WhenThereAreActiveGroups_WhenGroupIsOnlyInActive_ShouldReturnSameAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        setUpGroupOnlyInActive();

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, real);
    }

    function test_getExpectedAndActualCeloForGroup_WhenThereAreActiveGroups_WhenGroupIsOnlyInActive_ShouldReturnDifferentAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        setUpGroupOnlyInActive();

        mockAccount.setVotesForGroup(groupAddresses[0], 30);
        mockAccount.setScheduledVotes(groupAddresses[0], 30);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, 50);
        assertEq(real, 60);
    }

    function test_getExpectedAndActualCeloForGroup_WhenThereAreActiveGroups_WhenGroupIsInBothActiveAndSpecific_ShouldReturnSameAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        setUpGroupInBothActiveAndSpecific();

        mockAccount.setScheduledVotes(groupAddresses[0], 150);
        mockAccount.setVotesForGroup(groupAddresses[0], 0);
        mockAccount.setCeloForGroup(groupAddresses[0], 150);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, real);
    }

    function test_getExpectedAndActualCeloForGroup_WhenThereAreActiveGroups_WhenGroupIsInBothActiveAndSpecific_ShouldReturnDifferentAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        setUpGroupInBothActiveAndSpecific();

        mockAccount.setScheduledVotes(groupAddresses[0], 60);
        mockAccount.setVotesForGroup(groupAddresses[0], 0);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, 150);
        assertEq(real, 60);
    }

    function test_getExpectedAndActualCeloForGroup_WhenThereAreActiveGroups_WhenGroupIsInBothActiveAndSpecific_WhenHavingDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldReturnDifferentAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        setUpGroupInBothActiveAndSpecific();
        mockAccount.setTotalCelo(400);

        mockAccount.setScheduledVotes(groupAddresses[0], 50);
        mockAccount.setVotesForGroup(groupAddresses[0], 0);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, 300);
        assertEq(real, 50);
    }

    function test_getExpectedAndActualCeloForGroup_WhenThereAreActiveGroups_WhenGroupIsInBothActiveAndSpecific_WhenHavingDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldReturnDifferentAmountForRealAndExpected()
        public
    {
        activateGroupsWithSplitCelo(2, 50);
        setUpGroupInBothActiveAndSpecific();
        mockAccount.setTotalCelo(100);

        mockAccount.setScheduledVotes(groupAddresses[0], 50);
        mockAccount.setVotesForGroup(groupAddresses[0], 0);

        (uint256 expected, uint256 real) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
        );
        assertEq(expected, 75);
        assertEq(real, 50);
    }

    function test_getExpectedAndActualCeloForGroup_WhenGroupsAreCloseToTheirVotingLimit_WhenDepositingToSpecificStrategyThatIsNotUsedInActiveGroups_ShouldReturnExpectedWithoutOverflow()
        public
    {
        prepareOverflowAndReadCapacities(false);
        activateGroups(2);

        uint256 deposit = 250 ether;
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[2]);
        vm.prank(depositor);
        manager.deposit{value: deposit}();
        mockAccount.setScheduledVotes(groupAddresses[2], thirdGroupCapacity);

        (uint256 expected, uint256 actual) = manager.getExpectedAndActualCeloForGroup(
            groupAddresses[2]
        );
        assertEq(expected, thirdGroupCapacity);
        assertEq(actual, thirdGroupCapacity);
        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), deposit - thirdGroupCapacity);
    }

    // =========================================================================
    //                             #rebalance()
    // =========================================================================

    function test_rebalance_ShouldRevertWhenTryingToBalanceSomeAnd0x0Group() public {
        manager.changeStrategy(groupAddresses[0]);
        manager.deposit{value: FROM_GROUP_DEPOSITED_VALUE}();

        mockAccount.setScheduledVotes(groupAddresses[0], FROM_GROUP_DEPOSITED_VALUE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(Manager.RebalanceEnoughCelo.selector, ADDRESS_ZERO, 0, 0)
        );
        manager.rebalance(groupAddresses[0], ADDRESS_ZERO);
    }

    function test_rebalance_ShouldRevertWhenTryingToBalance0x0And0x0Group() public {
        vm.expectRevert(
            abi.encodeWithSelector(Manager.RebalanceNoExtraCelo.selector, ADDRESS_ZERO, 0, 0)
        );
        manager.rebalance(ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_rebalance_ShouldRevertWhenFromGroupHasLessCeloThanItShould() public {
        manager.changeStrategy(groupAddresses[0]);
        manager.deposit{value: FROM_GROUP_DEPOSITED_VALUE}();

        vm.prank(depositor2);
        manager.changeStrategy(groupAddresses[1]);
        vm.prank(depositor2);
        manager.deposit{value: TO_GROUP_DEPOSITED_VALUE}();

        mockAccount.setScheduledVotes(groupAddresses[0], FROM_GROUP_DEPOSITED_VALUE - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Manager.RebalanceNoExtraCelo.selector,
                groupAddresses[0],
                FROM_GROUP_DEPOSITED_VALUE - 1,
                FROM_GROUP_DEPOSITED_VALUE
            )
        );
        manager.rebalance(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalance_ShouldRevertWhenFromGroupHasSameCeloAsItShould() public {
        manager.changeStrategy(groupAddresses[0]);
        manager.deposit{value: FROM_GROUP_DEPOSITED_VALUE}();

        vm.prank(depositor2);
        manager.changeStrategy(groupAddresses[1]);
        vm.prank(depositor2);
        manager.deposit{value: TO_GROUP_DEPOSITED_VALUE}();

        mockAccount.setScheduledVotes(groupAddresses[0], FROM_GROUP_DEPOSITED_VALUE);
        vm.expectRevert(
            abi.encodeWithSelector(
                Manager.RebalanceNoExtraCelo.selector,
                groupAddresses[0],
                FROM_GROUP_DEPOSITED_VALUE,
                FROM_GROUP_DEPOSITED_VALUE
            )
        );
        manager.rebalance(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalance_WhenFromGroupHasValidProperties_ShouldRevertWhenToGroupHasMoreCeloThanItShould()
        public
    {
        setUpFromGroupValid();

        vm.prank(depositor2);
        manager.changeStrategy(groupAddresses[1]);
        vm.prank(depositor2);
        manager.deposit{value: TO_GROUP_DEPOSITED_VALUE}();
        mockAccount.setCeloForGroup(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE + 1);
        mockAccount.setScheduledVotes(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Manager.RebalanceEnoughCelo.selector,
                groupAddresses[1],
                TO_GROUP_DEPOSITED_VALUE + 1,
                TO_GROUP_DEPOSITED_VALUE
            )
        );
        manager.rebalance(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalance_WhenFromGroupHasValidProperties_ShouldRevertWhenToGroupHasSameCeloAsItShould()
        public
    {
        setUpFromGroupValid();

        vm.prank(depositor2);
        manager.changeStrategy(groupAddresses[1]);
        vm.prank(depositor2);
        manager.deposit{value: TO_GROUP_DEPOSITED_VALUE}();
        mockAccount.setCeloForGroup(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE);
        mockAccount.setScheduledVotes(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE);

        vm.expectRevert(
            abi.encodeWithSelector(
                Manager.RebalanceEnoughCelo.selector,
                groupAddresses[1],
                TO_GROUP_DEPOSITED_VALUE,
                TO_GROUP_DEPOSITED_VALUE
            )
        );
        manager.rebalance(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalance_WhenFromGroupHasValidProperties_WhenToGroupHasValidProperties_ShouldScheduleTransfer()
        public
    {
        setUpFromGroupValid();
        setUpToGroupValid();

        manager.rebalance(groupAddresses[0], groupAddresses[1]);

        assertTransferOfOne();
    }

    function test_rebalance_WhenFromGroupHasValidProperties_WhenToGroupHasValidProperties_ShouldScheduleTransferWhenGroupCeloBalanceIsNegative()
        public
    {
        setUpFromGroupValid();
        setUpToGroupValid();

        mockAccount.setCeloForGroup(groupAddresses[1], 0);
        mockAccount.setScheduledRevokeForGroup(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE + 10);

        manager.rebalance(groupAddresses[0], groupAddresses[1]);

        assertTransferOfOne();
    }

    function test_rebalance_WhenFromGroupHasValidProperties_WhenToGroupHasValidProperties_WhenHavingSameActiveGroupsAndSpecificStrategyGetBlocked_ShouldRevertWhenRebalanceToDeactivatedGroup()
        public
    {
        setUpFromGroupValid();
        setUpToGroupValid();
        setUpSameActiveGroupsBlocked();

        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(groupAddresses[1]);
        vm.expectRevert(
            abi.encodeWithSelector(Manager.InvalidToGroup.selector, groupAddresses[1])
        );
        manager.rebalance(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalance_WhenFromGroupHasValidProperties_WhenToGroupHasValidProperties_WhenHavingDifferentActiveGroups_ShouldScheduleTransferFromDisspecificStrategy()
        public
    {
        setUpFromGroupValid();
        setUpToGroupValid();
        setUpDifferentActiveGroups();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[0]);
        manager.rebalance(groupAddresses[0], groupAddresses[1]);

        assertTransferOfOne();
    }

    function test_rebalance_WhenFromGroupHasValidProperties_WhenToGroupHasValidProperties_WhenHavingDifferentActiveGroups_ShouldRevertWhenRebalanceToDisspecificStrategy()
        public
    {
        setUpFromGroupValid();
        setUpToGroupValid();
        setUpDifferentActiveGroups();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[1]);
        vm.expectRevert(
            abi.encodeWithSelector(Manager.InvalidToGroup.selector, groupAddresses[1])
        );
        manager.rebalance(groupAddresses[0], groupAddresses[1]);
    }

    // =========================================================================
    //                   #scheduleTransferWithinStrategy()
    // =========================================================================

    function test_scheduleTransferWithinStrategy_ShouldRevertWhenNotCalledByStrategy() public {
        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(Manager.CallerNotStrategy.selector, depositor));
        manager.scheduleTransferWithinStrategy(
            new address[](0),
            new address[](0),
            new uint256[](0),
            new uint256[](0)
        );
    }

    function test_scheduleTransferWithinStrategy_ShouldScheduleTransferWhenCalledByStrategy()
        public
    {
        address strategyAddress = address(manager.defaultStrategy());
        vm.prank(depositor);
        (bool sent, ) = strategyAddress.call{value: 10 ether}("");
        assertTrue(sent);

        address[] memory fromGroups = arr(groupAddresses[6], groupAddresses[7]);
        uint256[] memory fromVotes = arr(uint256(100), uint256(200));
        address[] memory toGroups = arr(groupAddresses[8], groupAddresses[9]);
        uint256[] memory toVotes = arr(uint256(300), uint256(400));

        vm.prank(strategyAddress);
        manager.scheduleTransferWithinStrategy(fromGroups, toGroups, fromVotes, toVotes);

        (
            address[] memory lastFromGroups,
            uint256[] memory lastFromVotes,
            address[] memory lastToGroups,
            uint256[] memory lastToVotes
        ) = mockAccount.getLastTransferValues();

        assertMembers(lastFromGroups, fromGroups);
        assertEq(lastFromVotes, fromVotes);

        assertMembers(lastToGroups, toGroups);
        assertEq(lastToVotes, toVotes);
    }

    // =========================================================================
    //                    #getReceivableVotesForGroup()
    // =========================================================================

    function test_getReceivableVotesForGroup_ShouldRevertWhenNotValidatorGroup() public {
        vm.expectRevert(bytes("Not validator group"));
        manager.getReceivableVotesForGroup(nonAccount);
    }

    function test_getReceivableVotesForGroup_WhenHavingValidatorGroupsCloseToVotingLimit_ShouldReturnCorrectAmountOfReceivableVotes()
        public
    {
        prepareOverflowAndReadCapacities(true);

        assertEq(manager.getReceivableVotesForGroup(groupAddresses[0]), firstGroupCapacity);
    }

    function test_getReceivableVotesForGroup_WhenHavingValidatorGroupsCloseToVotingLimit_WhenHavingSomeVotesScheduled_ShouldReturnCorrectAmount()
        public
    {
        prepareOverflowAndReadCapacities(true);

        uint256 scheduledVotes = 2 ether;
        mockAccount.setCeloForGroup(groupAddresses[0], scheduledVotes);

        assertEq(
            manager.getReceivableVotesForGroup(groupAddresses[0]),
            firstGroupCapacity - scheduledVotes
        );
    }

    // =========================================================================
    //                        #rebalanceOverflow()
    // =========================================================================

    function test_rebalanceOverflow_ShouldRevertWhenToGroupNotActive() public {
        vm.expectRevert(
            abi.encodeWithSelector(Manager.InvalidToGroup.selector, groupAddresses[1])
        );
        manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalanceOverflow_WhenActiveGroups_ShouldRevertWhenFromGroupNotOverflowing()
        public
    {
        prepareOverflowAndReadCapacities(true);

        vm.expectRevert(
            abi.encodeWithSelector(Manager.FromGroupNotOverflowing.selector, groupAddresses[0])
        );
        manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalanceOverflow_WhenActiveGroups_WhenScheduledVotesAreStillReceivable_ShouldRevertWhenFromGroupHasNoScheduledVotes()
        public
    {
        prepareOverflowAndReadCapacities(true);
        mockAccount.setCeloForGroup(groupAddresses[0], firstGroupCapacity);

        vm.expectRevert(
            abi.encodeWithSelector(Manager.FromGroupNotOverflowing.selector, groupAddresses[0])
        );
        manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalanceOverflow_WhenActiveGroups_WhenFromGroupOverflowing_WhenToGroupIsOverflowing_ShouldRevert()
        public
    {
        prepareOverflowAndReadCapacities(true);
        mockAccount.setCeloForGroup(groupAddresses[0], firstGroupCapacity * 2);

        mockAccount.setScheduledVotes(groupAddresses[0], firstGroupCapacity * 2);
        mockAccount.setCeloForGroup(groupAddresses[1], secondGroupCapacity * 2);

        vm.expectRevert(
            abi.encodeWithSelector(Manager.ToGroupOverflowing.selector, groupAddresses[1])
        );
        manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1]);
    }

    function test_rebalanceOverflow_WhenActiveGroups_WhenFromGroupOverflowing_WhenScheduledVotesThatAreStillReceivable_ShouldScheduleTransfer()
        public
    {
        prepareOverflowAndReadCapacities(true);
        mockAccount.setCeloForGroup(groupAddresses[0], firstGroupCapacity * 2);

        mockAccount.setScheduledVotes(groupAddresses[0], firstGroupCapacity * 2);
        mockAccount.setScheduledRevokeForGroup(groupAddresses[0], 1 ether);
        mockAccount.setScheduledWithdrawalsForGroup(groupAddresses[0], 1 ether);
        manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1]);

        (
            address[] memory fromGroups,
            uint256[] memory fromVotes,
            address[] memory toGroups,
            uint256[] memory toVotes
        ) = mockAccount.getLastTransferValues();

        assertMembers(fromGroups, arr(groupAddresses[0]));
        assertEq(fromVotes, arr(firstGroupCapacity - 2 ether));

        assertMembers(toGroups, arr(groupAddresses[1]));
        assertEq(toVotes, arr(firstGroupCapacity - 2 ether));
    }

    // =========================================================================
    //                          BLOCK FIXTURES
    // =========================================================================

    /// @dev `depositOverCapacity` of the overflowing specific strategy block.
    uint256 private constant DEPOSIT_OVER_CAPACITY = 10 ether;

    /// @dev `beforeEach` of `When specific strategy is overflowing and unhealthy`.
    function setUpOverflowingSpecificStrategy() private returns (address originalTail) {
        prepareOverflowAndReadCapacities(false);

        vm.startPrank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[1]);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[2]);
        vm.stopPrank();
        mockDefaultStrategy.activateGroup(groupAddresses[1], ADDRESS_ZERO, ADDRESS_ZERO);
        mockDefaultStrategy.activateGroup(groupAddresses[2], ADDRESS_ZERO, groupAddresses[1]);

        (originalTail, ) = mockDefaultStrategy.getGroupsTail();
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);
        vm.prank(depositor);
        manager.deposit{value: firstGroupCapacity + DEPOSIT_OVER_CAPACITY}();

        updateGroupCelo();
    }

    /// @dev `beforeEach` of `When group becomes unhealthy`.
    function setUpGroupBecomesUnhealthy() private returns (address newTail) {
        revokeElection(groupAddresses[0]);
        (newTail, ) = mockDefaultStrategy.getGroupsTail();
        specificGroupStrategy.rebalanceWhenHealthChanged(groupAddresses[0]);
        updateGroupCelo();
    }

    /// @dev `beforeEach` of `When group is only in specific group strategy`.
    function setUpOnlyInSpecificGroupStrategy() private {
        manager.changeStrategy(groupAddresses[0]);
        manager.deposit{value: 100}();
    }

    /// @dev `beforeEach` of `When there are active groups > When group is only in active`.
    function setUpGroupOnlyInActive() private {
        manager.deposit{value: 100}();
        rebalanceDefaultGroups(defaultStrategy());
    }

    /// @dev `beforeEach` of `When there are active groups > When group is in both active and
    ///      specific`.
    function setUpGroupInBothActiveAndSpecific() private {
        vm.prank(depositor);
        manager.deposit{value: 100}();
        vm.prank(depositor2);
        manager.changeStrategy(groupAddresses[0]);
        vm.prank(depositor2);
        manager.deposit{value: 100}();
        rebalanceDefaultGroups(defaultStrategy());
    }

    /// @dev `beforeEach` of `#rebalance() > When fromGroup has valid properties`.
    function setUpFromGroupValid() private {
        manager.changeStrategy(groupAddresses[0]);
        manager.deposit{value: FROM_GROUP_DEPOSITED_VALUE}();
        mockAccount.setCeloForGroup(groupAddresses[0], FROM_GROUP_DEPOSITED_VALUE + 1);
        mockAccount.setScheduledVotes(groupAddresses[0], FROM_GROUP_DEPOSITED_VALUE + 1);
        mockAccount.setVotesForGroup(groupAddresses[0], 0);
    }

    /// @dev `beforeEach` of `#rebalance() > ... > When toGroup has valid properties`.
    function setUpToGroupValid() private {
        vm.prank(depositor2);
        manager.changeStrategy(groupAddresses[1]);
        vm.prank(depositor2);
        manager.deposit{value: TO_GROUP_DEPOSITED_VALUE}();
        mockAccount.setCeloForGroup(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE - 1);
        mockAccount.setScheduledVotes(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE - 1);
        mockAccount.setVotesForGroup(groupAddresses[1], 0);
    }

    /// @dev `beforeEach` of `When having same active groups and specific strategy get blocked`.
    function setUpSameActiveGroupsBlocked() private {
        activateGroups(2);
        mockAccount.setCeloForGroup(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE);
        mockAccount.setScheduledVotes(groupAddresses[1], TO_GROUP_DEPOSITED_VALUE);
        mockAccount.setVotesForGroup(groupAddresses[1], 0);

        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[0]);
        specificGroupStrategy.rebalanceWhenHealthChanged(groupAddresses[0]);
        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[1]);
        specificGroupStrategy.rebalanceWhenHealthChanged(groupAddresses[1]);
    }

    /// @dev `beforeEach` of `When having different active groups`.
    function setUpDifferentActiveGroups() private {
        for (uint256 i = 2; i < 4; i++) {
            (address head, ) = mockDefaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
    }

    /// @dev The transfer of one CELO from group 0 to group 1 asserted by three `#rebalance()`
    ///      cases.
    function assertTransferOfOne() private view {
        (
            address[] memory fromGroups,
            uint256[] memory fromVotes,
            address[] memory toGroups,
            uint256[] memory toVotes
        ) = mockAccount.getLastTransferValues();

        assertEq(fromGroups, arr(groupAddresses[0]));
        assertEq(fromVotes, arr(uint256(1)));
        assertEq(toGroups, arr(groupAddresses[1]));
        assertEq(toVotes, arr(uint256(1)));
    }
}
