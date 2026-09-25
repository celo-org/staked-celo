// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./DefaultStrategyTestBase.sol";

/**
 * @title DefaultStrategyRebalanceTest
 * @notice Ports the accounting describe blocks of `test-ts/default-strategy.test.ts`:
 *         `#getExpectedAndActualStCeloForGroup()`, `#rebalance()` and `#updateGroupStCelo`.
 */
contract DefaultStrategyRebalanceTest is DefaultStrategyTestBase {
    /// @dev `originalTail` / `currentHead` of the nested describe blocks.
    address internal originalTail;
    address internal currentHead;

    function setUp() public {
        _deployDefaultStrategyFixture();
    }

    // =========================================================================
    //               #getExpectedAndActualStCeloForGroup()
    // =========================================================================

    function test_getExpectedAndActualStCeloForGroup_ShouldReturn0WhenNoDeposit() public {
        _activateGroupsFromPrevious(3);

        (uint256 expected, uint256 actual) =
            defaultStrategy.getExpectedAndActualStCeloForGroup(groupAddresses[0]);
        assertEq(expected, 0);
        assertEq(actual, 0);
    }

    /// @dev `describe("When deposited")` beforeEach of `#getExpectedAndActualStCeloForGroup()`.
    function _setUpExpectedAndActualDeposited() private {
        _activateGroupsFromPrevious(3);
        (originalTail,) = defaultStrategy.getGroupsTail();
        manager.deposit{value: 100}();
    }

    function test_getExpectedAndActualStCeloForGroup_WhenDeposited_ShouldReturnMoreRealStCeloInOriginalTailCurrentHead()
        public
    {
        _setUpExpectedAndActualDeposited();

        (address head,) = defaultStrategy.getGroupsHead();
        assertEq(head, originalTail);

        (uint256 expected, uint256 actual) =
            defaultStrategy.getExpectedAndActualStCeloForGroup(head);
        assertEq(expected, 34);
        assertEq(actual, 100);
    }

    function test_getExpectedAndActualStCeloForGroup_WhenDeposited_ShouldReturn0RealStCeloButCorrectExpectedForOtherThanHead()
        public
    {
        _setUpExpectedAndActualDeposited();

        (uint256 expected, uint256 actual) =
            defaultStrategy.getExpectedAndActualStCeloForGroup(groupAddresses[1]);
        assertNotEq(groupAddresses[1], originalTail);
        assertEq(expected, 33);
        assertEq(actual, 0);
    }

    // =========================================================================
    //                            #rebalance()
    // =========================================================================

    function test_rebalance_ShouldRevertWhenRebalancingFromNonActiveGroup() public {
        _activateGroupsFromPrevious(3);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.InvalidFromGroup.selector, groupAddresses[7])
        );
        mockDefaultStrategy.rebalance(groupAddresses[7], groupAddresses[0]);
    }

    function test_rebalance_ShouldRevertWhenRebalancingToNonActiveGroup() public {
        _activateGroupsFromPrevious(3);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.InvalidToGroup.selector, groupAddresses[7])
        );
        mockDefaultStrategy.rebalance(groupAddresses[0], groupAddresses[7]);
    }

    function test_rebalance_ShouldRevertWhenNothingDeposited() public {
        _activateGroupsFromPrevious(3);

        vm.expectRevert(
            abi.encodeWithSelector(
                DefaultStrategy.RebalanceNoExtraStCelo.selector, groupAddresses[0], 0, 0
            )
        );
        mockDefaultStrategy.rebalance(groupAddresses[0], groupAddresses[1]);
    }

    /// @dev `describe("When deposited")` beforeEach of `#rebalance()`.
    function _setUpRebalanceDeposited() private {
        _activateGroupsFromPrevious(3);
        manager.deposit{value: 49}();
        manager.deposit{value: 51}();
        (currentHead,) = defaultStrategy.getGroupsHead();
    }

    function test_rebalance_WhenDeposited_ShouldHaveStCeloOnlyInTwoGroups() public {
        _setUpRebalanceDeposited();

        assertEq(defaultStrategy.stCeloInGroup(currentHead), 51);
        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[0]), 0);
        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[1]), 51);
        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[2]), 49);
        _assertCorrectOrder();
    }

    function test_rebalance_WhenDeposited_ShouldRebalanceCorrectly() public {
        _setUpRebalanceDeposited();

        _assertCorrectOrder();
        mockDefaultStrategy.rebalance(groupAddresses[1], groupAddresses[0]);
        _assertCorrectOrder();
        mockDefaultStrategy.rebalance(groupAddresses[2], groupAddresses[0]);
        _assertCorrectOrder();

        assertEq(defaultStrategy.stCeloInGroup(currentHead), 34);
        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[0]), 32);
        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[1]), 34);
        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[2]), 34);

        assertTrue(defaultStrategy.sorted());
    }

    function test_rebalance_WhenDeposited_EmitsRebalancedEvent() public {
        _setUpRebalanceDeposited();

        _expectEmitFrom(address(mockDefaultStrategy));
        emit Rebalanced(groupAddresses[1], groupAddresses[0], 17);
        mockDefaultStrategy.rebalance(groupAddresses[1], groupAddresses[0]);
    }

    function test_rebalance_WhenDeposited_ShouldRevertWhenRebalancingFromEmptyGroup() public {
        _setUpRebalanceDeposited();

        vm.expectRevert(
            abi.encodeWithSelector(
                DefaultStrategy.RebalanceNoExtraStCelo.selector, groupAddresses[0], 0, 33
            )
        );
        mockDefaultStrategy.rebalance(groupAddresses[0], currentHead);
    }

    function test_rebalance_WhenDeposited_ShouldRevertWhenRebalancingToAlreadyRebalancedGroup()
        public
    {
        _setUpRebalanceDeposited();

        manager.deposit{value: 50}();

        vm.expectRevert(
            abi.encodeWithSelector(
                DefaultStrategy.RebalanceEnoughStCelo.selector, groupAddresses[0], 50, 50
            )
        );
        mockDefaultStrategy.rebalance(groupAddresses[1], groupAddresses[0]);
    }

    /// @dev `describe("When sorting loop limit 0 and rebalancing")` beforeEach.
    function _setUpSortingLoopLimitZeroRebalance() private {
        _setUpRebalanceDeposited();

        vm.prank(owner);
        mockDefaultStrategy.setSortingParams(10, 10, 0);
        mockDefaultStrategy.rebalance(currentHead, groupAddresses[0]);
        assertNotEq(currentHead, groupAddresses[0]);
    }

    function test_rebalance_WhenDeposited_WhenSortingLoopLimit0AndRebalancing_ShouldSetSortedToFalse()
        public
    {
        _setUpSortingLoopLimitZeroRebalance();

        assertFalse(defaultStrategy.sorted());
    }

    function test_rebalance_WhenDeposited_WhenSortingLoopLimit0AndRebalancing_ShouldAddRebalancedGroupToUnsortedGroups()
        public
    {
        _setUpSortingLoopLimitZeroRebalance();

        address[] memory unsortedGroups = getUnsortedGroups(defaultStrategy);
        _assertContains(unsortedGroups, currentHead);
        _assertContains(unsortedGroups, groupAddresses[0]);
    }

    // =========================================================================
    //                         #updateGroupStCelo
    // =========================================================================

    function test_updateGroupStCelo_ShouldRevertWhenNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        mockDefaultStrategy.updateGroupStCelo(groupAddresses[0], 100, true);
    }

    function test_updateGroupStCelo_ShouldAddGroupStCelo() public {
        vm.prank(owner);
        mockDefaultStrategy.updateGroupStCelo(groupAddresses[0], 100, true);

        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[0]), 100);
        assertEq(defaultStrategy.totalStCeloInStrategy(), 100);
    }

    function test_updateGroupStCelo_ShouldSubtractGroupStCelo() public {
        vm.prank(owner);
        mockDefaultStrategy.updateGroupStCelo(groupAddresses[0], 100, true);
        vm.prank(owner);
        mockDefaultStrategy.updateGroupStCelo(groupAddresses[0], 50, false);

        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[0]), 50);
        assertEq(defaultStrategy.totalStCeloInStrategy(), 50);
    }

    function test_updateGroupStCelo_EmitsGroupStCeloUpdatedEventWhenAdding() public {
        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupStCeloUpdated(groupAddresses[0], 100, true);
        vm.prank(owner);
        mockDefaultStrategy.updateGroupStCelo(groupAddresses[0], 100, true);
    }

    function test_updateGroupStCelo_EmitsGroupStCeloUpdatedEventWhenSubtracting() public {
        vm.prank(owner);
        mockDefaultStrategy.updateGroupStCelo(groupAddresses[0], 100, true);

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupStCeloUpdated(groupAddresses[0], 50, false);
        vm.prank(owner);
        mockDefaultStrategy.updateGroupStCelo(groupAddresses[0], 50, false);
    }
}
