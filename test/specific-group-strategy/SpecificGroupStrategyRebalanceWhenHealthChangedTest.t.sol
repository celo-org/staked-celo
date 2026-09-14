// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./SpecificGroupStrategyTestBase.sol";

/**
 * @title SpecificGroupStrategyRebalanceWhenHealthChangedTest
 * @notice Port of describe("#rebalanceWhenHealthChanged()") (33 cases) of
 *         test-ts/specific_group_strategy.test.ts.
 * @dev Deviation: the original hardcoded `firstGroupCapacity = 40.166666666666666666 CELO`,
 *      the receivable votes the ganache devchain left for groups[0] after `prepareOverflow`.
 *      The anvil devchain solves the vote amounts from the chain state, so the capacity is
 *      read from the Election contract right after `prepareOverflow` instead of hardcoded.
 */
contract SpecificGroupStrategyRebalanceWhenHealthChangedTest is SpecificGroupStrategyTestBase {
    /// @dev `specificGroupAddress` of the original test.
    address internal specificGroupAddress;
    /// @dev `deposit` of the nested describe blocks.
    uint256 internal deposit;
    /// @dev `tail` of describe("When active groups and rebalanceWhenHealthChanged called").
    address internal tail;
    /// @dev `head` of the describe("When group becomes ... again") blocks.
    address internal head;

    /// @dev `firstGroupCapacity` of describe("When overflowing group is blocked").
    uint256 internal firstGroupCapacity;
    /// @dev `depositOverCapacity` of describe("When overflowing group is blocked").
    uint256 internal constant DEPOSIT_OVER_CAPACITY = 10 ether;
    /// @dev `nextToTail` of describe("When ratio 1:1").
    address internal nextToTail;
    /// @dev `specificOverflowingGroup` of describe("When overflowing group is blocked").
    address internal specificOverflowingGroup;

    function setUp() public {
        _setUpSpecificGroupStrategy();

        // beforeEach of describe("#rebalanceWhenHealthChanged()")
        specificGroupAddress = groupAddresses[4];
    }

    // =========================================================================
    //                     #rebalanceWhenHealthChanged()
    // =========================================================================

    /// @dev The original `expect(...).revertedWith(...)` was missing its `await`, so the
    ///      assertion resolved after the test had finished and never ran. The revert is
    ///      asserted for real here.
    function test_rebalanceWhenHealthChanged_ShouldRevertWhenHealthyAndNoUnhealthyStCelo() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.GroupBalanced.selector,
                specificGroupAddress
            )
        );
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);
    }

    // ------------------------ When group is unhealthy -------------------------

    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_ShouldHaveUnhealthyGroup()
        public
    {
        _whenGroupIsUnhealthy();

        assertFalse(mockGroupHealth.isGroupValid(specificGroupAddress));
    }

    /// @dev The original `expect(...).revertedWith(...)` was missing its `await`, so the
    ///      assertion resolved after the test had finished and never ran. The revert is
    ///      asserted for real here.
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_ShouldRevertWhenNoStCeloInGroup()
        public
    {
        _whenGroupIsUnhealthy();

        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.GroupBalanced.selector,
                specificGroupAddress
            )
        );
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);
    }

    // --------------------- When Celo deposited in group -----------------------

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_ShouldHaveStCeloInStrategy()
        public
    {
        _whenCeloDepositedInGroup();

        GroupStCelo memory amounts = _stCeloInGroup(specificGroupAddress);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, 0);
        assertEq(amounts.unhealthy, 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_ShouldRevertWhenNoActiveGroups()
        public
    {
        _whenCeloDepositedInGroup();

        vm.expectRevert(abi.encodeWithSelector(SpecificGroupStrategy.NoActiveGroups.selector));
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);
    }

    // ---------- When active groups and rebalanceWhenHealthChanged called -------

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_WhenActiveGroupsAndRebalanceWhenHealthChangedCalled_ShouldHaveStCeloUnhealthyStCeloInStrategy()
        public
    {
        _whenActiveGroupsAndRebalanceWhenHealthChangedCalled();

        mockAccount.setCeloForGroup(specificGroupAddress, deposit);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);

        GroupStCelo memory amounts = _stCeloInGroup(specificGroupAddress);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, 0);
        assertEq(amounts.unhealthy, deposit);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_WhenActiveGroupsAndRebalanceWhenHealthChangedCalled_ShouldScheduleTransfers()
        public
    {
        _whenActiveGroupsAndRebalanceWhenHealthChangedCalled();

        mockAccount.setCeloForGroup(specificGroupAddress, deposit);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(specificGroupAddress));
        _assertEqUints(values.fromVotes, _uints(deposit));
        _assertMembersAddresses(values.toGroups, _addresses(tail));
        _assertEqUints(values.toVotes, _uints(deposit));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_WhenActiveGroupsAndRebalanceWhenHealthChangedCalled_ShouldNotScheduleTransfersIfGroupDoesntHaveEnoughOfCelo()
        public
    {
        _whenActiveGroupsAndRebalanceWhenHealthChangedCalled();

        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(specificGroupAddress));
        _assertEqUints(values.fromVotes, _uints(0));
        _assertMembersAddresses(values.toGroups, new address[](0));
        _assertEqUints(values.toVotes, new uint256[](0));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_WhenActiveGroupsAndRebalanceWhenHealthChangedCalled_ShouldUpdateStCeloInDefaultStrategy()
        public
    {
        _whenActiveGroupsAndRebalanceWhenHealthChangedCalled();

        mockAccount.setCeloForGroup(specificGroupAddress, deposit);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);

        assertEq(mockDefaultStrategy.stCeloInGroup(tail), deposit);
    }

    // ------------------- When group becomes healthy again ---------------------

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_WhenActiveGroupsAndRebalanceWhenHealthChangedCalled_WhenGroupBecomesHealthyAgain_ShouldRemoveUnhealthyStCelo()
        public
    {
        _whenGroupBecomesHealthyAgain();

        GroupStCelo memory amounts = _stCeloInGroup(specificGroupAddress);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, 0);
        assertEq(amounts.unhealthy, 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_WhenActiveGroupsAndRebalanceWhenHealthChangedCalled_WhenGroupBecomesHealthyAgain_ShouldScheduleTransfers()
        public
    {
        _whenGroupBecomesHealthyAgain();

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(head));
        _assertEqUints(values.fromVotes, _uints(deposit));
        _assertMembersAddresses(values.toGroups, _addresses(specificGroupAddress));
        _assertEqUints(values.toVotes, _uints(deposit));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenGroupIsUnhealthy_WhenCeloDepositedInGroup_WhenActiveGroupsAndRebalanceWhenHealthChangedCalled_WhenGroupBecomesHealthyAgain_ShouldUpdateStCeloInDefaultStrategy()
        public
    {
        _whenGroupBecomesHealthyAgain();

        assertEq(mockDefaultStrategy.stCeloInGroup(tail), 0);
    }

    // =========================================================================
    //             When overflowing group is blocked -> When ratio 1:1
    // =========================================================================

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenRatio1To1_ShouldHaveBlockedGroup()
        public
    {
        _whenRatio1To1();

        assertTrue(specificGroupStrategy.isBlockedGroup(specificOverflowingGroup));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenRatio1To1_ShouldHaveStCeloUnhealthyStCeloInStrategy()
        public
    {
        _whenRatio1To1();

        GroupStCelo memory amounts = _stCeloInGroup(specificOverflowingGroup);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, DEPOSIT_OVER_CAPACITY);
        assertEq(amounts.unhealthy, firstGroupCapacity);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenRatio1To1_ShouldScheduleTransfers()
        public
    {
        _whenRatio1To1();

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(specificOverflowingGroup));
        _assertEqUints(values.fromVotes, _uints(firstGroupCapacity));
        _assertMembersAddresses(values.toGroups, _addresses(nextToTail));
        _assertEqUints(values.toVotes, _uints(firstGroupCapacity));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenRatio1To1_ShouldUpdateStCeloInDefaultStrategy()
        public
    {
        _whenRatio1To1();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), deposit);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenRatio1To1_WhenGroupBecomesUnblockedAgain_ShouldRemoveUnhealthyStCelo()
        public
    {
        _whenRatio1To1UnblockedAgain();

        GroupStCelo memory amounts = _stCeloInGroup(specificOverflowingGroup);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, DEPOSIT_OVER_CAPACITY);
        assertEq(amounts.unhealthy, 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenRatio1To1_WhenGroupBecomesUnblockedAgain_ShouldScheduleTransfers()
        public
    {
        _whenRatio1To1UnblockedAgain();

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(head));
        _assertEqUints(values.fromVotes, _uints(firstGroupCapacity));
        _assertMembersAddresses(values.toGroups, _addresses(specificOverflowingGroup));
        _assertEqUints(values.toVotes, _uints(firstGroupCapacity));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenRatio1To1_WhenGroupBecomesUnblockedAgain_ShouldUpdateStCeloInDefaultStrategy()
        public
    {
        _whenRatio1To1UnblockedAgain();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), DEPOSIT_OVER_CAPACITY);
    }

    // =========================================================================
    //     When overflowing group is blocked -> When there is more CELO than stCELO
    // =========================================================================

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldHaveBlockedGroup()
        public
    {
        _whenThereIsMoreCeloThanStCelo();

        assertTrue(specificGroupStrategy.isBlockedGroup(specificOverflowingGroup));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldHaveStCeloUnhealthyStCeloInStrategy()
        public
    {
        _whenThereIsMoreCeloThanStCelo();

        GroupStCelo memory amounts = _stCeloInGroup(specificOverflowingGroup);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, DEPOSIT_OVER_CAPACITY);
        assertEq(amounts.unhealthy, firstGroupCapacity);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldScheduleTransfers()
        public
    {
        _whenThereIsMoreCeloThanStCelo();

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(specificOverflowingGroup));
        _assertEqUints(values.fromVotes, _uints(firstGroupCapacity * 2));
        assertEq(values.toGroups.length, 1);
        assertEq(values.toVotes[0], firstGroupCapacity * 2);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldUpdateStCeloInDefaultStrategy()
        public
    {
        _whenThereIsMoreCeloThanStCelo();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), deposit);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_WhenGroupBecomesUnblockedAgain_ShouldRemoveUnhealthyStCelo()
        public
    {
        _whenThereIsMoreCeloThanStCeloUnblockedAgain();

        GroupStCelo memory amounts = _stCeloInGroup(specificOverflowingGroup);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, DEPOSIT_OVER_CAPACITY);
        assertEq(amounts.unhealthy, 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_WhenGroupBecomesUnblockedAgain_ShouldScheduleTransfers()
        public
    {
        _whenThereIsMoreCeloThanStCeloUnblockedAgain();

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(head));
        assertEq(values.fromVotes[0], firstGroupCapacity * 2);
        _assertMembersAddresses(values.toGroups, _addresses(specificOverflowingGroup));
        _assertEqUints(values.toVotes, _uints(firstGroupCapacity * 2));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_WhenGroupBecomesUnblockedAgain_ShouldUpdateStCeloInDefaultStrategy()
        public
    {
        _whenThereIsMoreCeloThanStCeloUnblockedAgain();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), DEPOSIT_OVER_CAPACITY);
    }

    // =========================================================================
    //     When overflowing group is blocked -> When there is less CELO than stCELO
    // =========================================================================

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldHaveBlockedGroup()
        public
    {
        _whenThereIsLessCeloThanStCelo();

        assertTrue(specificGroupStrategy.isBlockedGroup(specificOverflowingGroup));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldHaveStCeloUnhealthyStCeloInStrategy()
        public
    {
        _whenThereIsLessCeloThanStCelo();

        GroupStCelo memory amounts = _stCeloInGroup(specificOverflowingGroup);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, DEPOSIT_OVER_CAPACITY);
        assertEq(amounts.unhealthy, firstGroupCapacity);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldScheduleTransfers()
        public
    {
        _whenThereIsLessCeloThanStCelo();

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(specificOverflowingGroup));
        _assertEqUints(values.fromVotes, _uints(firstGroupCapacity / 2));
        assertEq(values.toGroups.length, 1);
        _assertMembersUints(values.toVotes, _uints(firstGroupCapacity / 2));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldUpdateStCeloInDefaultStrategy()
        public
    {
        _whenThereIsLessCeloThanStCelo();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), deposit);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_WhenGroupBecomesUnblockedAgain_ShouldRemoveUnhealthyStCelo()
        public
    {
        _whenThereIsLessCeloThanStCeloUnblockedAgain();

        GroupStCelo memory amounts = _stCeloInGroup(specificOverflowingGroup);
        assertEq(amounts.total, deposit);
        assertEq(amounts.overflow, DEPOSIT_OVER_CAPACITY);
        assertEq(amounts.unhealthy, 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_WhenGroupBecomesUnblockedAgain_ShouldScheduleTransfers()
        public
    {
        _whenThereIsLessCeloThanStCeloUnblockedAgain();

        TransferValues memory values = _lastTransferValues();
        _assertMembersAddresses(values.fromGroups, _addresses(head));
        assertEq(values.fromVotes[0], firstGroupCapacity / 2);
        _assertMembersAddresses(values.toGroups, _addresses(specificOverflowingGroup));
        _assertEqUints(values.toVotes, _uints(firstGroupCapacity / 2));
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceWhenHealthChanged_WhenOverflowingGroupIsBlocked_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_WhenGroupBecomesUnblockedAgain_ShouldUpdateStCeloInDefaultStrategy()
        public
    {
        _whenThereIsLessCeloThanStCeloUnblockedAgain();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), DEPOSIT_OVER_CAPACITY);
    }

    // =========================================================================
    //                       NESTED beforeEach BLOCKS
    // =========================================================================

    /// @dev beforeEach of describe("When group is unhealthy").
    function _whenGroupIsUnhealthy() private {
        revokeElectionOnMockValidatorGroupsAndUpdate(
            mockGroupHealth,
            _addresses(specificGroupAddress),
            true
        );
    }

    /// @dev beforeEach of describe("When Celo deposited in group").
    function _whenCeloDepositedInGroup() private {
        _whenGroupIsUnhealthy();

        deposit = 1 ether;
        electMockValidatorGroupsAndUpdate(mockGroupHealth, _addresses(specificGroupAddress));
        vm.prank(depositor);
        manager.changeStrategy(specificGroupAddress);
        vm.prank(depositor);
        manager.deposit{value: deposit}();
        revokeElectionOnMockValidatorGroupsAndUpdate(
            mockGroupHealth,
            _addresses(specificGroupAddress),
            true
        );
    }

    /// @dev beforeEach of describe("When active groups and rebalanceWhenHealthChanged called").
    function _whenActiveGroupsAndRebalanceWhenHealthChangedCalled() private {
        _whenCeloDepositedInGroup();

        _prepareOverflow();
        (tail, ) = mockDefaultStrategy.getGroupsTail();
    }

    /// @dev beforeEach of describe("When group becomes healthy again").
    function _whenGroupBecomesHealthyAgain() private {
        _whenActiveGroupsAndRebalanceWhenHealthChangedCalled();

        mockAccount.setCeloForGroup(specificGroupAddress, deposit);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);

        (head, ) = mockDefaultStrategy.getGroupsHead();
        electMockValidatorGroupsAndUpdate(mockGroupHealth, _addresses(specificGroupAddress));
        _updateGroupCelo();
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupAddress);
    }

    /// @dev Shared head of the three "When overflowing group is blocked" ratio blocks:
    ///      changes the strategy, prepares the overflow and deposits over the group capacity.
    function _depositOverFirstGroupCapacity() private {
        specificOverflowingGroup = groupAddresses[0];
        vm.prank(depositor);
        manager.changeStrategy(specificOverflowingGroup);

        _prepareOverflow();
        firstGroupCapacity = _receivableVotes(groupAddresses[0]);
        deposit = firstGroupCapacity + DEPOSIT_OVER_CAPACITY;

        vm.prank(depositor);
        manager.deposit{value: deposit}();
    }

    /// @dev beforeEach of describe("When ratio 1:1").
    function _whenRatio1To1() private {
        _depositOverFirstGroupCapacity();

        mockAccount.setCeloForGroup(specificOverflowingGroup, deposit);
        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificOverflowingGroup);
        (, nextToTail) = mockDefaultStrategy.getGroupsTail();
        specificGroupStrategy.rebalanceWhenHealthChanged(specificOverflowingGroup);
    }

    /// @dev beforeEach of describe("When group becomes unblocked again") under "When ratio 1:1".
    function _whenRatio1To1UnblockedAgain() private {
        _whenRatio1To1();

        (head, ) = mockDefaultStrategy.getGroupsHead();
        vm.prank(owner);
        specificGroupStrategy.unblockGroup(specificOverflowingGroup);
        _updateGroupCelo();
        specificGroupStrategy.rebalanceWhenHealthChanged(specificOverflowingGroup);
    }

    /// @dev beforeEach of describe("When there is more CELO than stCELO").
    function _whenThereIsMoreCeloThanStCelo() private {
        _depositOverFirstGroupCapacity();

        mockAccount.setTotalCelo(deposit * 2);
        _updateGroupCelo();
        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificOverflowingGroup);
        mockAccount.setCeloForGroup(specificOverflowingGroup, firstGroupCapacity * 2);

        specificGroupStrategy.rebalanceWhenHealthChanged(specificOverflowingGroup);
    }

    /// @dev beforeEach of describe("When group becomes unblocked again") under
    ///      "When there is more CELO than stCELO".
    function _whenThereIsMoreCeloThanStCeloUnblockedAgain() private {
        _whenThereIsMoreCeloThanStCelo();

        (head, ) = mockDefaultStrategy.getGroupsHead();
        vm.prank(owner);
        specificGroupStrategy.unblockGroup(specificOverflowingGroup);
        _updateGroupCelo();
        mockAccount.setCeloForGroup(specificOverflowingGroup, deposit);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificOverflowingGroup);
    }

    /// @dev beforeEach of describe("When there is less CELO than stCELO").
    function _whenThereIsLessCeloThanStCelo() private {
        _depositOverFirstGroupCapacity();

        mockAccount.setTotalCelo(deposit / 2);
        _updateGroupCelo();
        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificOverflowingGroup);
        mockAccount.setCeloForGroup(specificOverflowingGroup, deposit);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificOverflowingGroup);
    }

    /// @dev beforeEach of describe("When group becomes unblocked again") under
    ///      "When there is less CELO than stCELO".
    function _whenThereIsLessCeloThanStCeloUnblockedAgain() private {
        _whenThereIsLessCeloThanStCelo();

        (head, ) = mockDefaultStrategy.getGroupsHead();
        vm.prank(owner);
        specificGroupStrategy.unblockGroup(specificOverflowingGroup);
        _updateGroupCelo();
        specificGroupStrategy.rebalanceWhenHealthChanged(specificOverflowingGroup);
    }
}
