// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./SpecificGroupStrategyTestBase.sol";

/**
 * @title SpecificGroupStrategyDistributionTest
 * @notice Port of the vote distribution and accounting describe blocks of
 *         test-ts/specific_group_strategy.test.ts:
 *         #generateWithdrawalVoteDistribution (2), #generateDepositVoteDistribution (2)
 *         and #updateGroupStCelo (3).
 */
contract SpecificGroupStrategyDistributionTest is SpecificGroupStrategyTestBase {
    function setUp() public {
        _setUpSpecificGroupStrategy();
    }

    // =========================================================================
    //                 #generateWithdrawalVoteDistribution()
    // =========================================================================

    function test_generateWithdrawalVoteDistribution_CannotBeCalledByANonManagerAddress() public {
        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        specificGroupStrategy.generateWithdrawalVoteDistribution(nonVote, 10, 10, false);
    }

    // solhint-disable-next-line max-line-length
    function test_generateWithdrawalVoteDistribution_WhenCalledThroughManagerWithdrawWithSpecificStrategy_EmitsWithdrawalVoteDistributionGeneratedEvent()
        public
    {
        _whenCalledThroughManagerWithdrawWithSpecificStrategy();

        vm.expectEmit(false, false, false, false);
        emit WithdrawalVoteDistributionGenerated(
            ADDRESS_ZERO,
            new address[](0),
            new uint256[](0)
        );
        vm.prank(depositor);
        manager.withdraw(0.5 ether);
    }

    /// @dev beforeEach of describe("when called through manager withdraw with specific strategy").
    function _whenCalledThroughManagerWithdrawWithSpecificStrategy() private {
        _activateGroups(2);

        mockAccount.setCeloForGroup(groupAddresses[2], 1 ether);
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[2]);
        vm.prank(depositor);
        manager.deposit{value: 1 ether}();
        _updateGroupCelo();
    }

    // =========================================================================
    //                  #generateDepositVoteDistribution()
    // =========================================================================

    function test_generateDepositVoteDistribution_CannotBeCalledByANonManagerAddress() public {
        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        specificGroupStrategy.generateDepositVoteDistribution(nonVote, 10, 10);
    }

    // solhint-disable-next-line max-line-length
    function test_generateDepositVoteDistribution_WhenCalledThroughManagerDepositWithSpecificStrategy_EmitsDepositVoteDistributionGeneratedEvent()
        public
    {
        _whenCalledThroughManagerDepositWithSpecificStrategy();

        vm.expectEmit(false, false, false, false);
        emit DepositVoteDistributionGenerated(ADDRESS_ZERO, new address[](0), new uint256[](0));
        vm.prank(depositor);
        manager.deposit{value: 1 ether}();
    }

    /// @dev beforeEach of describe("when called through manager deposit with specific strategy").
    function _whenCalledThroughManagerDepositWithSpecificStrategy() private {
        _activateGroups(2);

        mockAccount.setCeloForGroup(groupAddresses[2], 1 ether);
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[2]);
    }

    // =========================================================================
    //                          #updateGroupStCelo
    // =========================================================================

    function test_updateGroupStCelo_ShouldRevertWhenNotOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        specificGroupStrategy.updateGroupStCelo(groupAddresses[0], 100, true);
    }

    function test_updateGroupStCelo_ShouldAddGroupStCelo() public {
        vm.prank(owner);
        specificGroupStrategy.updateGroupStCelo(groupAddresses[0], 100, true);

        assertEq(specificGroupStrategy.stCeloInGroup(groupAddresses[0]), 100);
        assertEq(specificGroupStrategy.totalStCeloLocked(), 100);
    }

    function test_updateGroupStCelo_ShouldSubtractGroupStCelo() public {
        vm.prank(owner);
        specificGroupStrategy.updateGroupStCelo(groupAddresses[0], 100, true);
        vm.prank(owner);
        specificGroupStrategy.updateGroupStCelo(groupAddresses[0], 50, false);

        assertEq(specificGroupStrategy.stCeloInGroup(groupAddresses[0]), 50);
        assertEq(specificGroupStrategy.totalStCeloLocked(), 50);
    }
}
