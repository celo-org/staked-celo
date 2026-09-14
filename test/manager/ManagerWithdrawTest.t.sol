// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./ManagerTestBase.sol";

/**
 * @title ManagerWithdrawTest
 * @notice Ports `#withdraw()` of test-ts/manager.test.ts.
 */
contract ManagerWithdrawTest is ManagerTestBase {
    /// @dev `specificGroupStrategyWithdrawal` of the specific-group blocks.
    uint256 private constant SPECIFIC_WITHDRAWAL = 100;

    /// @dev `depositAmount` of the `when groups are close to their voting limit` block.
    /// @dev Deviation: the original deposited a flat 50 CELO, which on the ganache devchain
    ///      left an overflow of 9.833333333333333334 stCELO. That amount happened to be
    ///      divisible by the three default groups without a remainder, and so did its halves
    ///      and doubles, which the withdrawal distribution of DefaultStrategy relies on (it
    ///      reverts with NotAbleToDistributeVotes when rounding leaves a wei behind). The
    ///      anvil devchain leaves exactly 40 CELO of capacity, so the deposit is expressed as
    ///      "9 CELO over the first group's capacity" to keep the same property.
    uint256 private overflowDeposit;

    /// @dev `depositOverCapacity` / `deposit2` of the unhealthy overflow block.
    uint256 private constant DEPOSIT_OVER_CAPACITY = 10 ether;
    uint256 private constant DEPOSIT2 = 5 ether;

    address private originalHead;
    address private originalDefaultHead;
    address private previousOfHead;
    uint256 private originalOverflow;

    // =========================================================================
    //                             TOP LEVEL
    // =========================================================================

    function test_withdraw_RevertsWhenThereAreNoActiveOrDeactivatedGroups() public {
        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(DefaultStrategy.NoActiveGroups.selector));
        manager.withdraw(100);
    }

    // =========================================================================
    //                       when groups are activated
    // =========================================================================

    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawnFromHead_ShouldChangeCurrentHead()
        public
    {
        setUpGroupsActivated();
        withdrawAs(depositor2, 77);

        (address currentHead, ) = mockDefaultStrategy.getGroupsHead();
        assertNotEq(currentHead, originalHead);
    }

    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawnFromHead_ShouldUpdateCurrentTail()
        public
    {
        setUpGroupsActivated();
        withdrawAs(depositor2, 77);

        (address currentTail, ) = mockDefaultStrategy.getGroupsTail();
        assertEq(currentTail, originalHead);
    }

    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawnFromHead_ShouldUpdateTotalStCeloInDefaultStrategy()
        public
    {
        setUpGroupsActivated();
        withdrawAs(depositor2, 77);

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 223);
    }

    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawnFromHead_WhenWithdrawnAgain_ShouldChangeCurrentHead()
        public
    {
        setUpGroupsActivated();
        withdrawAs(depositor2, 77);

        (address headAfterWithdrawal1, ) = mockDefaultStrategy.getGroupsHead();
        withdrawAs(depositor2, 77);

        (address currentHead, ) = mockDefaultStrategy.getGroupsHead();
        assertNotEq(currentHead, headAfterWithdrawal1);
    }

    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawnFromHead_WhenWithdrawnAgain_ShouldUpdateCurrentTail()
        public
    {
        setUpGroupsActivated();
        withdrawAs(depositor2, 77);

        (address tailAfterWithdrawal1, ) = mockDefaultStrategy.getGroupsTail();
        withdrawAs(depositor2, 77);

        (address currentTail, ) = mockDefaultStrategy.getGroupsTail();
        assertEq(currentTail, tailAfterWithdrawal1);
    }

    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawnFromHead_WhenWithdrawnAgain_ShouldUpdateTotalStCeloInDefaultStrategy()
        public
    {
        setUpGroupsActivated();
        withdrawAs(depositor2, 77);
        withdrawAs(depositor2, 77);

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 146);
    }

    /// @dev When withdrawing 77 stCELO with a 1:1 ratio the event carries stCelo == celo.
    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawnFromHead_EmitsCeloWithdrawnEvent()
        public
    {
        setUpGroupsActivated();
        withdrawAs(depositor2, 77);

        vm.prank(depositor2);
        _expectEmitFrom(address(manager));
        emit CeloWithdrawn(depositor2, 50, 50);
        manager.withdraw(50);
    }

    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawingFromMultipleGroups_ShouldScheduleTransferFrom2Groups()
        public
    {
        setUpGroupsActivated();
        (address head, address previousHead) = headAndPrevious();

        withdrawAs(depositor2, 150);

        (address[] memory groups, uint256[] memory votes) = lastScheduledWithdrawals();
        assertMembers(groups, arr(head, previousHead));
        assertMembers(votes, arr(uint256(100), uint256(50)));
    }

    function test_withdraw_WhenGroupsAreActivated_WhenWithdrawingFromMultipleGroups_ShouldScheduleTransferFrom3Groups()
        public
    {
        setUpGroupsActivated();

        withdrawAs(depositor2, 300);

        (address[] memory groups, uint256[] memory votes) = lastScheduledWithdrawals();
        assertMembers(groups, groupSlice(3));
        assertMembers(votes, arr(uint256(100), uint256(100), uint256(100)));
    }

    // =========================================================================
    //                            stCELO burning
    // =========================================================================

    function test_withdraw_StCeloBurning_WhenThereAreEqualAmountOfCeloAndStCeloInTheSystem_CalculatesCelo11WithStCelo()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(200);
        mockStakedCelo.mint(someone, 100);

        withdrawAs(depositor, 100);

        assertEq(scheduledWithdrawalTotal(), 100);
    }

    function test_withdraw_StCeloBurning_WhenThereAreEqualAmountOfCeloAndStCeloInTheSystem_BurnsTheStCelo()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(200);
        mockStakedCelo.mint(someone, 100);

        withdrawAs(depositor, 100);

        assertEq(mockStakedCelo.balanceOf(depositor), 0);
    }

    function test_withdraw_StCeloBurning_WhenThereAreEqualAmountOfCeloAndStCeloInTheSystem_CalculatesCelo11WithStCeloForADifferentAmount()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(200);
        mockStakedCelo.mint(someone, 100);

        withdrawAs(depositor, 10);

        assertEq(scheduledWithdrawalTotal(), 10);
    }

    function test_withdraw_StCeloBurning_WhenThereAreEqualAmountOfCeloAndStCeloInTheSystem_BurnsTheStCeloForADifferentAmount()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(200);
        mockStakedCelo.mint(someone, 100);

        withdrawAs(depositor, 10);

        assertEq(mockStakedCelo.balanceOf(depositor), 90);
    }

    function test_withdraw_StCeloBurning_WhenThereIsMoreCeloThanStCeloInTheSystem_CalculatesMoreStCeloThanTheInputCelo()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(200);

        withdrawAs(depositor, 100);

        assertEq(scheduledWithdrawalTotal(), 200);
    }

    function test_withdraw_StCeloBurning_WhenThereIsMoreCeloThanStCeloInTheSystem_BurnsTheStCelo()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(200);

        withdrawAs(depositor, 100);

        assertEq(mockStakedCelo.balanceOf(depositor), 0);
    }

    function test_withdraw_StCeloBurning_WhenThereIsMoreCeloThanStCeloInTheSystem_CalculatesMoreStCeloThanTheInputCeloForADifferentAmount()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(200);

        withdrawAs(depositor, 10);

        assertEq(scheduledWithdrawalTotal(), 20);
    }

    function test_withdraw_StCeloBurning_WhenThereIsMoreCeloThanStCeloInTheSystem_BurnsTheStCelo2()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(200);

        withdrawAs(depositor, 10);

        assertEq(mockStakedCelo.balanceOf(depositor), 90);
    }

    function test_withdraw_StCeloBurning_WhenThereIsLessCeloThanStCeloInTheSystem_CalculatesLessStCeloThanTheInputCelo()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(100);
        mockStakedCelo.mint(someone, 100);

        withdrawAs(depositor, 100);

        assertEq(scheduledWithdrawalTotal(), 50);
    }

    function test_withdraw_StCeloBurning_WhenThereIsLessCeloThanStCeloInTheSystem_BurnsTheStCelo()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(100);
        mockStakedCelo.mint(someone, 100);

        withdrawAs(depositor, 100);

        assertEq(mockStakedCelo.balanceOf(depositor), 0);
    }

    function test_withdraw_StCeloBurning_WhenThereIsLessCeloThanStCeloInTheSystem_CalculatesLessStCeloThanTheInputCeloForADifferentAmount()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(100);
        mockStakedCelo.mint(someone, 100);

        withdrawAs(depositor, 10);

        assertEq(scheduledWithdrawalTotal(), 5);
    }

    /// @dev Deviation: the original names this case `burns the stCELO` as well, which would
    ///      collide with the previous function; the suffix disambiguates it.
    function test_withdraw_StCeloBurning_WhenThereIsLessCeloThanStCeloInTheSystem_BurnsTheStCelo2()
        public
    {
        setUpBurning();
        mockAccount.setTotalCelo(100);
        mockStakedCelo.mint(someone, 100);

        withdrawAs(depositor, 10);

        assertEq(mockStakedCelo.balanceOf(depositor), 90);
    }

    // =========================================================================
    //        When voted for specific validator group - no active groups
    // =========================================================================

    function test_withdraw_WhenVotedForSpecificValidatorGroupNoActiveGroups_ShouldWithdrawLessThanOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpSpecificNoActiveGroups();
        withdrawAs(depositor, 60);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(groups, arr(groupAddresses[0]));
        assertEq(withdrawals, arr(uint256(60)));
    }

    function test_withdraw_WhenVotedForSpecificValidatorGroupNoActiveGroups_ShouldWithdrawSameAmountAsOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpSpecificNoActiveGroups();
        withdrawAs(depositor, 100);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(groups, arr(groupAddresses[0]));
        assertEq(withdrawals, arr(uint256(100)));
    }

    function test_withdraw_WhenVotedForSpecificValidatorGroupNoActiveGroups_ShouldRevertWhenWithdrawMoreAmountThanOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpSpecificNoActiveGroups();

        vm.prank(depositor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.CantWithdrawAccordingToStrategy.selector,
                groupAddresses[0]
            )
        );
        manager.withdraw(110);
    }

    // =========================================================================
    //   When there are other active groups - voted is different from active
    // =========================================================================

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsDifferentFromActive_AddedGroupToVotedStrategies()
        public
    {
        setUpVotedDifferentFromActive();

        assertMembers(getDefaultGroups(defaultStrategy()), arr(groupAddresses[0], groupAddresses[1]));
        assertEq(getSpecificGroups(specificGroupStrategy), arr(groupAddresses[2]));
    }

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsDifferentFromActive_ShouldWithdrawLessThanOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpVotedDifferentFromActive();
        withdrawAs(depositor, 60);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(groups, arr(groupAddresses[2]));
        assertEq(withdrawals, arr(uint256(60)));
        assertEq(getSpecificGroups(specificGroupStrategy), arr(groupAddresses[2]));
    }

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsDifferentFromActive_ShouldWithdrawSameAmountAsOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpVotedDifferentFromActive();
        withdrawAs(depositor, 100);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(arr(groupAddresses[2]), groups);
        assertEq(arr(uint256(100)), withdrawals);
        assertEq(arr(groupAddresses[2]), getSpecificGroups(specificGroupStrategy));
    }

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsDifferentFromActive_ShouldWithdrawSameAmountAsOriginallyDepositedFromActiveGroupsAfterStrategyIsBlocked()
        public
    {
        setUpVotedDifferentFromActive();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[2]);
        specificGroupStrategy.rebalanceWhenHealthChanged(groupAddresses[2]);

        (address groupHead, ) = mockDefaultStrategy.getGroupsHead();
        updateGroupCelo();
        withdrawAs(depositor, 100);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(groups, arr(groupHead));
        assertEq(withdrawals, arr(uint256(100)));
        assertEq(getSpecificGroups(specificGroupStrategy), arr(groupAddresses[2]));
    }

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsDifferentFromActive_ShouldRevertWhenWithdrawMoreAmountThanOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpVotedDifferentFromActive();

        vm.prank(depositor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.CantWithdrawAccordingToStrategy.selector,
                groupAddresses[2]
            )
        );
        manager.withdraw(110);
    }

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsDifferentFromActive_WhenStrategyBlocked_ShouldWithdrawCorrectlyAfterRebalance()
        public
    {
        setUpVotedDifferentFromActive();
        setUpStrategyBlocked();

        (address head, ) = mockDefaultStrategy.getGroupsHead();
        updateGroupCelo();
        withdrawAs(depositor, SPECIFIC_WITHDRAWAL);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(groups, arr(head));
        assertEq(withdrawals, arr(SPECIFIC_WITHDRAWAL));

        (uint256 stCelo, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[2]);
        assertEq(stCelo, 0);
        assertEq(overflow, 0);
        assertEq(unhealthy, 0);
    }

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsDifferentFromActive_WhenStrategyBlocked_ShouldWithdrawCorrectlyAfterRebalanceWhenWithdrawingLessThanDeposited()
        public
    {
        setUpVotedDifferentFromActive();
        setUpStrategyBlocked();

        uint256 toWithdraw = SPECIFIC_WITHDRAWAL - 10;
        (address head, ) = mockDefaultStrategy.getGroupsHead();
        updateGroupCelo();
        withdrawAs(depositor, toWithdraw);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(groups, arr(head));
        assertEq(withdrawals, arr(toWithdraw));

        (uint256 stCelo, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[2]);
        assertEq(stCelo, 10);
        assertEq(overflow, 0);
        assertEq(unhealthy, 10);
    }

    // =========================================================================
    //  When there are other active groups - voted is one of the active groups
    // =========================================================================

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsOneOfTheActiveGroups_ShouldWithdrawLessThanOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpVotedIsActiveGroup();
        withdrawAs(depositor, 60);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(groups, arr(groupAddresses[1]));
        assertEq(withdrawals, arr(uint256(60)));
    }

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsOneOfTheActiveGroups_ShouldWithdrawSameAmountAsOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpVotedIsActiveGroup();
        withdrawAs(depositor, 100);

        (address[] memory groups, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        assertEq(groups, arr(groupAddresses[1]));
        assertEq(withdrawals, arr(uint256(100)));
    }

    function test_withdraw_WhenThereAreOtherActiveGroupsBesidesSpecificValidatorGroupVotedIsOneOfTheActiveGroups_ShouldRevertWhenWithdrawMoreAmountThanOriginallyDepositedFromSpecificGroupStrategy()
        public
    {
        setUpVotedIsActiveGroup();

        vm.prank(depositor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.CantWithdrawAccordingToStrategy.selector,
                groupAddresses[1]
            )
        );
        manager.withdraw(110);
    }

    // =========================================================================
    //              when groups are close to their voting limit
    // =========================================================================

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOnlyFromOverflow_ShouldRemoveOverflowFromDefaultStrategy()
        public
    {
        setUpCloseToVotingLimit();
        uint256 toWithdraw = 5 ether;
        withdrawAs(depositor, toWithdraw);

        (uint256 stCeloInStrategy, uint256 overflowAmount, ) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        assertEq(stCeloInStrategy, overflowDeposit - toWithdraw);
        assertEq(overflowAmount, overflowDeposit - firstGroupCapacity - toWithdraw);
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOnlyFromOverflow_ShouldScheduleWithdrawFromDefaultStrategyOnly()
        public
    {
        setUpCloseToVotingLimit();
        uint256 toWithdraw = 5 ether;
        withdrawAs(depositor, toWithdraw);

        (address[] memory groups, uint256[] memory votes) = lastScheduledWithdrawals();
        assertMembers(groups, arr(previousOfHead, originalDefaultHead));
        assertMembers(votes, arr(originalOverflow / 3, toWithdraw - originalOverflow / 3));
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOnlyFromOverflow_ShouldAddOverflowToDefaultStrategyStCeloBalance()
        public
    {
        setUpCloseToVotingLimit();
        withdrawAs(depositor, 5 ether);

        (, uint256 overflow, ) = specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), overflow);
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_When11_ShouldRemoveOverflowFromDefaultStrategy()
        public
    {
        setUpCloseToVotingLimit();
        withdrawAs(depositor, 20 ether);

        (uint256 stCeloInStrategy, uint256 overflowAmount, ) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        assertEq(stCeloInStrategy, overflowDeposit - 20 ether);
        assertEq(overflowAmount, 0);
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_When11_ShouldScheduleWithdrawFromDefaultAndSpecificStrategy()
        public
    {
        setUpCloseToVotingLimit();
        uint256 toWithdraw = 20 ether;
        withdrawAs(depositor, toWithdraw);

        uint256 overflowBefore = overflowDeposit - firstGroupCapacity;
        (address[] memory groups, uint256[] memory votes) = lastScheduledWithdrawals();
        assertMembers(
            groups,
            arr(groupAddresses[0], groupAddresses[1], groupAddresses[2], groupAddresses[0])
        );
        assertMembers(
            votes,
            arr(
                overflowBefore / 3,
                overflowBefore / 3,
                overflowBefore / 3,
                toWithdraw - overflowBefore
            )
        );
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_When11_ShouldAddOverflowToDefaultStrategyStCeloBalance()
        public
    {
        setUpCloseToVotingLimit();
        withdrawAs(depositor, 20 ether);

        (, uint256 overflow, ) = specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), overflow);
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_WhenThereIsMoreCeloThanStCelo_ShouldRemoveOverflowFromDefaultStrategy()
        public
    {
        setUpCloseToVotingLimit();
        mockAccount.setTotalCelo(overflowDeposit * 2);
        updateGroupCelo();
        withdrawAs(depositor, 20 ether);

        (uint256 stCeloInStrategy, uint256 overflowAmount, ) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        assertEq(stCeloInStrategy, overflowDeposit - 20 ether);
        assertEq(overflowAmount, 0);
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_WhenThereIsMoreCeloThanStCelo_ShouldScheduleWithdrawFromDefaultAndSpecificStrategy()
        public
    {
        setUpCloseToVotingLimit();
        mockAccount.setTotalCelo(overflowDeposit * 2);
        updateGroupCelo();
        uint256 toWithdraw = 20 ether;
        withdrawAs(depositor, toWithdraw);

        uint256 overflowBefore = overflowDeposit - firstGroupCapacity;
        (address[] memory groups, uint256[] memory votes) = lastScheduledWithdrawals();
        assertMembers(
            groups,
            arr(groupAddresses[0], groupAddresses[1], groupAddresses[2], groupAddresses[0])
        );
        assertMembers(
            votes,
            arr(
                (overflowBefore / 3) * 2,
                (overflowBefore / 3) * 2,
                (overflowBefore / 3) * 2,
                (toWithdraw - overflowBefore) * 2
            )
        );
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_WhenThereIsMoreCeloThanStCelo_ShouldAddOverflowToDefaultStrategyStCeloBalance()
        public
    {
        setUpCloseToVotingLimit();
        mockAccount.setTotalCelo(overflowDeposit * 2);
        updateGroupCelo();
        withdrawAs(depositor, 20 ether);

        (, uint256 overflow, ) = specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), overflow);
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_WhenThereIsLessCeloThanStCelo_ShouldRemoveOverflowFromDefaultStrategy()
        public
    {
        setUpCloseToVotingLimit();
        mockAccount.setTotalCelo(overflowDeposit / 2);
        withdrawAs(depositor, 20 ether);

        (uint256 stCeloInStrategy, uint256 overflowAmount, ) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        assertEq(stCeloInStrategy, overflowDeposit - 20 ether);
        assertEq(overflowAmount, 0);
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_WhenThereIsLessCeloThanStCelo_ShouldScheduleWithdrawFromDefaultAndSpecificStrategy()
        public
    {
        setUpCloseToVotingLimit();
        mockAccount.setTotalCelo(overflowDeposit / 2);
        uint256 toWithdraw = 20 ether;
        withdrawAs(depositor, toWithdraw);

        uint256 overflowBefore = overflowDeposit - firstGroupCapacity;
        (address[] memory groups, uint256[] memory votes) = lastScheduledWithdrawals();
        assertMembers(
            groups,
            arr(groupAddresses[0], groupAddresses[1], groupAddresses[2], groupAddresses[0])
        );
        assertMembers(
            votes,
            arr(
                overflowBefore / 3 / 2,
                overflowBefore / 3 / 2,
                overflowBefore / 3 / 2,
                (toWithdraw - overflowBefore) / 2
            )
        );
    }

    function test_withdraw_WhenGroupsAreCloseToTheirVotingLimit_WhenWithdrawingAmountOverOverflow_WhenThereIsLessCeloThanStCelo_ShouldAddOverflowToDefaultStrategyStCeloBalance()
        public
    {
        setUpCloseToVotingLimit();
        mockAccount.setTotalCelo(overflowDeposit / 2);
        withdrawAs(depositor, 20 ether);

        (, uint256 overflow, ) = specificGroupStrategy.getStCeloInGroup(groupAddresses[0]);
        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), overflow);
    }

    // =========================================================================
    //   When withdrawing from originally healthy overflowing group that became
    //   unhealthy
    // =========================================================================

    function test_withdraw_WhenWithdrawingFromOriginallyHealthyOverflowingGroupThatBecameUnhealthy_WhenDepositingToUnhealthySpecificGroup_ShouldScheduleTransfersCorrectly()
        public
    {
        setUpUnhealthyOverflow();
        address nextToTail = depositToUnhealthyGroup();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(nextToTail));
        assertEq(votes, arr(DEPOSIT2));
    }

    function test_withdraw_WhenWithdrawingFromOriginallyHealthyOverflowingGroupThatBecameUnhealthy_WhenDepositingToUnhealthySpecificGroup_ShouldHaveStCeloInStrategy()
        public
    {
        uint256 deposit = setUpUnhealthyOverflow();
        depositToUnhealthyGroup();

        (uint256 total, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        assertEq(total, DEPOSIT2 + deposit);
        assertEq(overflow, DEPOSIT_OVER_CAPACITY);
        // there is only deposit2 since rebalanceWhenHealthChanged was not called
        assertEq(unhealthy, DEPOSIT2);
    }

    function test_withdraw_WhenWithdrawingFromOriginallyHealthyOverflowingGroupThatBecameUnhealthy_WhenDepositingToUnhealthySpecificGroup_WhenWithdrawingFromUnhealthyOverflowedGroup_When11_ShouldHaveStCeloInStrategy()
        public
    {
        uint256 deposit = setUpUnhealthyOverflow();
        depositToUnhealthyGroup();

        updateGroupCelo();
        withdrawAs(depositor, 14 ether);

        (uint256 total, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        assertEq(total, DEPOSIT2 + deposit - 14 ether);
        assertEq(overflow, 0);
        assertEq(unhealthy, 1 ether);
    }

    function test_withdraw_WhenWithdrawingFromOriginallyHealthyOverflowingGroupThatBecameUnhealthy_WhenDepositingToUnhealthySpecificGroup_WhenWithdrawingFromUnhealthyOverflowedGroup_When11_ShouldScheduleWithdrawalFromDefaultStrategy()
        public
    {
        setUpUnhealthyOverflow();
        depositToUnhealthyGroup();

        updateGroupCelo();
        (address head, address perviousToHead) = mockDefaultStrategy.getGroupsHead();
        withdrawAs(depositor, 14 ether);

        (address[] memory groups, uint256[] memory votes) = lastScheduledWithdrawals();
        assertMembers(groups, arr(head, perviousToHead));
        assertEq(votes[0] + votes[1], 14 ether);
    }

    function test_withdraw_WhenWithdrawingFromOriginallyHealthyOverflowingGroupThatBecameUnhealthy_WhenDepositingToUnhealthySpecificGroup_WhenWithdrawingFromUnhealthyOverflowedGroup_WhenLessCeloThanStCelo_ShouldHaveStCeloInStrategy()
        public
    {
        uint256 deposit = setUpUnhealthyOverflow();
        depositToUnhealthyGroup();

        mockAccount.setTotalCelo((deposit + DEPOSIT2) / 2);
        updateGroupCelo();
        updateGroupCelo();
        withdrawAs(depositor, 14 ether);

        (uint256 total, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        assertEq(total, DEPOSIT2 + deposit - 14 ether);
        assertEq(overflow, 0);
        assertEq(unhealthy, 1 ether);
    }

    function test_withdraw_WhenWithdrawingFromOriginallyHealthyOverflowingGroupThatBecameUnhealthy_WhenDepositingToUnhealthySpecificGroup_WhenWithdrawingFromUnhealthyOverflowedGroup_WhenLessCeloThanStCelo_ShouldScheduleWithdrawalFromDefaultStrategy()
        public
    {
        uint256 deposit = setUpUnhealthyOverflow();
        depositToUnhealthyGroup();

        mockAccount.setTotalCelo((deposit + DEPOSIT2) / 2);
        updateGroupCelo();
        updateGroupCelo();
        (address head, address perviousToHead) = mockDefaultStrategy.getGroupsHead();
        withdrawAs(depositor, 14 ether);

        (address[] memory groups, uint256[] memory votes) = lastScheduledWithdrawals();
        assertMembers(groups, arr(head, perviousToHead));
        assertEq(votes[0] + votes[1], 14 ether / 2);
    }

    // =========================================================================
    //                          BLOCK FIXTURES
    // =========================================================================

    /// @dev `beforeEach` of `#withdraw() > when groups are activated`.
    function setUpGroupsActivated() private {
        address nextGroup = ADDRESS_ZERO;
        for (uint256 i = 0; i < 3; i++) {
            (address tail, ) = mockDefaultStrategy.getGroupsTail();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], nextGroup, tail);
            nextGroup = groupAddresses[i];
            mockAccount.setCeloForGroup(groupAddresses[i], 100);
            vm.prank(depositor2);
            manager.deposit{value: 100}();
        }

        (originalHead, ) = mockDefaultStrategy.getGroupsHead();
    }

    /// @dev `beforeEach` of `#withdraw() > stCELO burning`.
    function setUpBurning() private {
        for (uint256 i = 0; i < 3; i++) {
            (address head, ) = mockDefaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            mockAccount.setCeloForGroup(groupAddresses[i], 100);
            mockDefaultStrategy.addToStrategyTotalStCeloVotesPublic(groupAddresses[i], 100);
        }
        vm.prank(depositor);
        manager.deposit{value: 100}();
    }

    /// @dev `beforeEach` of `When voted for specific validator group - no active groups`.
    function setUpSpecificNoActiveGroups() private {
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);
        vm.prank(depositor);
        manager.deposit{value: 100}();
        mockAccount.setCeloForGroup(groupAddresses[0], 100);
    }

    /// @dev `beforeEach` of `When there are other active groups besides specific validator
    ///      group - voted is different from active`.
    function setUpVotedDifferentFromActive() private {
        uint256[] memory withdrawals = arr(uint256(40), uint256(50));
        address nextGroup = ADDRESS_ZERO;
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
            nextGroup = groupAddresses[i];
            vm.prank(depositor2);
            manager.deposit{value: withdrawals[i]}();
            mockAccount.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        mockAccount.setCeloForGroup(groupAddresses[2], SPECIFIC_WITHDRAWAL);

        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[2]);
        vm.prank(depositor);
        manager.deposit{value: SPECIFIC_WITHDRAWAL}();
    }

    /// @dev `beforeEach` of the nested `When strategy blocked` block.
    function setUpStrategyBlocked() private {
        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[2]);
        specificGroupStrategy.rebalanceWhenHealthChanged(groupAddresses[2]);
    }

    /// @dev `beforeEach` of `... - voted is one of the active groups`.
    function setUpVotedIsActiveGroup() private {
        uint256[] memory withdrawals = arr(uint256(40), uint256(50));
        for (uint256 i = 0; i < 2; i++) {
            (address head, ) = mockDefaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            mockAccount.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        mockAccount.setCeloForGroup(groupAddresses[1], withdrawals[1] + SPECIFIC_WITHDRAWAL);

        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[1]);
        vm.prank(depositor);
        manager.deposit{value: SPECIFIC_WITHDRAWAL}();
    }

    /// @dev `beforeEach` of `#withdraw() > when groups are close to their voting limit`.
    function setUpCloseToVotingLimit() private {
        prepareOverflowAndReadCapacities(true);
        overflowDeposit = firstGroupCapacity + 9 ether;

        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);
        vm.prank(depositor);
        manager.deposit{value: overflowDeposit}();
        rebalanceDefaultGroups(defaultStrategy());
        (originalDefaultHead, ) = mockDefaultStrategy.getGroupsHead();
        (previousOfHead, ) = mockDefaultStrategy.getGroupPreviousAndNext(originalDefaultHead);
        updateGroupCelo();
        originalOverflow = specificGroupStrategy.totalStCeloOverflow();
    }

    /// @dev `beforeEach` of `When withdrawing from originally healthy overflowing group that
    ///      became unhealthy`.
    function setUpUnhealthyOverflow() private returns (uint256 deposit) {
        prepareOverflowAndReadCapacities(true);
        deposit = firstGroupCapacity + DEPOSIT_OVER_CAPACITY;

        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);
        vm.prank(depositor);
        manager.deposit{value: deposit}();

        revokeElection(groupAddresses[0]);
    }

    /// @dev `beforeEach` of the nested `When depositing to unhealthy specific group` block.
    function depositToUnhealthyGroup() private returns (address nextToTail) {
        vm.prank(depositor);
        manager.deposit{value: DEPOSIT2}();
        (, nextToTail) = mockDefaultStrategy.getGroupsTail();
    }

    // =========================================================================
    //                              HELPERS
    // =========================================================================

    function withdrawAs(address who, uint256 stCeloAmount) private {
        vm.prank(who);
        manager.withdraw(stCeloAmount);
    }

    function headAndPrevious() private view returns (address head, address previousHead) {
        (head, ) = mockDefaultStrategy.getGroupsHead();
        (previousHead, ) = mockDefaultStrategy.getGroupPreviousAndNext(head);
    }

    /// @dev Ports `sum(withdrawals)` of the stCELO burning block.
    function scheduledWithdrawalTotal() private view returns (uint256 total) {
        (, uint256[] memory withdrawals) = lastScheduledWithdrawals();
        for (uint256 i = 0; i < withdrawals.length; i++) {
            total += withdrawals[i];
        }
    }
}
