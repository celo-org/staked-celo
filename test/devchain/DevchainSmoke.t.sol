// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";

/// @dev Minimal console logger (forge-std cannot be imported under pragma 0.8.11).
library Log {
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    function u(string memory label, uint256 value) internal view {
        (bool ok, ) = CONSOLE.staticcall(abi.encodeWithSignature("log(string,uint256)", label, value));
        ok;
    }

    function a(string memory label, address value) internal view {
        (bool ok, ) = CONSOLE.staticcall(abi.encodeWithSignature("log(string,address)", label, value));
        ok;
    }
}

/**
 * @title DevchainSmokeTest
 * @notice Sanity checks for the devchain fixture: the flows the ported Hardhat tests rely on
 *         (locking, voting, epochs, rewards, validator registration, withdrawals) must work
 *         against the real Celo core contracts.
 */
contract DevchainSmokeTest is DevchainHelper {
    address internal voter;

    function setUp() public {
        loadDevchain();
        _initNamedAccounts();
        voter = makeAddr("voter");
        vm.deal(voter, 1_000_000 ether);
    }

    function test_coreContractsResolved() public view {
        assertNotEq(address(celoAccounts), ADDRESS_ZERO);
        assertNotEq(address(celoLockedGold), ADDRESS_ZERO);
        assertNotEq(address(celoElection), ADDRESS_ZERO);
        assertNotEq(address(celoValidators), ADDRESS_ZERO);
        assertNotEq(address(celoEpochManager), ADDRESS_ZERO);
        assertNotEq(address(celoGoldToken), ADDRESS_ZERO);
        assertNotEq(address(celoGovernance), ADDRESS_ZERO);

        Log.u("block.number", block.number);
        Log.u("block.timestamp", block.timestamp);
        Log.u("epoch", currentEpochNumber());
        Log.u("validatorLockedGoldRequirement", validatorLockedGoldRequirement);
        Log.u("groupLockedGoldRequirement", groupLockedGoldRequirement);
        Log.u("unlockingPeriod", celoLockedGold.unlockingPeriod());
        Log.u("totalLockedGold", celoLockedGold.getTotalLockedGold());
        Log.u("numRegisteredValidators", celoValidators.getNumRegisteredValidators());
        Log.u("maxNumGroupsVotedFor", celoElection.maxNumGroupsVotedFor());
        (uint256 minElectable, uint256 maxElectable) = celoElection.getElectableValidators();
        Log.u("electable.min", minElectable);
        Log.u("electable.max", maxElectable);
        Log.u("epochDuration", celoEpochManager.epochDuration());
        Log.a("registry.owner", celoRegistry.owner());
        Log.a("lockedGold.owner", celoLockedGold.owner());
        Log.a("governance.owner", celoGovernance.owner());
        Log.a("governance.approver", celoGovernance.approver());
        Log.u("governance.minDeposit", celoGovernance.minDeposit());
        Log.u("governance.concurrentProposals", celoGovernance.concurrentProposals());
        Log.u("governance.referendumDuration", celoGovernance.getReferendumStageDuration());
        Log.u("eligibleGroups", celoElection.getEligibleValidatorGroups().length);
    }

    function test_lockUnlockWithdraw() public {
        lockCelo(voter, 10 ether);
        assertEq(celoLockedGold.getAccountTotalLockedGold(voter), 10 ether);

        vm.prank(voter);
        celoLockedGold.unlock(4 ether);
        (uint256[] memory values, uint256[] memory timestamps) = celoLockedGold
            .getPendingWithdrawals(voter);
        assertEq(values.length, 1);
        assertEq(values[0], 4 ether);
        assertTrue(timestamps[0] > block.timestamp);

        uint256 before = voter.balance;
        timeTravel(celoLockedGold.unlockingPeriod() + 1);
        vm.prank(voter);
        celoLockedGold.withdraw(0);
        // LockedGold pays out through GoldToken, which uses the Celo transfer precompile.
        assertEq(voter.balance, before + 4 ether);
        assertEq(celoLockedGold.getAccountTotalLockedGold(voter), 6 ether);
    }

    function test_goldTokenTransfer() public {
        address receiver = makeAddr("receiver");
        vm.prank(voter);
        celoGoldToken.transfer(receiver, 1 ether);
        assertEq(receiver.balance, 1 ether);
        assertEq(celoGoldToken.balanceOf(receiver), 1 ether);
    }

    function test_registerGroupVoteActivateAndRewards() public {
        address group = makeAddr("group");
        vm.deal(group, 100_000 ether);
        address validator = createWallet(100_000 ether);

        registerValidatorGroup(group, 1);
        registerValidatorAndAddToGroupMembers(group, validator);
        assertTrue(celoValidators.isValidatorGroup(group));
        assertTrue(celoValidators.isValidator(validator));
        assertEq(celoValidators.getGroupNumMembers(group), 1);
        assertTrue(celoElection.getGroupEligibility(group));

        voteForGroup(group, voter, 50 ether);
        assertEq(celoElection.getPendingVotesForGroupByAccount(group, voter), 50 ether);
        assertFalse(celoElection.hasActivatablePendingVotes(voter, group));

        mineToNextEpoch();
        assertTrue(celoElection.hasActivatablePendingVotes(voter, group));
        activateVotesForGroup(voter);
        assertEq(celoElection.getActiveVotesForGroupByAccount(group, voter), 50 ether);

        distributeEpochRewards(group, 5 ether);
        assertEq(celoElection.getActiveVotesForGroupByAccount(group, voter), 55 ether);
        assertEq(celoElection.getActiveVotesForGroup(group), 55 ether);
    }

    function test_makeValidatorUseSigner() public {
        address group = makeAddr("group");
        vm.deal(group, 100_000 ether);
        address validator = createWallet(100_000 ether);
        registerValidatorGroup(group, 1);
        registerValidatorAndAddToGroupMembers(group, validator);

        address signer = makeValidatorUseSigner(validator);
        assertEq(celoAccounts.getValidatorSigner(validator), signer);
        assertEq(celoAccounts.validatorSignerToAccount(signer), validator);
    }

    function test_deregisterValidatorGroup() public {
        address group = makeAddr("group");
        vm.deal(group, 100_000 ether);
        address validator = createWallet(100_000 ether);
        registerValidatorGroup(group, 1);
        registerValidatorAndAddToGroupMembers(group, validator);

        deregisterValidatorGroup(group);
        assertFalse(celoValidators.isValidatorGroup(group));
    }

    function test_slashingMultiplier() public {
        address group = makeAddr("group");
        vm.deal(group, 100_000 ether);
        address validator = createWallet(100_000 ether);
        registerValidatorGroup(group, 1);
        registerValidatorAndAddToGroupMembers(group, validator);

        address slasher = makeAddr("slasher");
        updateGroupSlashingMultiplier(group, slasher);
        assertEq(celoValidators.getValidatorGroupSlashingMultiplier(group), 5e23);
    }

    function test_prepareOverflow() public {
        address[] memory groups = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            groups[i] = makeAddr(string(abi.encodePacked("ovf-group-", vm.toString(i))));
            vm.deal(groups[i], 100_000 ether);
            address validator = createWallet(100_000 ether);
            registerValidatorGroup(groups[i], 1);
            registerValidatorAndAddToGroupMembers(groups[i], validator);
        }
        // DefaultStrategy is not needed to exercise the vote math.
        prepareOverflow(DefaultStrategy(address(0)), voter, groups, false);

        uint256[3] memory expected = [uint256(40 ether), uint256(100 ether), uint256(200 ether)];
        for (uint256 i = 0; i < 3; i++) {
            uint256 left = celoElection.getNumVotesReceivable(groups[i]) -
                celoElection.getTotalVotesForGroup(groups[i]);
            Log.u("receivable left", left);
            assertEq(left, expected[i]);
        }
    }

    function test_governanceConcurrentProposals() public {
        setGovernanceConcurrentProposals(5);
        assertEq(celoGovernance.concurrentProposals(), 5);
    }
}
