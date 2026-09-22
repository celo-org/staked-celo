// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/DevchainHelper.sol";
import "./helpers/deploy/FullTestManagerDeployHelper.sol";

/**
 * @title ManagerStrategyChangeTest
 * @notice Port of the Hardhat era test-ts/manager-strategy-change.test.ts
 *         (`describe("Manager strategy change: delayed transfer")`).
 * @dev Two validator groups with one validator each are registered against the real Celo core
 *      contracts of the devchain, elected on MockGroupHealth and activated in DefaultStrategy,
 *      exactly like the `before()` / `beforeEach()` pair of the original. `setUp()` runs before
 *      every test, which is what the Hardhat fixture re-deployment did.
 *
 * @dev Deviation: the original deployed the production "core" fixture, upgraded its GroupHealth
 *      proxy to MockGroupHealth through the MultiSig and activated the groups through MultiSig
 *      proposals. The port uses the `FullTestManager` fixture against the devchain registry,
 *      which deploys MockGroupHealth directly and leaves the strategies owned by `owner`, so the
 *      groups are activated with a plain owner call. The contracts under test (Manager, Account,
 *      DefaultStrategy) and their wiring are the same either way.
 */
contract ManagerStrategyChangeTest is DevchainHelper, FullTestManagerDeployHelper {
    address internal depositor;
    address internal group0;
    address internal group1;

    function setUp() public {
        loadDevchain();
        deployFullTestManager(REGISTRY_ADDRESS);

        (depositor,) = randomSigner(1000 ether);

        group0 = _registerGroupWithValidator();
        group1 = _registerGroupWithValidator();

        address[] memory groups = new address[](2);
        groups[0] = group0;
        groups[1] = group1;
        electMockValidatorGroupsAndUpdate(mockGroupHealth, groups);

        _activateGroups(groups);
    }

    /// @dev Ambiguous because both CeloTestHelper and DevchainHelper define it.
    function mineToNextEpoch() internal override(CeloTestHelper, DevchainHelper) {
        super.mineToNextEpoch();
    }

    /// @dev Ambiguous because both CeloTestHelper and DevchainHelper define it.
    function currentEpochNumber()
        internal
        view
        override(CeloTestHelper, DevchainHelper)
        returns (uint256)
    {
        return super.currentEpochNumber();
    }

    /// @dev One validator group with a single validator member.
    function _registerGroupWithValidator() private returns (address group) {
        (group,) = randomSigner(21_000 ether);
        registerValidatorGroup(group, 1);
        registerValidatorAndAddToGroupMembers(group, createWallet(11_000 ether));
    }

    /// @dev Ports `activateValidators(...)` from utils-validators.ts.
    function _activateGroups(address[] memory groups) private {
        (address nextGroup,) = mockDefaultStrategy.getGroupsTail();

        for (uint256 i = 0; i < groups.length; i++) {
            require(mockGroupHealth.isGroupValid(groups[i]), "not a valid group");

            vm.startPrank(owner);
            mockDefaultStrategy.addActivatableGroup(groups[i]);
            mockDefaultStrategy.activateGroup(groups[i], ADDRESS_ZERO, nextGroup);
            vm.stopPrank();

            nextGroup = groups[i];
        }
    }

    /// @notice changeStrategy should NOT schedule transfers immediately; rebalance should.
    /// @dev Ports it("should NOT schedule transfers immediately on strategy change").
    function test_StrategyChange_ShouldNotScheduleTransfersImmediately() public {
        // Deposit to default strategy
        uint256 depositAmount = 100 ether;
        vm.prank(depositor);
        manager.deposit{value: depositAmount}();

        // Record initial state
        uint256 group0RevokeBefore = account.scheduledRevokeForGroup(group0);
        uint256 group1RevokeBefore = account.scheduledRevokeForGroup(group1);
        uint256 group0ScheduledBefore = account.scheduledVotesForGroup(group0);
        uint256 group1ScheduledBefore = account.scheduledVotesForGroup(group1);

        // Change strategy to specific group
        vm.prank(depositor);
        manager.changeStrategy(group0);

        // No transfers scheduled after change strategy
        uint256 group0RevokeAfterChange = account.scheduledRevokeForGroup(group0);
        uint256 group1RevokeAfterChange = account.scheduledRevokeForGroup(group1);
        uint256 group0ScheduledAfterChange = account.scheduledVotesForGroup(group0);
        uint256 group1ScheduledAfterChange = account.scheduledVotesForGroup(group1);

        assertEq(group0RevokeAfterChange, group0RevokeBefore);
        assertEq(group1RevokeAfterChange, group1RevokeBefore);
        assertEq(group0ScheduledAfterChange, group0ScheduledBefore);
        assertEq(group1ScheduledAfterChange, group1ScheduledBefore);

        // Internal accounting should be updated
        address depositorStrategy = manager.strategies(depositor);
        assertEq(depositorStrategy, group0);

        // Call rebalance
        manager.rebalance(group1, group0);

        // Transfers are scheduled after rebalance
        uint256 group0ScheduledAfterRebalance = account.scheduledVotesForGroup(group0);
        assertTrue(group0ScheduledAfterRebalance > group0ScheduledAfterChange);
    }
}
