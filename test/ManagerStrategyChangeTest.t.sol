// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/deploy/FullTestManagerDeployHelper.sol";
import "./helpers/ValidatorHelper.sol";

/// @dev Extended VM interface for mockCall cheatcode (not in CeloTestVm).
interface IVmMockCall {
    function mockCall(address callee, bytes calldata data, bytes calldata returnData) external;
}

/**
 * @title ManagerStrategyChangeTest
 * @notice Tests Manager.changeStrategy behavior — delayed transfer pattern.
 * @dev Migrated from test-ts/manager-strategy-change.test.ts (145 LOC, 1 test).
 *      Verifies that changeStrategy does NOT schedule transfers immediately,
 *      but rebalance() does.
 */
contract ManagerStrategyChangeTest is FullTestManagerDeployHelper, ValidatorHelper {
    address depositor;
    address group0;
    address group1;

    function setUp() public {
        // Phase 1: Deploy full Manager fixture
        deployFullTestManager();

        // Phase 2: Create depositor with 1000 CELO
        (depositor, ) = randomSigner(1000 ether);

        // Phase 3: Create 2 validator groups, each with 1 validator member
        address validator0;
        address validator1;

        (group0, ) = randomSigner(21000 ether);
        registerValidatorGroup(mockValidators, mockLockedGold, group0, 1);
        (validator0, ) = randomSigner(11000 ether);
        registerValidatorAndAddToGroupMembers(mockValidators, mockLockedGold, group0, validator0);

        (group1, ) = randomSigner(21000 ether);
        registerValidatorGroup(mockValidators, mockLockedGold, group1, 1);
        (validator1, ) = randomSigner(11000 ether);
        registerValidatorAndAddToGroupMembers(mockValidators, mockLockedGold, group1, validator1);

        // Phase 4: Elect mock validator groups and set health
        // MockValidators lacks getValidatorGroup(), so we cannot use
        // updateGroupHealth. Instead: set elected validators, then set validity directly.
        address[] memory groups = new address[](2);
        groups[0] = group0;
        groups[1] = group1;
        electMockValidatorGroupsAndUpdate(
            mockValidators,
            address(mockGroupHealth),
            groups,
            false, // don't revoke
            false  // DON'T update (MockValidators.getValidatorGroup doesn't exist)
        );
        mockGroupHealth.setGroupValidity(group0, true);
        mockGroupHealth.setGroupValidity(group1, true);

        // Phase 5: Activate validators in DefaultStrategy
        // FullTestManagerDeployHelper sets `owner` as DefaultStrategy owner (no MultiSig),
        // so we call addActivatableGroup/activateGroup directly via prank.
        DefaultStrategy ds = DefaultStrategy(address(mockDefaultStrategy));
        vm.startPrank(owner);

        (address nextGroup, ) = ds.getGroupsTail();

        ds.addActivatableGroup(group0);
        ds.activateGroup(group0, address(0), nextGroup);
        nextGroup = group0;

        ds.addActivatableGroup(group1);
        ds.activateGroup(group1, address(0), nextGroup);

        vm.stopPrank();

        // Phase 6: Mock Election.getNumVotesReceivable to return max
        // MockElection hardcodes getNumVotesReceivable() to 0, preventing any deposits.
        // In the TS test, the real Celo Election contract handles this. We mock it here.
        IVmMockCall(address(vm)).mockCall(
            address(mockElection),
            abi.encodeWithSelector(IElection.getNumVotesReceivable.selector),
            abi.encode(type(uint256).max)
        );
    }

    /// @notice changeStrategy should NOT schedule transfers immediately; rebalance should.
    /// @dev Migrated from: it("should NOT schedule transfers immediately on strategy change")
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
