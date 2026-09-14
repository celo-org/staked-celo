// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./DefaultStrategyTestBase.sol";

/**
 * @title DefaultStrategyOrderTest
 * @notice Ports the sorting describe blocks of `test-ts/default-strategy.test.ts`:
 *         `#updateActiveGroupOrder()`, `#getGroupsHead()` and `#getGroupsTail()`.
 */
contract DefaultStrategyOrderTest is DefaultStrategyTestBase {
    /// @dev Amount withdrawn by `describe("when withdrawn with big enough sorting limit")`.
    uint256 internal constant WITHDRAWN = 250;

    address internal originalTail;
    address internal originalHead;
    uint256 internal totalDeposited;
    OrderedGroup[] internal originalOrderedGroups;

    function setUp() public {
        _deployDefaultStrategyFixture();
    }

    // =========================================================================
    //                       NESTED beforeEach HELPERS
    // =========================================================================

    /// @dev `describe("#updateActiveGroupOrder()")` beforeEach.
    function _setUpActiveGroups() private {
        _activateGroupsFromPrevious(3);
    }

    function _setSortingParams(uint256 loopLimit) private {
        vm.prank(owner);
        mockDefaultStrategy.setSortingParams(3, 3, loopLimit);
    }

    function _depositIncreasingAmounts() private {
        for (uint256 i = 0; i < 3; i++) {
            manager.deposit{value: (i + 1) * 100}();
        }
    }

    function _storeOrderedGroups() private {
        delete originalOrderedGroups;
        OrderedGroup[] memory ordered = getOrderedActiveGroups(defaultStrategy);
        for (uint256 i = 0; i < ordered.length; i++) {
            originalOrderedGroups.push(ordered[i]);
        }
    }

    /// @dev `describe("when deposited with big enough sorting limit")` beforeEach.
    function _setUpDepositedBigSortingLimit() private {
        _setUpActiveGroups();
        _setSortingParams(3);
        _depositIncreasingAmounts();
    }

    /// @dev `describe("when deposited with {0,1} sorting loop limit to TAIL only")` beforeEach.
    function _setUpDepositedToTailOnly(uint256 loopLimit) private {
        _setUpActiveGroups();
        _setSortingParams(loopLimit);
        (originalTail, ) = defaultStrategy.getGroupsTail();
        _depositIncreasingAmounts();
    }

    /// @dev ... `> describe("When updateActiveGroupOrder called")` beforeEach.
    function _setUpDepositedToTailOnlyUpdated(uint256 loopLimit) private {
        _setUpDepositedToTailOnly(loopLimit);
        (address head, ) = defaultStrategy.getGroupsHead();
        mockDefaultStrategy.updateActiveGroupOrder(originalTail, head, ADDRESS_ZERO);
    }

    /// @dev `describe("when deposited with 0 sorting loop limit to more groups")` beforeEach.
    function _setUpDepositedToMoreGroups() private {
        _setUpActiveGroups();
        _setSortingParams(0);
        (originalTail, ) = defaultStrategy.getGroupsTail();

        prepareOverflow(defaultStrategy, voter, groupAddresses, false);
        _storeOrderedGroups();
        manager.deposit{value: 250 ether}();
    }

    /// @dev ... `> describe("When updateActiveGroupOrder called")` beforeEach.
    function _setUpDepositedToMoreGroupsUpdated() private {
        _setUpDepositedToMoreGroups();
        (address head, ) = defaultStrategy.getGroupsHead();
        mockDefaultStrategy.updateActiveGroupOrder(originalTail, head, ADDRESS_ZERO);
        mockDefaultStrategy.updateActiveGroupOrder(
            originalOrderedGroups[1].group,
            head,
            ADDRESS_ZERO
        );
    }

    /// @dev `describe("when withdrawn with big enough sorting limit")` beforeEach.
    function _setUpWithdrawnBigSortingLimit() private {
        _setUpActiveGroups();
        totalDeposited = 0;
        _setSortingParams(3);
        for (uint256 i = 0; i < 3; i++) {
            uint256 toDeposit = (i + 1) * 100;
            manager.deposit{value: toDeposit}();
            totalDeposited += toDeposit;
        }
        _updateGroupCelo();
        manager.withdraw(WITHDRAWN);
    }

    /// @dev `describe("when withdrawing with {0,1} sorting loop limit")` beforeEach.
    function _setUpWithdrawingBase(uint256 loopLimit) private {
        _setUpActiveGroups();
        _depositIncreasingAmounts();
        (originalHead, ) = defaultStrategy.getGroupsHead();
        _setSortingParams(loopLimit);
        assertTrue(defaultStrategy.sorted());
    }

    /// @dev ... `> describe("when withdrawing from 1 group")` beforeEach.
    function _setUpWithdrawFromOneGroup(uint256 loopLimit) private {
        _setUpWithdrawingBase(loopLimit);
        _updateGroupCelo();
        manager.withdraw(250);
    }

    /// @dev ... `> describe("When updateActiveGroupOrder called")` beforeEach.
    function _setUpWithdrawFromOneGroupUpdated(uint256 loopLimit) private {
        _setUpWithdrawFromOneGroup(loopLimit);
        (address tail, ) = defaultStrategy.getGroupsTail();
        mockDefaultStrategy.updateActiveGroupOrder(originalHead, ADDRESS_ZERO, tail);
    }

    /// @dev ... `> describe("when withdrawing from more groups")` beforeEach.
    function _setUpWithdrawFromMoreGroups(uint256 loopLimit) private {
        _setUpWithdrawingBase(loopLimit);
        _storeOrderedGroups();
        _updateGroupCelo();
        manager.withdraw(450);
    }

    /// @dev ... `> describe("When updateActiveGroupOrder called")` beforeEach.
    function _setUpWithdrawFromMoreGroupsUpdated(uint256 loopLimit) private {
        _setUpWithdrawFromMoreGroups(loopLimit);
        (address tail, ) = defaultStrategy.getGroupsTail();
        uint256 count = originalOrderedGroups.length;
        mockDefaultStrategy.updateActiveGroupOrder(
            originalOrderedGroups[count - 2].group,
            ADDRESS_ZERO,
            tail
        );
        mockDefaultStrategy.updateActiveGroupOrder(
            originalOrderedGroups[count - 1].group,
            ADDRESS_ZERO,
            tail
        );
    }

    /// @dev The two tail-most groups of `originalOrderedGroups` (`slice(0, 2)`).
    function _firstTwoOriginalGroups() private view returns (address[] memory groups) {
        groups = new address[](2);
        groups[0] = originalOrderedGroups[0].group;
        groups[1] = originalOrderedGroups[1].group;
    }

    /// @dev The two head-most groups of `originalOrderedGroups` (`slice(length - 2)`).
    function _lastTwoOriginalGroups() private view returns (address[] memory groups) {
        uint256 count = originalOrderedGroups.length;
        groups = new address[](2);
        groups[0] = originalOrderedGroups[count - 2].group;
        groups[1] = originalOrderedGroups[count - 1].group;
    }

    function _assertUnsortedGroupsEmpty() private view {
        _assertSameMembers(getUnsortedGroups(defaultStrategy), new address[](0));
    }

    // =========================================================================
    //                      #updateActiveGroupOrder()
    // =========================================================================

    function test_updateActiveGroupOrder_ShouldHaveSortedFlagSetToTrue() public {
        _setUpActiveGroups();

        assertTrue(defaultStrategy.sorted());
    }

    // ---- when deposited with big enough sorting limit ----

    function test_updateActiveGroupOrder_WhenDepositedWithBigEnoughSortingLimit_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpDepositedBigSortingLimit();

        assertTrue(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenDepositedWithBigEnoughSortingLimit_ShouldHaveCorrectlyOrderedActiveGroups()
        public
    {
        _setUpDepositedBigSortingLimit();

        _assertCorrectOrder();
    }

    // ---- when deposited with 0 sorting loop limit to TAIL only ----

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToTailOnly_ShouldHaveSortedFlagSetToFalse()
        public
    {
        _setUpDepositedToTailOnly(0);

        assertFalse(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToTailOnly_ShouldHaveTailInUnsortedGroups()
        public
    {
        _setUpDepositedToTailOnly(0);

        _assertSameMembers(getUnsortedGroups(defaultStrategy), _toArray(originalTail));
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToTailOnly_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheHead()
        public
    {
        _setUpDepositedToTailOnlyUpdated(0);

        (address currentHead, ) = defaultStrategy.getGroupsHead();
        assertEq(currentHead, originalTail);
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToTailOnly_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheTail()
        public
    {
        _setUpDepositedToTailOnlyUpdated(0);

        (address currentTail, ) = defaultStrategy.getGroupsTail();
        assertNotEq(currentTail, originalTail);
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToTailOnly_WhenUpdateActiveGroupOrderCalled_ShouldEmptyUnsortedGroups()
        public
    {
        _setUpDepositedToTailOnlyUpdated(0);

        _assertUnsortedGroupsEmpty();
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToTailOnly_WhenUpdateActiveGroupOrderCalled_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpDepositedToTailOnlyUpdated(0);

        assertTrue(defaultStrategy.sorted());
    }

    // ---- when deposited with 1 sorting loop limit to TAIL only ----

    function test_updateActiveGroupOrder_WhenDepositedWith1SortingLoopLimitToTailOnly_ShouldHaveSortedFlagSetToFalse()
        public
    {
        _setUpDepositedToTailOnly(1);

        assertFalse(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenDepositedWith1SortingLoopLimitToTailOnly_ShouldHaveTailInUnsortedGroups()
        public
    {
        _setUpDepositedToTailOnly(1);

        _assertSameMembers(getUnsortedGroups(defaultStrategy), _toArray(originalTail));
    }

    function test_updateActiveGroupOrder_WhenDepositedWith1SortingLoopLimitToTailOnly_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheHead()
        public
    {
        _setUpDepositedToTailOnlyUpdated(1);

        (address currentHead, ) = defaultStrategy.getGroupsHead();
        assertEq(currentHead, originalTail);
    }

    function test_updateActiveGroupOrder_WhenDepositedWith1SortingLoopLimitToTailOnly_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheTail()
        public
    {
        _setUpDepositedToTailOnlyUpdated(1);

        (address currentTail, ) = defaultStrategy.getGroupsTail();
        assertNotEq(currentTail, originalTail);
    }

    function test_updateActiveGroupOrder_WhenDepositedWith1SortingLoopLimitToTailOnly_WhenUpdateActiveGroupOrderCalled_ShouldEmptyUnsortedGroups()
        public
    {
        _setUpDepositedToTailOnlyUpdated(1);

        _assertUnsortedGroupsEmpty();
    }

    function test_updateActiveGroupOrder_WhenDepositedWith1SortingLoopLimitToTailOnly_WhenUpdateActiveGroupOrderCalled_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpDepositedToTailOnlyUpdated(1);

        assertTrue(defaultStrategy.sorted());
    }

    // ---- when deposited with 0 sorting loop limit to more groups ----

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToMoreGroups_ShouldHaveSortedFlagSetToFalse()
        public
    {
        _setUpDepositedToMoreGroups();

        assertFalse(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToMoreGroups_ShouldHaveTailGroupsInUnsortedGroups()
        public
    {
        _setUpDepositedToMoreGroups();

        _assertSameMembers(getUnsortedGroups(defaultStrategy), _firstTwoOriginalGroups());
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheHead()
        public
    {
        _setUpDepositedToMoreGroupsUpdated();

        (address currentHead, ) = defaultStrategy.getGroupsHead();
        assertEq(currentHead, originalTail);
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheTail()
        public
    {
        _setUpDepositedToMoreGroupsUpdated();

        (address currentTail, ) = defaultStrategy.getGroupsTail();
        assertNotEq(currentTail, originalTail);
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldEmptyUnsortedGroups()
        public
    {
        _setUpDepositedToMoreGroupsUpdated();

        _assertUnsortedGroupsEmpty();
    }

    function test_updateActiveGroupOrder_WhenDepositedWith0SortingLoopLimitToMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpDepositedToMoreGroupsUpdated();

        assertTrue(defaultStrategy.sorted());
    }

    // ---- when withdrawn with big enough sorting limit ----

    function test_updateActiveGroupOrder_WhenWithdrawnWithBigEnoughSortingLimit_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpWithdrawnBigSortingLimit();

        assertTrue(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenWithdrawnWithBigEnoughSortingLimit_ShouldHaveCorrectlyOrderedActiveGroups()
        public
    {
        _setUpWithdrawnBigSortingLimit();

        OrderedGroup[] memory ordered = getOrderedActiveGroups(defaultStrategy);
        uint256 previous = 0;
        uint256 totalAmountInProtocol = 0;
        for (uint256 i = 0; i < ordered.length; i++) {
            assertTrue(previous <= ordered[i].stCelo);
            previous = ordered[i].stCelo;
            totalAmountInProtocol += previous;
        }
        assertEq(totalAmountInProtocol, totalDeposited - WITHDRAWN);
    }

    // ---- when withdrawing with 0 sorting loop limit / from 1 group ----

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFrom1Group_ShouldHaveSortedFlagSetToFalse()
        public
    {
        _setUpWithdrawFromOneGroup(0);

        assertFalse(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFrom1Group_ShouldHaveHeadInUnsortedGroups()
        public
    {
        _setUpWithdrawFromOneGroup(0);

        _assertSameMembers(getUnsortedGroups(defaultStrategy), _toArray(originalHead));
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFrom1Group_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheTail()
        public
    {
        _setUpWithdrawFromOneGroupUpdated(0);

        (address currentTail, ) = defaultStrategy.getGroupsTail();
        assertEq(currentTail, originalHead);
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFrom1Group_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheHead()
        public
    {
        _setUpWithdrawFromOneGroupUpdated(0);

        (address currentHead, ) = defaultStrategy.getGroupsHead();
        assertNotEq(currentHead, originalHead);
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFrom1Group_WhenUpdateActiveGroupOrderCalled_ShouldEmptyUnsortedGroups()
        public
    {
        _setUpWithdrawFromOneGroupUpdated(0);

        _assertUnsortedGroupsEmpty();
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFrom1Group_WhenUpdateActiveGroupOrderCalled_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpWithdrawFromOneGroupUpdated(0);

        assertTrue(defaultStrategy.sorted());
    }

    // ---- when withdrawing with 0 sorting loop limit / from more groups ----

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFromMoreGroups_ShouldHaveSortedFlagSetToFalse()
        public
    {
        _setUpWithdrawFromMoreGroups(0);

        assertFalse(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFromMoreGroups_ShouldHaveHeadGroupsInUnsortedGroups()
        public
    {
        _setUpWithdrawFromMoreGroups(0);

        _assertSameMembers(getUnsortedGroups(defaultStrategy), _lastTwoOriginalGroups());
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFromMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheTail()
        public
    {
        _setUpWithdrawFromMoreGroupsUpdated(0);

        (address currentTail, ) = defaultStrategy.getGroupsTail();
        assertEq(currentTail, originalHead);
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFromMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheHead()
        public
    {
        _setUpWithdrawFromMoreGroupsUpdated(0);

        (address currentHead, ) = defaultStrategy.getGroupsHead();
        assertNotEq(currentHead, originalHead);
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFromMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldEmptyUnsortedGroups()
        public
    {
        _setUpWithdrawFromMoreGroupsUpdated(0);

        _assertUnsortedGroupsEmpty();
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith0SortingLoopLimit_WhenWithdrawingFromMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpWithdrawFromMoreGroupsUpdated(0);

        assertTrue(defaultStrategy.sorted());
    }

    // ---- when withdrawing with 1 sorting loop limit / from 1 group ----

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFrom1Group_ShouldHaveSortedFlagSetToFalse()
        public
    {
        _setUpWithdrawFromOneGroup(1);

        assertFalse(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFrom1Group_ShouldHaveHeadInUnsortedGroups()
        public
    {
        _setUpWithdrawFromOneGroup(1);

        _assertSameMembers(getUnsortedGroups(defaultStrategy), _toArray(originalHead));
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFrom1Group_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheTail()
        public
    {
        _setUpWithdrawFromOneGroupUpdated(1);

        (address currentTail, ) = defaultStrategy.getGroupsTail();
        assertEq(currentTail, originalHead);
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFrom1Group_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheHead()
        public
    {
        _setUpWithdrawFromOneGroupUpdated(1);

        (address currentHead, ) = defaultStrategy.getGroupsHead();
        assertNotEq(currentHead, originalHead);
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFrom1Group_WhenUpdateActiveGroupOrderCalled_ShouldEmptyUnsortedGroups()
        public
    {
        _setUpWithdrawFromOneGroupUpdated(1);

        _assertUnsortedGroupsEmpty();
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFrom1Group_WhenUpdateActiveGroupOrderCalled_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpWithdrawFromOneGroupUpdated(1);

        assertTrue(defaultStrategy.sorted());
    }

    // ---- when withdrawing with 1 sorting loop limit / from more groups ----

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFromMoreGroups_ShouldHaveSortedFlagSetToFalse()
        public
    {
        _setUpWithdrawFromMoreGroups(1);

        assertFalse(defaultStrategy.sorted());
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFromMoreGroups_ShouldHaveHeadGroupsInUnsortedGroups()
        public
    {
        _setUpWithdrawFromMoreGroups(1);

        _assertSameMembers(getUnsortedGroups(defaultStrategy), _lastTwoOriginalGroups());
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFromMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheTail()
        public
    {
        _setUpWithdrawFromMoreGroupsUpdated(1);

        (address currentTail, ) = defaultStrategy.getGroupsTail();
        assertEq(currentTail, originalHead);
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFromMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldChangeTheHead()
        public
    {
        _setUpWithdrawFromMoreGroupsUpdated(1);

        (address currentHead, ) = defaultStrategy.getGroupsHead();
        assertNotEq(currentHead, originalHead);
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFromMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldEmptyUnsortedGroups()
        public
    {
        _setUpWithdrawFromMoreGroupsUpdated(1);

        _assertUnsortedGroupsEmpty();
    }

    function test_updateActiveGroupOrder_WhenWithdrawingWith1SortingLoopLimit_WhenWithdrawingFromMoreGroups_WhenUpdateActiveGroupOrderCalled_ShouldHaveSortedFlagSetToTrue()
        public
    {
        _setUpWithdrawFromMoreGroupsUpdated(1);

        assertTrue(defaultStrategy.sorted());
    }

    // =========================================================================
    //                           #getGroupsHead()
    // =========================================================================

    function test_getGroupsHead_ReturnsEmptyWhenNoActiveGroups() public {
        (address head, address previous) = defaultStrategy.getGroupsHead();
        assertEq(head, ADDRESS_ZERO);
        assertEq(previous, ADDRESS_ZERO);
    }

    /// @dev `describe("When active groups")` beforeEach of `#getGroupsHead()`/`#getGroupsTail()`.
    function _setUpHeadTailActiveGroups() private {
        _activateGroupsFromPrevious(3);
        manager.deposit{value: 100}();
        manager.deposit{value: 50}();
    }

    function test_getGroupsHead_WhenActiveGroups_ShouldReturnHeadCorrectly() public {
        _setUpHeadTailActiveGroups();

        OrderedGroup[] memory allGroups = getOrderedActiveGroups(defaultStrategy);
        (address head, address previous) = defaultStrategy.getGroupsHead();
        OrderedGroup[] memory sortedGroups = _sortByStCelo(allGroups);

        assertEq(sortedGroups[sortedGroups.length - 1].group, head);
        assertEq(sortedGroups[sortedGroups.length - 2].group, previous);
    }

    // =========================================================================
    //                           #getGroupsTail()
    // =========================================================================

    function test_getGroupsTail_ReturnsEmptyWhenNoActiveGroups() public {
        (address tail, address next) = defaultStrategy.getGroupsTail();
        assertEq(tail, ADDRESS_ZERO);
        assertEq(next, ADDRESS_ZERO);
    }

    function test_getGroupsTail_WhenActiveGroups_ShouldReturnTailCorrectly() public {
        _setUpHeadTailActiveGroups();

        OrderedGroup[] memory allGroups = getOrderedActiveGroups(defaultStrategy);
        (address tail, address next) = defaultStrategy.getGroupsTail();
        OrderedGroup[] memory sortedGroups = _sortByStCelo(allGroups);

        assertEq(sortedGroups[0].group, tail);
        assertEq(sortedGroups[1].group, next);
    }
}
