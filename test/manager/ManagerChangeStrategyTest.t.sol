// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./ManagerTestBase.sol";

/**
 * @title ManagerChangeStrategyTest
 * @notice Ports `#changeStrategy()` and `#forceChangeStrategy()` of test-ts/manager.test.ts.
 * @dev The original called `manager.changeStrategy(...)` / `manager.deposit(...)` without
 *      `.connect(...)` in these blocks, i.e. from the default Hardhat signer. The Foundry
 *      equivalent is the test contract itself, which is therefore the depositor of the
 *      `#changeStrategy()` blocks.
 */
contract ManagerChangeStrategyTest is ManagerTestBase {
    /// @dev `specificGroupStrategyDeposit` / `defaultGroupDeposit` of the nested blocks.
    uint256 private constant STRATEGY_DEPOSIT = 2 ether;

    address private specificGroupStrategyAddress;

    function setUp() public override {
        super.setUp();
        specificGroupStrategyAddress = groupAddresses[2];
        activateGroupsWithCeloList(arr(uint256(40), uint256(50)));
    }

    // =========================================================================
    //                          #changeStrategy()
    // =========================================================================

    function test_changeStrategy_ShouldRevertWhenNotValidGroup() public {
        address slashedGroup = groupAddresses[0];
        slashGroup(slashedGroup);
        mineToNextEpoch();
        electAndUpdate(slashedGroup);

        vm.expectRevert(abi.encodeWithSelector(Manager.GroupNotEligible.selector, slashedGroup));
        manager.changeStrategy(slashedGroup);
    }

    function test_changeStrategy_WhenChangingWithNoPreviousStCelo_ShouldAddGroupToVotedStrategies()
        public
    {
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);

        vm.prank(depositor);
        manager.deposit{value: 100}();
        assertEq(getSpecificGroups(specificGroupStrategy), arr(groupAddresses[0]));
    }

    function test_changeStrategy_WhenChangingWithNoPreviousStCelo_ShouldChangeAccountStrategy()
        public
    {
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);

        assertEq(manager.getAddressStrategy(depositor), groupAddresses[0]);
    }

    function test_changeStrategy_WhenDepositorChoseSpecificStrategy_ShouldScheduleNothingWhenTryingToChangeToSameSpecificStrategy()
        public
    {
        setUpChoseSpecificStrategy();

        manager.changeStrategy(specificGroupStrategyAddress);

        assertNoTransferScheduled();
    }

    function test_changeStrategy_WhenDepositorChoseSpecificStrategy_ShouldScheduleTransfersWhenChangingToDifferentSpecificStrategy()
        public
    {
        setUpChoseSpecificStrategy();

        manager.changeStrategy(ADDRESS_ZERO);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(
            mockDefaultStrategy.stCeloInGroup(groupAddresses[0]),
            mockDefaultStrategy.stCeloInGroup(groupAddresses[0])
        );
    }

    function test_changeStrategy_WhenDepositorChoseSpecificStrategy_ShouldScheduleTransfersWhenChangingToDefaultStrategy()
        public
    {
        setUpChoseSpecificStrategy();

        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        manager.changeStrategy(ADDRESS_ZERO);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[0]), 0);
        assertEq(tail, groupAddresses[1]);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[1]), STRATEGY_DEPOSIT);
    }

    function test_changeStrategy_WhenDepositorChoseSpecificStrategy_WhenChosenGroupIsUnhealthy_ShouldScheduleTransfersFromGroupSinceGroupWasNotRebalancedWhenChangingToDifferentSpecificStrategy()
        public
    {
        setUpChoseSpecificStrategy();
        setUpChosenGroupUnhealthy();

        address differentSpecificGroupStrategy = groupAddresses[0];
        manager.changeStrategy(differentSpecificGroupStrategy);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(
            specificGroupStrategy.stCeloInGroup(differentSpecificGroupStrategy),
            STRATEGY_DEPOSIT
        );
    }

    function test_changeStrategy_WhenDepositorChoseSpecificStrategy_WhenChosenGroupIsUnhealthy_WhenRebalanced_ShouldScheduleTransfersWhenChangingToDefaultStrategy()
        public
    {
        setUpChoseSpecificStrategy();
        setUpChosenGroupUnhealthy();
        setUpRebalanced();

        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        manager.changeStrategy(ADDRESS_ZERO);

        (uint256 stCeloInStrategy, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(specificGroupStrategyAddress);
        assertEq(stCeloInStrategy, 0);
        assertEq(overflow, 0);
        assertEq(unhealthy, 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(tail), STRATEGY_DEPOSIT);
    }

    function test_changeStrategy_WhenDepositorChoseSpecificStrategy_WhenChosenGroupIsUnhealthy_ShouldScheduleTransfersWhenChangingToDefaultStrategy()
        public
    {
        setUpChoseSpecificStrategy();
        setUpChosenGroupUnhealthy();

        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        manager.changeStrategy(ADDRESS_ZERO);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[0]), 0);
        assertEq(tail, groupAddresses[1]);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[1]), STRATEGY_DEPOSIT);
    }

    function test_changeStrategy_WhenDepositorChoseDefaultStrategy_ShouldScheduleNothingWhenChangingToDefaultStrategy()
        public
    {
        setUpChoseDefaultStrategy();

        manager.changeStrategy(ADDRESS_ZERO);

        assertNoTransferScheduled();
    }

    function test_changeStrategy_WhenDepositorChoseDefaultStrategy_ShouldScheduleTransfersWhenChangingToSpecificStrategy()
        public
    {
        setUpChoseDefaultStrategy();

        manager.changeStrategy(specificGroupStrategyAddress);

        assertEq(
            specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress),
            STRATEGY_DEPOSIT
        );
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[0]), 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[1]), 0);
    }

    // =========================================================================
    //                       #forceChangeStrategy()
    // =========================================================================

    function test_forceChangeStrategy_ShouldRevertWhenCalledByNonOwner() public {
        address slashedGroup = groupAddresses[0];
        slashGroup(slashedGroup);
        mineToNextEpoch();
        electAndUpdate(slashedGroup);

        vm.prank(nonOwner);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        manager.forceChangeStrategy(depositor, slashedGroup);
    }

    function test_forceChangeStrategy_WhenChangingWithNoPreviousStCelo_ShouldAddGroupToVotedStrategies()
        public
    {
        vm.prank(owner);
        manager.forceChangeStrategy(depositor, groupAddresses[0]);

        vm.prank(depositor);
        manager.deposit{value: 100}();
        assertEq(getSpecificGroups(specificGroupStrategy), arr(groupAddresses[0]));
    }

    function test_forceChangeStrategy_WhenChangingWithNoPreviousStCelo_ShouldChangeAccountStrategy()
        public
    {
        vm.prank(owner);
        manager.forceChangeStrategy(depositor, groupAddresses[0]);

        assertEq(manager.getAddressStrategy(depositor), groupAddresses[0]);
    }

    function test_forceChangeStrategy_WhenDepositorChoseSpecificStrategy_ShouldScheduleNothingWhenTryingToChangeToSameSpecificStrategy()
        public
    {
        setUpForcedSpecificStrategy();

        vm.prank(owner);
        manager.forceChangeStrategy(depositor, specificGroupStrategyAddress);

        assertNoTransferScheduled();
    }

    function test_forceChangeStrategy_WhenDepositorChoseSpecificStrategy_ShouldScheduleTransfersWhenChangingToDifferentSpecificStrategy()
        public
    {
        setUpForcedSpecificStrategy();

        vm.prank(owner);
        manager.forceChangeStrategy(depositor, ADDRESS_ZERO);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(
            mockDefaultStrategy.stCeloInGroup(groupAddresses[0]),
            mockDefaultStrategy.stCeloInGroup(groupAddresses[0])
        );
    }

    function test_forceChangeStrategy_WhenDepositorChoseSpecificStrategy_ShouldScheduleTransfersWhenChangingToDefaultStrategy()
        public
    {
        setUpForcedSpecificStrategy();

        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        vm.prank(owner);
        manager.forceChangeStrategy(depositor, ADDRESS_ZERO);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[0]), 0);
        assertEq(tail, groupAddresses[1]);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[1]), STRATEGY_DEPOSIT);
    }

    function test_forceChangeStrategy_WhenDepositorChoseSpecificStrategy_WhenChosenGroupIsUnhealthy_ShouldScheduleTransfersFromGroupSinceGroupWasNotRebalancedWhenChangingToDifferentSpecificStrategy()
        public
    {
        setUpForcedSpecificStrategy();
        setUpChosenGroupUnhealthy();

        address differentSpecificGroupStrategy = groupAddresses[0];
        vm.prank(owner);
        manager.forceChangeStrategy(depositor, differentSpecificGroupStrategy);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(
            specificGroupStrategy.stCeloInGroup(differentSpecificGroupStrategy),
            STRATEGY_DEPOSIT
        );
    }

    function test_forceChangeStrategy_WhenDepositorChoseSpecificStrategy_WhenChosenGroupIsUnhealthy_WhenRebalanced_ShouldScheduleTransfersWhenChangingToDefaultStrategy()
        public
    {
        setUpForcedSpecificStrategy();
        setUpChosenGroupUnhealthy();
        setUpRebalanced();

        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        vm.prank(owner);
        manager.forceChangeStrategy(depositor, ADDRESS_ZERO);

        (uint256 stCeloInStrategy, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(specificGroupStrategyAddress);
        assertEq(stCeloInStrategy, 0);
        assertEq(overflow, 0);
        assertEq(unhealthy, 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(tail), STRATEGY_DEPOSIT);
    }

    function test_forceChangeStrategy_WhenDepositorChoseSpecificStrategy_WhenChosenGroupIsUnhealthy_ShouldScheduleTransfersWhenChangingToDefaultStrategy()
        public
    {
        setUpForcedSpecificStrategy();
        setUpChosenGroupUnhealthy();

        (address tail, ) = mockDefaultStrategy.getGroupsTail();
        vm.prank(owner);
        manager.forceChangeStrategy(depositor, ADDRESS_ZERO);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[0]), 0);
        assertEq(tail, groupAddresses[1]);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[1]), STRATEGY_DEPOSIT);
    }

    function test_forceChangeStrategy_WhenDepositorChoseDefaultStrategy_ShouldScheduleNothingWhenChangingToDefaultStrategy()
        public
    {
        setUpForcedDefaultStrategy();

        vm.prank(owner);
        manager.forceChangeStrategy(depositor, ADDRESS_ZERO);

        assertNoTransferScheduled();
    }

    function test_forceChangeStrategy_WhenDepositorChoseDefaultStrategy_ShouldScheduleTransfersWhenChangingToSpecificStrategy()
        public
    {
        setUpForcedDefaultStrategy();

        vm.prank(owner);
        manager.forceChangeStrategy(depositor, specificGroupStrategyAddress);

        assertEq(
            specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress),
            STRATEGY_DEPOSIT
        );
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[0]), 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[1]), 0);
    }

    // =========================================================================
    //                          BLOCK FIXTURES
    // =========================================================================

    /// @dev `beforeEach` of `#changeStrategy() > When depositor chose specific strategy`.
    function setUpChoseSpecificStrategy() private {
        manager.changeStrategy(specificGroupStrategyAddress);
        manager.deposit{value: STRATEGY_DEPOSIT}();
        mockAccount.setCeloForGroup(specificGroupStrategyAddress, STRATEGY_DEPOSIT);
    }

    /// @dev `beforeEach` of `#changeStrategy() > When depositor chose default strategy`.
    function setUpChoseDefaultStrategy() private {
        manager.deposit{value: STRATEGY_DEPOSIT}();
        updateGroupCelo();
    }

    /// @dev `beforeEach` of `#forceChangeStrategy() > When depositor chose specific strategy`.
    function setUpForcedSpecificStrategy() private {
        vm.prank(owner);
        manager.forceChangeStrategy(depositor, specificGroupStrategyAddress);
        vm.prank(depositor);
        manager.deposit{value: STRATEGY_DEPOSIT}();
        mockAccount.setCeloForGroup(specificGroupStrategyAddress, STRATEGY_DEPOSIT);
    }

    /// @dev `beforeEach` of `#forceChangeStrategy() > When depositor chose default strategy`.
    function setUpForcedDefaultStrategy() private {
        vm.prank(depositor);
        manager.deposit{value: STRATEGY_DEPOSIT}();
        updateGroupCelo();
    }

    /// @dev `beforeEach` of the `When chosen group is unhealthy` blocks.
    function setUpChosenGroupUnhealthy() private {
        slashGroup(groupAddresses[2]);
        mockGroupHealth.updateGroupHealth(specificGroupStrategyAddress);
    }

    /// @dev `beforeEach` of the `When rebalanced` blocks.
    function setUpRebalanced() private {
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupStrategyAddress);
        updateGroupCelo();
    }
}
