// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#scheduleTransfer()")`.
contract AccountScheduleTransferTest is AccountTestBase {
    uint256 private constant ORIGINAL_GROUP_AMOUNT = 100;
    uint256 private constant AMOUNT_TRANSFERRED = 30;

    // =========================================================================
    //                          TOP-LEVEL CASES
    // =========================================================================

    function test_scheduleTransfer_ShouldRevertWhenNotCalledByManager() public {
        address[] memory groups = _allGroups();
        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        account.scheduleTransfer(groups, _amounts(100, 30, 70), groups, _amounts(30, 70, 100));
    }

    function test_scheduleTransfer_ShouldRevertWhenIncorrectVoteSum() public {
        address[] memory groups = _allGroups();
        vm.prank(managerSigner);
        vm.expectRevert(
            abi.encodeWithSelector(Account.NotEnoughCeloInGroup.selector, groupAddresses[0], 100, 0)
        );
        account.scheduleTransfer(groups, _amounts(100, 30, 80), groups, _amounts(30, 70, 100));
    }

    function test_scheduleTransfer_ShouldRevertWhenIncorrectVoteSum2() public {
        address[] memory groups = _allGroups();
        vm.prank(managerSigner);
        vm.expectRevert(
            abi.encodeWithSelector(Account.NotEnoughCeloInGroup.selector, groupAddresses[0], 100, 0)
        );
        account.scheduleTransfer(groups, _amounts(100, 30, 60), groups, _amounts(30, 70, 100));
    }

    // =========================================================================
    //                  When group has activated votes
    // =========================================================================

    function _setupGroupWithActivatedVotes() private {
        _scheduleVotes(groupAddresses[0], ORIGINAL_GROUP_AMOUNT);
        _activateAndVote(groupAddresses[0]);
    }

    function test_scheduleTransfer_WhenGroupHasActivatedVotes_GroupShouldHaveInitialAmount()
        public
    {
        _setupGroupWithActivatedVotes();
        assertEq(account.getCeloForGroup(groupAddresses[0]), ORIGINAL_GROUP_AMOUNT);
    }

    // ---- When moving amount to second group ----

    function _setupMovedToSecondGroup() private {
        _setupGroupWithActivatedVotes();
        _scheduleTransfer(groupAddresses[0], groupAddresses[1], AMOUNT_TRANSFERRED);
    }

    function test_scheduleTransfer_WhenGroupHasActivatedVotes_WhenMovingAmountToSecondGroup_ShouldReturnCorrectAmountForOriginalGroup()
        public
    {
        _setupMovedToSecondGroup();
        assertEq(
            account.getCeloForGroup(groupAddresses[0]), ORIGINAL_GROUP_AMOUNT - AMOUNT_TRANSFERRED
        );
    }

    function test_scheduleTransfer_WhenGroupHasActivatedVotes_WhenMovingAmountToSecondGroup_ShouldReturnCorrectAmountForReceivingGroup()
        public
    {
        _setupMovedToSecondGroup();
        assertEq(account.getCeloForGroup(groupAddresses[1]), AMOUNT_TRANSFERRED);
    }

    function test_scheduleTransfer_WhenGroupHasActivatedVotes_WhenMovingAmountToSecondGroup_ShouldReturnCorrectAmountWhenMovingBackToOriginalGroup()
        public
    {
        _setupMovedToSecondGroup();
        uint256 amountTransferred2 = 15;
        _scheduleTransfer(groupAddresses[1], groupAddresses[0], amountTransferred2);

        assertEq(
            account.getCeloForGroup(groupAddresses[0]),
            ORIGINAL_GROUP_AMOUNT - AMOUNT_TRANSFERRED + amountTransferred2
        );
        assertEq(
            account.getCeloForGroup(groupAddresses[1]), AMOUNT_TRANSFERRED - amountTransferred2
        );
    }

    function test_scheduleTransfer_WhenGroupHasActivatedVotes_WhenMovingAmountToSecondGroup_ShouldReturnCorrectAmountWhenMovingToThirdGroup()
        public
    {
        _setupMovedToSecondGroup();
        uint256 amountTransferred2 = 15;
        _scheduleTransfer(groupAddresses[1], groupAddresses[2], amountTransferred2);

        assertEq(
            account.getCeloForGroup(groupAddresses[1]), AMOUNT_TRANSFERRED - amountTransferred2
        );
        assertEq(account.getCeloForGroup(groupAddresses[2]), amountTransferred2);
    }

    // ---- When transferring to multiple groups ----

    function _setupTransferredToMultipleGroups() private {
        _setupGroupWithActivatedVotes();
        _scheduleTransfer(
            _addrs(groupAddresses[0]),
            _amounts(AMOUNT_TRANSFERRED),
            _addrs(groupAddresses[1], groupAddresses[2]),
            _amounts(AMOUNT_TRANSFERRED / 2, AMOUNT_TRANSFERRED / 2)
        );
    }

    function test_scheduleTransfer_WhenGroupHasActivatedVotes_WhenTransferringToMultipleGroups_ShouldReturnCorrectAmountForOriginalGroup()
        public
    {
        _setupTransferredToMultipleGroups();
        assertEq(
            account.getCeloForGroup(groupAddresses[0]), ORIGINAL_GROUP_AMOUNT - AMOUNT_TRANSFERRED
        );
    }

    function test_scheduleTransfer_WhenGroupHasActivatedVotes_WhenTransferringToMultipleGroups_ShouldReturnCorrectAmountForReceivingGroups()
        public
    {
        _setupTransferredToMultipleGroups();
        assertEq(account.getCeloForGroup(groupAddresses[1]), AMOUNT_TRANSFERRED / 2);
        assertEq(account.getCeloForGroup(groupAddresses[2]), AMOUNT_TRANSFERRED / 2);
    }

    function test_scheduleTransfer_WhenGroupHasActivatedVotes_ShouldRevertWhenTransferringMoreThenCurrentGroupHas()
        public
    {
        _setupGroupWithActivatedVotes();
        uint256 tooMuch = ORIGINAL_GROUP_AMOUNT * 2;
        vm.prank(managerSigner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Account.NotEnoughCeloInGroup.selector,
                groupAddresses[0],
                tooMuch,
                ORIGINAL_GROUP_AMOUNT
            )
        );
        account.scheduleTransfer(
            _addrs(groupAddresses[0]),
            _amounts(tooMuch),
            _addrs(groupAddresses[1]),
            _amounts(tooMuch)
        );
    }

    // =========================================================================
    //             When multiple groups have activated votes
    // =========================================================================

    function _setupTwoGroupsWithActivatedVotes() private {
        _scheduleVotes(groupAddresses[0], ORIGINAL_GROUP_AMOUNT);
        _scheduleVotes(groupAddresses[1], ORIGINAL_GROUP_AMOUNT);
        _activateAndVote(groupAddresses[0]);
        _activateAndVote(groupAddresses[1]);
    }

    // ---- When transferring from multiple groups to one group ----

    function _setupTransferredFromMultipleToOne() private {
        _setupTwoGroupsWithActivatedVotes();
        _scheduleTransfer(
            _addrs(groupAddresses[0], groupAddresses[1]),
            _amounts(AMOUNT_TRANSFERRED, AMOUNT_TRANSFERRED),
            _addrs(groupAddresses[2]),
            _amounts(AMOUNT_TRANSFERRED * 2)
        );
    }

    function test_scheduleTransfer_WhenMultipleGroupsHaveActivatedVotes_WhenTransferringFromMultipleGroupsToOneGroup_ShouldReturnCorrectAmountForOriginalGroups()
        public
    {
        _setupTransferredFromMultipleToOne();
        assertEq(
            account.getCeloForGroup(groupAddresses[0]), ORIGINAL_GROUP_AMOUNT - AMOUNT_TRANSFERRED
        );
        assertEq(
            account.getCeloForGroup(groupAddresses[1]), ORIGINAL_GROUP_AMOUNT - AMOUNT_TRANSFERRED
        );
    }

    function test_scheduleTransfer_WhenMultipleGroupsHaveActivatedVotes_WhenTransferringFromMultipleGroupsToOneGroup_ShouldReturnCorrectAmountForReceivingGroup()
        public
    {
        _setupTransferredFromMultipleToOne();
        assertEq(account.getCeloForGroup(groupAddresses[2]), AMOUNT_TRANSFERRED * 2);
    }

    // ---- When transferring from multiple groups to multiple group ----

    /// @dev The new group is registered inside the `beforeEach` of the original.
    function _setupTransferredFromMultipleToMultiple() private returns (address newValidatorGroup) {
        _setupTwoGroupsWithActivatedVotes();
        newValidatorGroup = registerNewValidatorGroup();
        _scheduleTransfer(
            _addrs(groupAddresses[0], groupAddresses[1]),
            _amounts(AMOUNT_TRANSFERRED, AMOUNT_TRANSFERRED),
            _addrs(groupAddresses[2], newValidatorGroup),
            _amounts(AMOUNT_TRANSFERRED, AMOUNT_TRANSFERRED)
        );
    }

    function test_scheduleTransfer_WhenMultipleGroupsHaveActivatedVotes_WhenTransferringFromMultipleGroupsToMultipleGroup_ShouldReturnCorrectAmountForReceivingGroup()
        public
    {
        address newValidatorGroup = _setupTransferredFromMultipleToMultiple();
        assertEq(account.getCeloForGroup(groupAddresses[2]), AMOUNT_TRANSFERRED);
        assertEq(account.getCeloForGroup(newValidatorGroup), AMOUNT_TRANSFERRED);
    }

    function test_scheduleTransfer_WhenMultipleGroupsHaveActivatedVotes_WhenTransferringFromMultipleGroupsToMultipleGroup_ShouldReturnCorrectAmountForOriginalGroups()
        public
    {
        _setupTransferredFromMultipleToMultiple();
        assertEq(
            account.getCeloForGroup(groupAddresses[0]), ORIGINAL_GROUP_AMOUNT - AMOUNT_TRANSFERRED
        );
        assertEq(
            account.getCeloForGroup(groupAddresses[1]), ORIGINAL_GROUP_AMOUNT - AMOUNT_TRANSFERRED
        );
    }
}
