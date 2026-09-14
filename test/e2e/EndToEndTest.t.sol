// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./EndToEndTestBase.sol";

/**
 * @title EndToEndTest
 * @notice Port of test-ts/end-to-end.test.ts ("e2e").
 */
contract EndToEndTest is EndToEndTestBase {
    uint256 internal constant REWARDS_GROUP_0 = 100 ether;
    uint256 internal constant REWARDS_GROUP_1 = 2 ether;
    uint256 internal constant REWARDS_GROUP_2 = 3.5 ether;

    function test_DepositAndWithdraw() public {
        uint256 amountOfCeloToDeposit = 0.01 ether;
        deposit(depositor0, amountOfCeloToDeposit);
        deposit(depositor1, amountOfCeloToDeposit);

        assertEq(stakedCelo.balanceOf(depositor1), amountOfCeloToDeposit);

        activateAndVote();
        mineToNextEpoch();
        activateAndVote();

        distributeAllRewards();
        rebalanceDefaultGroups(defaultStrategy);
        rebalanceGroups(manager, specificGroupStrategy, defaultStrategy);
        revoke();
        activateAndVote();

        vm.prank(depositor1);
        manager.withdraw(amountOfCeloToDeposit);
        assertEq(stakedCelo.balanceOf(depositor1), 0);

        withdraw(depositor1);

        uint256 depositor1BeforeWithdrawalBalance = depositor1.balance;

        timeTravelUnlockingPeriod();

        finishPendingWithdrawals(depositor1);

        deposit(depositor2, amountOfCeloToDeposit);

        assertEq(
            stakedCelo.balanceOf(depositor2),
            manager.toStakedCelo(amountOfCeloToDeposit)
        );

        assertEq(stakedCelo.balanceOf(depositor0), amountOfCeloToDeposit);

        uint256 depositor1AfterWithdrawalBalance = depositor1.balance;
        assertTrue(depositor1AfterWithdrawalBalance > depositor1BeforeWithdrawalBalance);

        uint256 rewardsReceived = depositor1AfterWithdrawalBalance -
            depositor1BeforeWithdrawalBalance -
            amountOfCeloToDeposit;

        assertEq(rewardsReceived, (REWARDS_GROUP_0 + REWARDS_GROUP_1 + REWARDS_GROUP_2) / 2);
    }

    function distributeAllRewards() internal {
        distributeRewards(1, REWARDS_GROUP_0);
        distributeRewards(1, REWARDS_GROUP_1);
        distributeRewards(2, REWARDS_GROUP_2);
    }
}
