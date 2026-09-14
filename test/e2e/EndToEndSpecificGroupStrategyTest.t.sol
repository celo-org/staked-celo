// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./EndToEndTestBase.sol";

/**
 * @title EndToEndSpecificGroupStrategyTest
 * @notice Port of test-ts/end-to-end-specific-group-strategy.test.ts
 *         ("e2e specific group strategy voting").
 */
contract EndToEndSpecificGroupStrategyTest is EndToEndTestBase {
    uint256 internal constant REWARDS_GROUP_0 = 10 ether;
    uint256 internal constant REWARDS_GROUP_1 = 20 ether;
    uint256 internal constant REWARDS_GROUP_2 = 30 ether;
    uint256 internal constant REWARDS_GROUP_5 = 10 ether;

    address internal specificGroupStrategyDifferentFromActive;
    address internal specificGroupStrategySameAsActive;
    address internal specificGroupThatWillBeUnhealthy;

    /// @dev Kept in storage so the withdrawal expectations do not exhaust the stack.
    mapping(address => uint256) internal expectedCeloToBeWithdrawn;
    mapping(address => uint256) internal balanceBeforeWithdrawal;

    function setUp() public override {
        super.setUp();
        specificGroupStrategyDifferentFromActive = groups[5];
        specificGroupStrategySameAsActive = groups[0];
        specificGroupThatWillBeUnhealthy = groups[7];
    }

    /// @dev groups[5] and groups[7] are elected on top of the activated groups.
    function _groupsToElect() internal view override returns (address[] memory) {
        return _activatedGroupsPlus(groups[5], groups[7]);
    }

    function test_DepositRebalanceTransferAndWithdraw() public {
        uint256 amountOfCeloToDeposit = 1 ether;

        vm.prank(depositor1);
        manager.changeStrategy(specificGroupStrategyDifferentFromActive);
        vm.prank(depositor2);
        manager.changeStrategy(specificGroupStrategySameAsActive);
        vm.prank(depositor4);
        manager.changeStrategy(specificGroupStrategySameAsActive);

        expectSumOfExpectedAndRealCeloInGroupsToEqual();

        deposit(depositor0, amountOfCeloToDeposit);
        deposit(depositor1, amountOfCeloToDeposit);
        deposit(depositor4, amountOfCeloToDeposit);
        deposit(depositor5, amountOfCeloToDeposit);

        expectSumOfExpectedAndRealCeloInGroupsToEqual();

        activateAndVote();
        mineToNextEpoch();
        activateAndVote();

        _transferStCelo(amountOfCeloToDeposit / 2);

        expectSumOfExpectedAndRealCeloInGroupsToEqual();

        expectStCeloBalance(depositor0, amountOfCeloToDeposit / 2);
        expectStCeloBalance(depositor1, amountOfCeloToDeposit);
        expectStCeloBalance(depositor3, amountOfCeloToDeposit);
        expectStCeloBalance(depositor4, amountOfCeloToDeposit / 2);

        rebalanceAllAndActivate();

        activateAndVote();
        mineToNextEpoch();
        activateAndVote();
        distributeAllRewards();
        expectSumOfExpectedAndRealCeloInGroupsToEqual();

        rebalanceAllAndActivate();

        _recordExpectedCelo(depositor0);
        _recordExpectedCelo(depositor1);
        _recordExpectedCelo(depositor3);
        _recordExpectedCelo(depositor4);

        vm.prank(depositor0);
        manager.withdraw(amountOfCeloToDeposit / 2);
        vm.prank(depositor1);
        manager.withdraw(amountOfCeloToDeposit);
        vm.prank(depositor3);
        manager.withdraw(amountOfCeloToDeposit);
        vm.prank(depositor4);
        manager.withdraw(amountOfCeloToDeposit / 2);

        expectStCeloBalance(depositor1, 0);

        balanceBeforeWithdrawal[depositor0] = depositor0.balance;
        balanceBeforeWithdrawal[depositor1] = depositor1.balance;
        balanceBeforeWithdrawal[depositor3] = depositor3.balance;
        balanceBeforeWithdrawal[depositor4] = depositor4.balance;

        _withdrawAndFinish(depositor0);
        _withdrawAndFinish(depositor1);
        _withdrawAndFinish(depositor3);
        _withdrawAndFinish(depositor4);

        assertEq(1 ether, stakedCelo.totalSupply());
        assertEq(manager.toCelo(1 ether), account.getTotalCelo());

        deposit(depositor2, amountOfCeloToDeposit);
        expectStCeloBalance(depositor2, manager.toStakedCelo(amountOfCeloToDeposit));

        _expectWithdrawnCelo(depositor0);
        _expectWithdrawnCelo(depositor1);
        _expectWithdrawnCelo(depositor3);
        _expectWithdrawnCelo(depositor4);

        // healthy -> unhealthy -> healthy
        _healthyUnhealthyHealthy(amountOfCeloToDeposit);
    }

    /// @dev The five stCELO transfers of the original test.
    function _transferStCelo(uint256 half) private {
        // default strategy -> default strategy
        vm.prank(depositor0);
        stakedCelo.transfer(depositor3, half);
        // specificGroupStrategyDifferentFromActive -> default strategy
        vm.prank(depositor1);
        stakedCelo.transfer(depositor3, half);
        // specificGroupStrategySameAsActive -> default strategy
        vm.prank(depositor4);
        stakedCelo.transfer(depositor3, half);
        // specificGroupStrategySameAsActive -> specificGroupStrategyDifferentFromActive
        vm.prank(depositor4);
        stakedCelo.transfer(depositor1, half);
        // default strategy -> specificGroupStrategySameAsActive
        vm.prank(depositor3);
        stakedCelo.transfer(depositor4, half);
    }

    function _healthyUnhealthyHealthy(uint256 amountOfCeloToDeposit) private {
        vm.prank(depositor6);
        manager.changeStrategy(specificGroupThatWillBeUnhealthy);
        deposit(depositor6, amountOfCeloToDeposit);
        assertEq(
            account.scheduledVotesForGroup(specificGroupThatWillBeUnhealthy),
            amountOfCeloToDeposit
        );

        address[] memory unhealthyGroup = new address[](1);
        unhealthyGroup[0] = specificGroupThatWillBeUnhealthy;
        revokeElectionOnMockValidatorGroupsAndUpdate(groupHealthMock, unhealthyGroup, true);

        specificGroupStrategy.rebalanceWhenHealthChanged(specificGroupThatWillBeUnhealthy);
        deposit(depositor6, amountOfCeloToDeposit);
        assertInRange(account.scheduledVotesForGroup(specificGroupThatWillBeUnhealthy), 0, 1);

        electMockValidatorGroupsAndUpdate(groupHealthMock, _groupsToElect());
        deposit(depositor6, amountOfCeloToDeposit);
        assertInRange(
            account.scheduledVotesForGroup(specificGroupThatWillBeUnhealthy),
            amountOfCeloToDeposit,
            1
        );
    }

    function _recordExpectedCelo(address depositor) private {
        expectedCeloToBeWithdrawn[depositor] = manager.toCelo(stakedCelo.balanceOf(depositor));
    }

    /// @dev The ACCOUNT_WITHDRAW task plus the unlocking period and the pending withdrawals.
    function _withdrawAndFinish(address beneficiary) private {
        withdraw(beneficiary);
        timeTravelUnlockingPeriod();
        finishPendingWithdrawalForAccount(beneficiary);
    }

    function _expectWithdrawnCelo(address depositor) private view {
        assertInRange(
            expectedCeloToBeWithdrawn[depositor],
            depositor.balance - balanceBeforeWithdrawal[depositor],
            10
        );
    }

    function finishPendingWithdrawalForAccount(address beneficiary) internal {
        (, uint256[] memory timestamps) = account.getPendingWithdrawals(beneficiary);
        require(timestamps.length > 0, "There are no pending withdrawals for account");
        finishPendingWithdrawals(beneficiary);
    }

    function distributeAllRewards() internal {
        distributeRewards(0, REWARDS_GROUP_0);
        distributeRewards(1, REWARDS_GROUP_1);
        distributeRewards(2, REWARDS_GROUP_2);
        distributeRewards(5, REWARDS_GROUP_5);
    }

    function expectStCeloBalance(address depositor, uint256 expectedAmount) internal view {
        assertEq(expectedAmount, stakedCelo.balanceOf(depositor));
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
