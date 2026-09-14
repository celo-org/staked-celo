// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./SpecificGroupStrategyTestBase.sol";

/**
 * @title SpecificGroupStrategyBlockGroupTest
 * @notice Port of the describe blocks #blockGroup() (9) and #unblockGroup (4) of
 *         test-ts/specific_group_strategy.test.ts.
 */
contract SpecificGroupStrategyBlockGroupTest is SpecificGroupStrategyTestBase {
    /// @dev `specificGroupStrategy` of the original test: the group the depositor votes for.
    address internal specificGroup;
    /// @dev `specificGroupStrategyDeposit` of the original test.
    uint256 internal specificGroupDeposit;

    function setUp() public {
        _setUpSpecificGroupStrategy();
    }

    // =========================================================================
    //                             #blockGroup()
    // =========================================================================

    function test_blockGroup_RevertsWhenNoActiveGroups() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SpecificGroupStrategy.NoActiveGroups.selector));
        specificGroupStrategy.blockGroup(groupAddresses[3]);
    }

    function test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_AddedGroupToAllowedStrategies()
        public
    {
        _whenTheGroupIsAllowed();

        _assertEqAddresses(
            getDefaultGroups(DefaultStrategy(address(mockDefaultStrategy))),
            _addresses(groupAddresses[0], groupAddresses[1])
        );
        _assertEqAddresses(getSpecificGroups(specificGroupStrategy), _addresses(specificGroup));
    }

    // solhint-disable-next-line max-line-length
    function test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_AddsTheGroupToBlockedGroupsArray()
        public
    {
        _whenTheGroupIsAllowed();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificGroup);

        _assertMembersAddresses(
            getDefaultGroups(DefaultStrategy(address(mockDefaultStrategy))),
            _addresses(groupAddresses[0], groupAddresses[1])
        );
        _assertEqAddresses(getSpecificGroups(specificGroupStrategy), _addresses(specificGroup));
        _assertEqAddresses(
            getBlockedSpecificGroupStrategies(specificGroupStrategy),
            _addresses(specificGroup)
        );
    }

    function test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_EmitsAStrategyBlockedEvent()
        public
    {
        _whenTheGroupIsAllowed();

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit GroupBlocked(specificGroup);
        specificGroupStrategy.blockGroup(specificGroup);
    }

    // solhint-disable-next-line max-line-length
    function test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_ShouldAddBlockedStrategyToBlockedStrategies()
        public
    {
        _whenTheGroupIsAllowed();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificGroup);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroup);

        _assertMembersAddresses(
            getBlockedSpecificGroupStrategies(specificGroupStrategy),
            _addresses(specificGroup)
        );
    }

    // solhint-disable-next-line max-line-length
    function test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_ShouldUpdateAccountingCorrectly()
        public
    {
        _whenTheGroupIsAllowed();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificGroup);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroup);

        GroupStCelo memory amounts = _stCeloInGroup(specificGroup);
        assertEq(amounts.total, specificGroupDeposit);
        assertEq(amounts.overflow, 0);
        assertEq(amounts.unhealthy, specificGroupDeposit);
    }

    // solhint-disable-next-line max-line-length
    function test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_RevertsWhenBlockingAlreadyBlockedStrategy()
        public
    {
        _whenTheGroupIsAllowed();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[3]);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.GroupAlreadyBlocked.selector,
                groupAddresses[3]
            )
        );
        specificGroupStrategy.blockGroup(groupAddresses[3]);
    }

    function test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_CannotBeCalledByANonOwner()
        public
    {
        _whenTheGroupIsAllowed();

        vm.prank(nonOwner);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        specificGroupStrategy.blockGroup(specificGroup);
    }

    // solhint-disable-next-line max-line-length
    function test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_ShouldScheduleTransfersToDefaultStrategy()
        public
    {
        _whenTheGroupIsAllowed();

        (address tail, ) = mockDefaultStrategy.getGroupsTail();

        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificGroup);
        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroup);

        TransferValues memory values = _lastTransferValues();
        _assertEqAddresses(values.fromGroups, _addresses(specificGroup));
        _assertEqUints(values.fromVotes, _uints(specificGroupDeposit));
        _assertEqAddresses(values.toGroups, _addresses(tail));
        _assertMembersUints(values.toVotes, _uints(specificGroupDeposit));
    }

    /// @dev beforeEach of describe("When 2 active groups").
    function _when2ActiveGroups() private {
        specificGroup = groupAddresses[2];
        _activateGroups(2);
    }

    /// @dev beforeEach of describe("when the group is allowed").
    function _whenTheGroupIsAllowed() private {
        _when2ActiveGroups();

        specificGroupDeposit = 1 ether;
        mockAccount.setCeloForGroup(specificGroup, specificGroupDeposit);
        vm.prank(depositor);
        manager.changeStrategy(specificGroup);
        vm.prank(depositor);
        manager.deposit{value: specificGroupDeposit}();
    }

    // =========================================================================
    //                            #unblockGroup
    // =========================================================================

    function test_unblockGroup_ShouldRevertWhenUnhealthyGroup() public {
        deregisterValidatorGroup(groupAddresses[0]);
        mockGroupHealth.updateGroupHealth(groupAddresses[0]);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.GroupNotEligible.selector,
                groupAddresses[0]
            )
        );
        specificGroupStrategy.unblockGroup(groupAddresses[0]);
    }

    function test_unblockGroup_ShouldRevertWhenNotBlockedStrategy() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpecificGroupStrategy.FailedToUnblockGroup.selector,
                groupAddresses[0]
            )
        );
        specificGroupStrategy.unblockGroup(groupAddresses[0]);
    }

    function test_unblockGroup_WhenTheGroupIsBlocked_ShouldHaveBlockedStrategy() public {
        _whenTheGroupIsBlocked();

        _assertMembersAddresses(
            getBlockedSpecificGroupStrategies(specificGroupStrategy),
            _addresses(specificGroup)
        );
    }

    function test_unblockGroup_WhenTheGroupIsBlocked_ShouldAllowToUnblockStrategy() public {
        _whenTheGroupIsBlocked();

        vm.prank(owner);
        specificGroupStrategy.unblockGroup(specificGroup);

        _assertMembersAddresses(
            getBlockedSpecificGroupStrategies(specificGroupStrategy),
            new address[](0)
        );
    }

    /// @dev beforeEach of describe("when the group is blocked").
    function _whenTheGroupIsBlocked() private {
        specificGroup = groupAddresses[2];
        _activateGroups(2);

        specificGroupDeposit = 1 ether;
        mockAccount.setCeloForGroup(specificGroup, specificGroupDeposit);
        vm.prank(depositor);
        manager.changeStrategy(specificGroup);
        vm.prank(depositor);
        manager.deposit{value: specificGroupDeposit}();
        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificGroup);
    }
}
