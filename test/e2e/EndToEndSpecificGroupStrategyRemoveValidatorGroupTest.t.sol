// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./EndToEndTestBase.sol";

/**
 * @title EndToEndSpecificGroupStrategyRemoveValidatorGroupTest
 * @notice Port of test-ts/end-to-end-specific-group-strategy-remove-validator-group.test.ts
 *         ("e2e specific group strategy voting removed validator group").
 */
contract EndToEndSpecificGroupStrategyRemoveValidatorGroupTest is EndToEndTestBase {
    uint256 internal constant REWARDS_GROUP_0 = 10 ether;
    uint256 internal constant REWARDS_GROUP_1 = 20 ether;
    uint256 internal constant REWARDS_GROUP_2 = 30 ether;
    uint256 internal constant REWARDS_GROUP_5 = 10 ether;

    address internal specificGroupStrategyDifferentFromActive;

    function setUp() public override {
        super.setUp();
        specificGroupStrategyDifferentFromActive = groups[5];
    }

    /// @dev groups[5] is elected on MockGroupHealth on top of the activated groups.
    function _groupsToElect() internal view override returns (address[] memory) {
        return _activatedGroupsPlus(groups[5]);
    }

    function test_DepositRebalanceTransferAndWithdraw() public {
        uint256 amountOfCeloToDeposit = 1 ether;

        vm.prank(depositor1);
        manager.changeStrategy(specificGroupStrategyDifferentFromActive);

        deposit(depositor1, amountOfCeloToDeposit);
        deposit(depositor2, amountOfCeloToDeposit);

        expectSumOfExpectedAndRealCeloInGroupsToEqual();

        activateAndVote();
        mineToNextEpoch();
        activateAndVote();

        expectSumOfExpectedAndRealCeloInGroupsToEqual();

        assertEq(stakedCelo.balanceOf(depositor1), amountOfCeloToDeposit);

        rebalanceAllAndActivate();

        activateAndVote();
        mineToNextEpoch();
        activateAndVote();
        distributeAllRewards();
        expectSumOfExpectedAndRealCeloInGroupsToEqual();

        deregisterValidatorGroup(specificGroupStrategyDifferentFromActive);

        specificGroupStrategy.getStCeloInGroup(specificGroupStrategyDifferentFromActive);

        groupHealthMock.updateGroupHealth(specificGroupStrategyDifferentFromActive);

        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupStrategyDifferentFromActive);

        expectSumOfExpectedAndRealCeloInGroupsToEqual();

        rebalanceAllAndActivate();
    }

    function distributeAllRewards() internal {
        distributeRewards(0, REWARDS_GROUP_0);
        distributeRewards(1, REWARDS_GROUP_1);
        distributeRewards(2, REWARDS_GROUP_2);
        distributeRewards(5, REWARDS_GROUP_5);
    }

    function expectSumOfExpectedAndRealCeloInGroupsToEqual() internal view {
        address[] memory allGroups = getGroupsOfAllStrategies(
            defaultStrategy,
            specificGroupStrategy
        );
        ExpectVsReal[] memory expectedVsReal = getRealVsExpectedCeloForGroups(manager, allGroups);

        uint256 expectedSum = 0;
        uint256 realSum = 0;
        for (uint256 i = 0; i < expectedVsReal.length; i++) {
            expectedSum += expectedVsReal[i].expected;
            realSum += expectedVsReal[i].real;
        }
        assertInRange(realSum, expectedSum, 10);
    }
}
