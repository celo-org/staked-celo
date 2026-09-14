// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./ManagerTestBase.sol";

/**
 * @title ManagerDepositTest
 * @notice Ports `#deposit()` of test-ts/manager.test.ts, except the blocks that drive groups
 *         to their voting limit (see ManagerDepositOverflowTest).
 */
contract ManagerDepositTest is ManagerTestBase {
    address private originalTail;

    // =========================================================================
    //                             TOP LEVEL
    // =========================================================================

    function test_deposit_RevertsWhenThereAreNoActiveGroups() public {
        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(DefaultStrategy.NoActiveGroups.selector));
        manager.deposit{value: 100}();
    }

    // =========================================================================
    //                       when having active groups
    // =========================================================================

    function test_deposit_WhenHavingActiveGroups_DistributesVotesToTail() public {
        setUpHavingActiveGroups();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(originalTail));
        assertEq(votes, arr(uint256(99)));
    }

    function test_deposit_WhenHavingActiveGroups_ShouldChangeTheTail() public {
        setUpHavingActiveGroups();

        (address newTail, ) = mockDefaultStrategy.getGroupsTail();
        assertNotEq(originalTail, newTail);
    }

    function test_deposit_WhenHavingActiveGroups_ShouldUpdateHead() public {
        setUpHavingActiveGroups();

        (address newHead, ) = mockDefaultStrategy.getGroupsHead();
        assertEq(newHead, originalTail);
    }

    function test_deposit_WhenHavingActiveGroups_WhenAnotherDepositIsMade_ShouldUpdateTailAccordingly()
        public
    {
        setUpHavingActiveGroups();
        (address tailAfterFirstDeposit, ) = mockDefaultStrategy.getGroupsTail();
        vm.prank(depositor);
        manager.deposit{value: 100}();

        (address newTail, ) = mockDefaultStrategy.getGroupsTail();
        assertNotEq(originalTail, newTail);
        assertNotEq(tailAfterFirstDeposit, newTail);
    }

    function test_deposit_WhenHavingActiveGroups_WhenAnotherDepositIsMade_ShouldUpdateHead()
        public
    {
        setUpHavingActiveGroups();
        (address tailAfterFirstDeposit, ) = mockDefaultStrategy.getGroupsTail();
        vm.prank(depositor);
        manager.deposit{value: 100}();

        (address newHead, ) = mockDefaultStrategy.getGroupsHead();
        assertEq(newHead, tailAfterFirstDeposit);
    }

    function test_deposit_WhenHavingActiveGroups_WhenTailGroupIsDeactivated_DistributesVotesToNewTail()
        public
    {
        setUpHavingActiveGroups();
        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(tail);

        (address currentTail, ) = mockDefaultStrategy.getGroupsTail();
        vm.prank(depositor);
        manager.deposit{value: 100}();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(currentTail));
        assertEq(votes, arr(uint256(100)));
    }

    // =========================================================================
    //                            stCELO minting
    // =========================================================================

    function test_deposit_StCeloMinting_WhenThereAreNoTokensInTheSystem_WhenItMintsCelo11WithStCelo_ShouldHaveCorrectStCeloBalance()
        public
    {
        activateGroups(3);
        mockAccount.setTotalCelo(0);
        depositAs(depositor, 100);

        assertEq(mockStakedCelo.balanceOf(depositor), 100);
    }

    function test_deposit_StCeloMinting_WhenThereAreNoTokensInTheSystem_WhenItMintsCelo11WithStCelo_ShouldHaveCorrectStCeloInDefaultStrategy()
        public
    {
        activateGroups(3);
        mockAccount.setTotalCelo(0);
        depositAs(depositor, 100);

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 100);
    }

    function test_deposit_StCeloMinting_WhenThereAreNoTokensInTheSystem_WhenItMintsCelo11WithStCelo_ShouldHaveCorrectVotesScheduled()
        public
    {
        activateGroups(3);
        mockAccount.setTotalCelo(0);
        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        depositAs(depositor, 100);

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertMembers(groups, arr(tail));
        assertMembers(votes, arr(uint256(100)));
    }

    function test_deposit_StCeloMinting_WhenThereAreNoTokensInTheSystem_CalculatesCelo11WithStCeloForADifferentAmount()
        public
    {
        activateGroups(3);
        mockAccount.setTotalCelo(0);
        depositAs(depositor, 10);

        assertEq(mockStakedCelo.balanceOf(depositor), 10);
    }

    function test_deposit_StCeloMinting_WhenThereAreNoTokensInTheSystem_EmitsCeloDepositedEvent()
        public
    {
        activateGroups(3);
        mockAccount.setTotalCelo(0);

        vm.prank(depositor);
        _expectEmitFrom(address(manager));
        emit CeloDeposited(depositor, 100, 100);
        manager.deposit{value: 100}();
    }

    function test_deposit_StCeloMinting_WhenThereAreEqualAmountOfCeloAndStCeloInTheSystem_WhenItMintsCelo11WithStCelo_ShouldHaveCorrectStCeloBalance()
        public
    {
        activateGroups(3);
        setUpRatio(100, 100);
        depositAs(depositor, 100);

        assertEq(mockStakedCelo.balanceOf(depositor), 100);
    }

    function test_deposit_StCeloMinting_WhenThereAreEqualAmountOfCeloAndStCeloInTheSystem_WhenItMintsCelo11WithStCelo_ShouldHaveCorrectStCeloInDefaultStrategy()
        public
    {
        activateGroups(3);
        setUpRatio(100, 100);
        depositAs(depositor, 100);

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 100);
    }

    function test_deposit_StCeloMinting_WhenThereAreEqualAmountOfCeloAndStCeloInTheSystem_WhenItMintsCelo11WithStCelo_ShouldHaveCorrectVotesScheduled()
        public
    {
        activateGroups(3);
        setUpRatio(100, 100);
        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        depositAs(depositor, 100);

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertMembers(groups, arr(tail));
        assertMembers(votes, arr(uint256(100)));
    }

    function test_deposit_StCeloMinting_WhenThereAreEqualAmountOfCeloAndStCeloInTheSystem_CalculatesCelo11WithStCeloForADifferentAmount()
        public
    {
        activateGroups(3);
        setUpRatio(100, 100);
        depositAs(depositor, 10);

        assertEq(mockStakedCelo.balanceOf(depositor), 10);
    }

    function test_deposit_StCeloMinting_WhenThereIsMoreCeloThanStCeloInTheSystem_WhenItCalculatesLessStCeloThanTheInputCelo_ShouldHaveCorrectStCeloBalance()
        public
    {
        activateGroups(3);
        setUpRatio(200, 100);
        depositAs(depositor, 100);

        assertEq(mockStakedCelo.balanceOf(depositor), 50);
    }

    function test_deposit_StCeloMinting_WhenThereIsMoreCeloThanStCeloInTheSystem_WhenItCalculatesLessStCeloThanTheInputCelo_ShouldHaveCorrectStCeloInDefaultStrategy()
        public
    {
        activateGroups(3);
        setUpRatio(200, 100);
        depositAs(depositor, 100);

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 50);
    }

    function test_deposit_StCeloMinting_WhenThereIsMoreCeloThanStCeloInTheSystem_WhenItCalculatesLessStCeloThanTheInputCelo_ShouldHaveCorrectVotesScheduled()
        public
    {
        activateGroups(3);
        setUpRatio(200, 100);
        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        depositAs(depositor, 100);

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertMembers(groups, arr(tail));
        assertMembers(votes, arr(uint256(100)));
    }

    function test_deposit_StCeloMinting_WhenThereIsMoreCeloThanStCeloInTheSystem_CalculatesLessStCeloThanTheInputCeloForADifferentAmount()
        public
    {
        activateGroups(3);
        setUpRatio(200, 100);
        depositAs(depositor, 10);

        assertEq(mockStakedCelo.balanceOf(depositor), 5);
    }

    function test_deposit_StCeloMinting_WhenThereIsLessCeloThanStCeloInTheSystem_WhenItCalculatesMoreStCeloThanTheInputCelo_ShouldHaveCorrectStCeloBalance()
        public
    {
        activateGroups(3);
        setUpRatio(100, 200);
        depositAs(depositor, 100);

        assertEq(mockStakedCelo.balanceOf(depositor), 200);
    }

    function test_deposit_StCeloMinting_WhenThereIsLessCeloThanStCeloInTheSystem_WhenItCalculatesMoreStCeloThanTheInputCelo_ShouldHaveCorrectStCeloInDefaultStrategy()
        public
    {
        activateGroups(3);
        setUpRatio(100, 200);
        depositAs(depositor, 100);

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 200);
    }

    function test_deposit_StCeloMinting_WhenThereIsLessCeloThanStCeloInTheSystem_WhenItCalculatesMoreStCeloThanTheInputCelo_ShouldHaveCorrectVotesScheduled()
        public
    {
        activateGroups(3);
        setUpRatio(100, 200);
        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        depositAs(depositor, 100);

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertMembers(groups, arr(tail));
        assertMembers(votes, arr(uint256(100)));
    }

    function test_deposit_StCeloMinting_WhenThereIsLessCeloThanStCeloInTheSystem_CalculatesMoreStCeloThanTheInputCeloForADifferentAmount()
        public
    {
        activateGroups(3);
        setUpRatio(100, 200);
        depositAs(depositor, 10);

        assertEq(mockStakedCelo.balanceOf(depositor), 20);
    }

    // =========================================================================
    //                  When voted for specific strategy
    // =========================================================================

    function test_deposit_WhenVotedForSpecificStrategy_ShouldAddGroupToVotedStrategies() public {
        setUpVotedForSpecificStrategy();

        assertEq(getDefaultGroups(defaultStrategy()).length, 0);
        address[] memory specificGroups = getSpecificGroups(specificGroupStrategy);
        assertEq(specificGroups.length, 1);
        assertEq(specificGroups[0], groupAddresses[0]);
    }

    function test_deposit_WhenVotedForSpecificStrategy_ShouldScheduleVotesForSpecificGroupStrategy()
        public
    {
        setUpVotedForSpecificStrategy();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, groupSlice(1));
        assertEq(votes, arr(uint256(100)));
    }

    function test_deposit_WhenVotedForSpecificStrategy_ShouldMint11StCelo() public {
        setUpVotedForSpecificStrategy();

        assertEq(mockStakedCelo.balanceOf(depositor), 100);
    }

    // =========================================================================
    //   When voted for originally valid validator group that is no longer valid
    // =========================================================================

    function test_deposit_WhenVotedForOriginallyValidValidatorGroupThatIsNoLongerValid_ShouldAddGroupToVotedStrategies()
        public
    {
        setUpNoLongerValidGroup();

        assertMembers(getDefaultGroups(defaultStrategy()), groupSlice(3));
        assertEq(getSpecificGroups(specificGroupStrategy), arr(groupAddresses[4]));
    }

    function test_deposit_WhenVotedForOriginallyValidValidatorGroupThatIsNoLongerValid_ShouldScheduleVotesForDefaultGroups()
        public
    {
        setUpNoLongerValidGroup();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(originalTail));
        assertEq(votes, arr(uint256(100)));
    }

    function test_deposit_WhenVotedForOriginallyValidValidatorGroupThatIsNoLongerValid_ShouldSetCorrectStCeloAndUnhealthyStCeloInGroup()
        public
    {
        setUpNoLongerValidGroup();

        (uint256 total, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[4]);
        assertEq(total, 100);
        assertEq(overflow, 0);
        assertEq(unhealthy, 100);
    }

    function test_deposit_WhenVotedForOriginallyValidValidatorGroupThatIsNoLongerValid_ShouldNotScheduleTransfersToDefaultStrategyWhenNoBalanceForSpecificStrategy()
        public
    {
        setUpNoLongerValidGroup();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[4]);

        assertNoTransferScheduled();
    }

    function test_deposit_WhenVotedForOriginallyValidValidatorGroupThatIsNoLongerValid_ShouldMint11StCelo()
        public
    {
        setUpNoLongerValidGroup();

        assertEq(mockStakedCelo.balanceOf(depositor), 100);
    }

    // =========================================================================
    //                  When voted for deactivated group
    // =========================================================================

    function test_deposit_WhenVotedForDeactivatedGroup_BlockStrategyGroupOtherThanActive_ShouldScheduleVotesForDefaultStrategy()
        public
    {
        setUpBlockedStrategy(2, groupAddresses[2]);

        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        manager.deposit{value: 1000}();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertMembers(groups, arr(tail));
        assertMembers(votes, arr(uint256(1000)));
    }

    function test_deposit_WhenVotedForDeactivatedGroup_BlockStrategyGroupOneOfActive_ShouldScheduleVotesForDefaultStrategy()
        public
    {
        setUpBlockedStrategy(3, groupAddresses[0]);

        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        manager.deposit{value: 1000}();

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertMembers(groups, arr(tail));
        assertMembers(votes, arr(uint256(1000)));
    }

    // =========================================================================
    //               When we have 2 active validator groups
    // =========================================================================

    function test_deposit_WhenWeHave2ActiveValidatorGroups_WhenVotedForSpecificValidatorGroupWhichIsNotInActiveGroups_ShouldAddGroupToVotedStrategies()
        public
    {
        activateGroupsWithCelo(2, 100);
        setUpSpecificDeposit(groupAddresses[2]);

        assertEq(getDefaultGroups(defaultStrategy()), arr(groupAddresses[0], groupAddresses[1]));
        assertEq(getSpecificGroups(specificGroupStrategy), arr(groupAddresses[2]));
    }

    function test_deposit_WhenWeHave2ActiveValidatorGroups_WhenVotedForSpecificValidatorGroupWhichIsNotInActiveGroups_ShouldScheduleVotesForSpecificGroupStrategy()
        public
    {
        activateGroupsWithCelo(2, 100);
        setUpSpecificDeposit(groupAddresses[2]);

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(groupAddresses[2]));
        assertEq(votes, arr(uint256(100)));
    }

    function test_deposit_WhenWeHave2ActiveValidatorGroups_WhenVotedForSpecificValidatorGroupWhichIsNotInActiveGroups_ShouldMint11StCelo()
        public
    {
        activateGroupsWithCelo(2, 100);
        setUpSpecificDeposit(groupAddresses[2]);

        assertEq(mockStakedCelo.balanceOf(depositor), 100);
    }

    function test_deposit_WhenWeHave2ActiveValidatorGroups_WhenVotedForSpecificValidatorGroupWhichIsInActiveGroups_ShouldAddGroupToVotedStrategies()
        public
    {
        activateGroupsWithCelo(2, 100);
        setUpSpecificDeposit(groupAddresses[0]);

        assertEq(getDefaultGroups(defaultStrategy()), arr(groupAddresses[0], groupAddresses[1]));
        assertEq(getSpecificGroups(specificGroupStrategy), arr(groupAddresses[0]));
    }

    function test_deposit_WhenWeHave2ActiveValidatorGroups_WhenVotedForSpecificValidatorGroupWhichIsInActiveGroups_ShouldScheduleVotesForSpecificGroupStrategy()
        public
    {
        activateGroupsWithCelo(2, 100);
        setUpSpecificDeposit(groupAddresses[0]);

        (address[] memory groups, uint256[] memory votes) = lastScheduledVotes();
        assertEq(groups, arr(groupAddresses[0]));
        assertEq(votes, arr(uint256(100)));
    }

    function test_deposit_WhenWeHave2ActiveValidatorGroups_WhenVotedForSpecificValidatorGroupWhichIsInActiveGroups_ShouldMint11StCelo()
        public
    {
        activateGroupsWithCelo(2, 100);
        setUpSpecificDeposit(groupAddresses[0]);

        assertEq(mockStakedCelo.balanceOf(depositor), 100);
    }

    // =========================================================================
    //                          BLOCK FIXTURES
    // =========================================================================

    /// @dev `beforeEach` of `#deposit() > when having active groups`.
    function setUpHavingActiveGroups() private {
        activateGroups(3);
        (originalTail, ) = mockDefaultStrategy.getGroupsTail();
        depositAs(depositor, 99);
    }

    /// @dev `beforeEach` of the CELO / stCELO ratio blocks of `stCELO minting`.
    function setUpRatio(uint256 totalCelo, uint256 stCeloSupply) private {
        mockAccount.setTotalCelo(totalCelo);
        mockStakedCelo.mint(someone, stCeloSupply);
    }

    /// @dev `beforeEach` of `#deposit() > When voted for specific strategy`.
    function setUpVotedForSpecificStrategy() private {
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);
        depositAs(depositor, 100);
    }

    /// @dev `beforeEach` of `When voted for originally valid validator group that is no longer
    ///      valid`.
    function setUpNoLongerValidGroup() private {
        activateGroupsWithCelo(3, 100);

        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[4]);
        mockAccount.setCeloForGroup(groupAddresses[4], 100);
        slashGroup(groupAddresses[4]);
        mineToNextEpoch();
        electAndUpdate(groupAddresses[4]);

        (originalTail, ) = mockDefaultStrategy.getGroupsTail();
        depositAs(depositor, 100);
    }

    /// @dev `beforeEach` of the two `When voted for deactivated group` blocks. The original
    ///      deposited from the default signer, which is the test contract here.
    function setUpBlockedStrategy(uint256 activeCount, address strategyGroup) private {
        activateGroupsWithCelo(activeCount, 100);

        manager.changeStrategy(strategyGroup);
        manager.deposit{value: 1000}();
        mockAccount.setCeloForGroup(strategyGroup, 1000);
        vm.prank(owner);
        specificGroupStrategy.blockGroup(strategyGroup);
    }

    /// @dev `beforeEach` of the two `When we have 2 active validator groups` sub-blocks.
    function setUpSpecificDeposit(address strategyGroup) private {
        vm.prank(depositor);
        manager.changeStrategy(strategyGroup);
        depositAs(depositor, 100);
    }

    // =========================================================================
    //                              HELPERS
    // =========================================================================

    function depositAs(address who, uint256 value) private {
        vm.prank(who);
        manager.deposit{value: value}();
    }
}
