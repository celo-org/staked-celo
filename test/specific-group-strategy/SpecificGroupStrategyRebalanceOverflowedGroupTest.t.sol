// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./SpecificGroupStrategyTestBase.sol";

/**
 * @title SpecificGroupStrategyRebalanceOverflowedGroupTest
 * @notice Port of describe("#rebalanceOverflowedGroup()") (13 cases) of
 *         test-ts/specific_group_strategy.test.ts.
 * @dev Deviation: the original hardcoded `thirdGroupCapacity = 200.166666666666666666 CELO`,
 *      the receivable votes the ganache devchain left for groups[2] after `prepareOverflow`.
 *      The anvil devchain solves the vote amounts from the chain state, so the capacity is
 *      read from the Election contract instead of hardcoded.
 */
contract SpecificGroupStrategyRebalanceOverflowedGroupTest is SpecificGroupStrategyTestBase {
    /// @dev `thirdGroupCapacity` of the original test.
    uint256 internal thirdGroupCapacity;
    /// @dev `deposit` of describe("When third group overflowing").
    uint256 internal deposit;
    /// @dev `originalOverflow` of describe("When some capacity was freed and rebalanced").
    uint256 internal originalOverflow;

    function setUp() public {
        _setUpSpecificGroupStrategy();

        // beforeEach of describe("#rebalanceOverflowedGroup()")
        _prepareOverflow();
        thirdGroupCapacity = _receivableVotes(groupAddresses[2]);
    }

    // =========================================================================
    //                      #rebalanceOverflowedGroup()
    // =========================================================================

    function test_rebalanceOverflowedGroup_ShouldRevertWhenFromGroupIsNotOverflowing() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.GroupNotOverflowing.selector, groupAddresses[0]
            )
        );
        specificGroupStrategy.rebalanceOverflowedGroup(groupAddresses[0]);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_ShouldRevertWhenGroupIsOverflowingAndNoCapacityWasFreed()
        public
    {
        _whenThirdGroupOverflowing();

        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.GroupStillOverflowing.selector, groupAddresses[2]
            )
        );
        specificGroupStrategy.rebalanceOverflowedGroup(groupAddresses[2]);
    }

    // ---------------------------- When 1:1 -----------------------------------

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_When1To1_ShouldReturn0Overflow()
        public
    {
        _when1To1();

        GroupStCelo memory amounts = _stCeloInGroup(groupAddresses[2]);
        assertEq(amounts.overflow, 0);
        assertEq(amounts.total, deposit);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_When1To1_ShouldRemoveStCeloFromDefaultStrategy()
        public
    {
        _when1To1();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_When1To1_ShouldScheduleTransfersFromActiveGroups()
        public
    {
        _when1To1();

        _assertTransfersFromActiveGroups(originalOverflow);
    }

    // ------------------- When there is more CELO than stCELO ------------------

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldReturn0Overflow()
        public
    {
        _whenThereIsMoreCeloThanStCelo();

        GroupStCelo memory amounts = _stCeloInGroup(groupAddresses[2]);
        assertEq(amounts.overflow, 0);
        assertEq(amounts.total, deposit);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldRemoveStCeloFromDefaultStrategy()
        public
    {
        _whenThereIsMoreCeloThanStCelo();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldRemoveOverflowFromSpecificGroupStrategy()
        public
    {
        _whenThereIsMoreCeloThanStCelo();

        GroupStCelo memory amounts = _stCeloInGroup(groupAddresses[2]);
        assertEq(amounts.overflow, 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsMoreCeloThanStCelo_ShouldScheduleTransfersFromActiveGroups()
        public
    {
        _whenThereIsMoreCeloThanStCelo();

        _assertTransfersFromActiveGroups(originalOverflow * 2);
    }

    // ------------------- When there is less CELO than stCELO ------------------

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldReturn0Overflow()
        public
    {
        _whenThereIsLessCeloThanStCelo();

        GroupStCelo memory amounts = _stCeloInGroup(groupAddresses[2]);
        assertEq(amounts.overflow, 0);
        assertEq(amounts.total, deposit);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldRemoveStCeloFromDefaultStrategy()
        public
    {
        _whenThereIsLessCeloThanStCelo();

        assertEq(mockDefaultStrategy.totalStCeloInStrategy(), 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldRemoveOverflowFromSpecificGroupStrategy()
        public
    {
        _whenThereIsLessCeloThanStCelo();

        GroupStCelo memory amounts = _stCeloInGroup(groupAddresses[2]);
        assertEq(amounts.overflow, 0);
    }

    // solhint-disable-next-line max-line-length
    function test_rebalanceOverflowedGroup_WhenThirdGroupOverflowing_WhenSomeCapacityWasFreedAndRebalanced_WhenDifferentRatioOfCeloVsStCelo_WhenThereIsLessCeloThanStCelo_ShouldScheduleTransfersFromActiveGroups()
        public
    {
        _whenThereIsLessCeloThanStCelo();

        _assertTransfersFromActiveGroups(originalOverflow / 2);
    }

    // =========================================================================
    //                       NESTED beforeEach BLOCKS
    // =========================================================================

    /// @dev beforeEach of describe("When third group overflowing").
    function _whenThirdGroupOverflowing() private {
        deposit = 250 ether;
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[2]);
        vm.prank(depositor);
        manager.deposit{value: deposit}();

        (address[] memory scheduledGroups, uint256[] memory scheduledVotes) =
            mockAccount.getLastScheduledVotes();
        for (uint256 i = 0; i < scheduledGroups.length; i++) {
            mockAccount.setCeloForGroup(scheduledGroups[i], scheduledVotes[i]);
        }
    }

    /// @dev beforeEach of describe("When some capacity was freed and rebalanced").
    function _whenSomeCapacityWasFreedAndRebalanced() private {
        _whenThirdGroupOverflowing();

        _revokePending(voter, groupAddresses[2], thirdGroupCapacity);
        (, originalOverflow,) = specificGroupStrategy.getStCeloInGroup(groupAddresses[2]);
    }

    /// @dev beforeEach of describe("When 1:1").
    function _when1To1() private {
        _whenSomeCapacityWasFreedAndRebalanced();

        specificGroupStrategy.rebalanceOverflowedGroup(groupAddresses[2]);
    }

    /// @dev beforeEach of describe("When there is more CELO than stCELO").
    function _whenThereIsMoreCeloThanStCelo() private {
        _whenSomeCapacityWasFreedAndRebalanced();

        mockAccount.setTotalCelo(deposit * 2);
        _updateGroupCelo();
        mockAccount.setCeloForGroup(groupAddresses[2], 0);
        specificGroupStrategy.rebalanceOverflowedGroup(groupAddresses[2]);
    }

    /// @dev beforeEach of describe("When there is less CELO than stCELO").
    function _whenThereIsLessCeloThanStCelo() private {
        _whenSomeCapacityWasFreedAndRebalanced();

        mockAccount.setTotalCelo(deposit / 2);
        _updateGroupCelo();
        specificGroupStrategy.rebalanceOverflowedGroup(groupAddresses[2]);
    }

    // =========================================================================
    //                            SHARED ASSERTION
    // =========================================================================

    /// @dev it("should schedule transfers from active groups") of all three ratio blocks.
    function _assertTransfersFromActiveGroups(uint256 expectedMoved) private view {
        TransferValues memory values = _lastTransferValues();

        _assertMembersAddresses(values.fromGroups, _addresses(groupAddresses[0], groupAddresses[1]));
        assertEq(values.fromVotes[0] + values.fromVotes[1], expectedMoved);

        _assertMembersAddresses(values.toGroups, _addresses(groupAddresses[2]));
        _assertMembersUints(values.toVotes, _uints(expectedMoved));
    }
}
