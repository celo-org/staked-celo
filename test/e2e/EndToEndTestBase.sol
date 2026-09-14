// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";
import "../helpers/deploy/CoreDeployHelper.sol";

/**
 * @title EndToEndTestBase
 * @notice Shared fixture of the five end-to-end suites of the Hardhat test suite
 *         (test-ts/end-to-end*.test.ts).
 * @dev `setUp()` merges the `before()` and `beforeEach()` blocks of the originals:
 *        - fund the depositors and the voter, create the voter's Celo account,
 *        - register the validator groups with their validators,
 *        - deploy the production "core" fixture against the devchain registry with
 *          TIME_LOCK_MIN_DELAY = TIME_LOCK_DELAY = MULTISIG_REQUIRED_CONFIRMATIONS = 1,
 *        - upgrade GroupHealth to MockGroupHealth through the MultiSig,
 *        - elect the validators of the tested groups on MockGroupHealth,
 *        - activate the first three groups in DefaultStrategy through the MultiSig.
 *
 *      The Hardhat tests drove the protocol through the `account:*` Hardhat tasks. Those
 *      tasks are inlined here as `activateAndVote()`, `revoke()`, `withdraw(beneficiary)`
 *      and `finishPendingWithdrawals(beneficiary)` with the logic of
 *      lib/account-tasks/helpers/*.ts.
 */
abstract contract EndToEndTestBase is CoreDeployHelper, DevchainHelper {
    /// @dev Lesser/greater neighbours and group index of an Account revocation, as computed
    ///      by lib/account-tasks/helpers/revokeHelper.ts and withdrawalHelper.ts.
    struct RevokeNeighbours {
        address lesserAfterPendingRevoke;
        address greaterAfterPendingRevoke;
        address lesserAfterActiveRevoke;
        address greaterAfterActiveRevoke;
        uint256 index;
    }

    /// @dev The "deployer" named account runs the account tasks (`useNodeAccount: true`).
    address internal taskSigner;

    // Depositors of the original suites; every suite funds them with 300 CELO.
    address internal depositor0;
    address internal depositor1;
    address internal depositor2;
    address internal depositor3;
    address internal depositor4;
    address internal depositor5;
    address internal depositor6;
    address internal voter;

    /// @dev Registered validator groups, `activatedGroupAddresses` are the first three.
    address[] internal groups;
    address[] internal validators;
    address[] internal activatedGroupAddresses;

    /// @dev GroupHealth proxy after the upgrade to MockGroupHealth.
    MockGroupHealth internal groupHealthMock;

    /// @dev CoreDeployHelper and DevchainHelper both derive from CeloTestHelper, so the epoch
    ///      helpers have to be disambiguated explicitly. The devchain behaviour is kept.
    function mineToNextEpoch() internal override(CeloTestHelper, DevchainHelper) {
        DevchainHelper.mineToNextEpoch();
    }

    function currentEpochNumber()
        internal
        view
        override(CeloTestHelper, DevchainHelper)
        returns (uint256)
    {
        return DevchainHelper.currentEpochNumber();
    }

    function setUp() public virtual {
        loadDevchain();
        _initNamedAccounts();
        taskSigner = deployer;

        _createDepositorsAndVoter();
        _registerGroups();

        // hre.deployments.fixture("core") with TIME_LOCK_MIN_DELAY = TIME_LOCK_DELAY =
        // MULTISIG_REQUIRED_CONFIRMATIONS = 1.
        deployCore(REGISTRY_ADDRESS, 1, 1, 1);

        groupHealthMock = upgradeToMockGroupHealthE2E(
            multiSig,
            multisigOwner0,
            address(groupHealth)
        );
        electMockValidatorGroupsAndUpdate(groupHealthMock, _groupsToElect());
        activateValidators(activatedGroupAddresses);
    }

    // =========================================================================
    //                          FIXTURE HOOKS
    // =========================================================================

    /// @notice Number of validator groups registered in `before()`.
    function _numberOfGroups() internal view virtual returns (uint256) {
        return 10;
    }

    /// @notice Number of validators registered for group `index`.
    function _validatorsPerGroup(uint256) internal view virtual returns (uint256) {
        return 1;
    }

    /// @notice Initial CELO balance of every validator group.
    function _groupBalance() internal view virtual returns (uint256) {
        return 11_000 ether;
    }

    /// @notice Initial CELO balance of the voter.
    function _voterBalance() internal view virtual returns (uint256) {
        return 300 ether;
    }

    /// @notice Groups whose validators are marked elected on MockGroupHealth.
    function _groupsToElect() internal view virtual returns (address[] memory) {
        return activatedGroupAddresses;
    }

    /// @dev The activated groups plus one extra group (the shape used by most suites).
    function _activatedGroupsPlus(address extra) internal view returns (address[] memory list) {
        list = new address[](activatedGroupAddresses.length + 1);
        for (uint256 i = 0; i < activatedGroupAddresses.length; i++) {
            list[i] = activatedGroupAddresses[i];
        }
        list[activatedGroupAddresses.length] = extra;
    }

    /// @dev The activated groups plus two extra groups.
    function _activatedGroupsPlus(address extra, address extra2)
        internal
        view
        returns (address[] memory list)
    {
        list = new address[](activatedGroupAddresses.length + 2);
        for (uint256 i = 0; i < activatedGroupAddresses.length; i++) {
            list[i] = activatedGroupAddresses[i];
        }
        list[activatedGroupAddresses.length] = extra;
        list[activatedGroupAddresses.length + 1] = extra2;
    }

    function _createDepositorsAndVoter() private {
        depositor0 = makeAddr("depositor0");
        depositor1 = makeAddr("depositor1");
        depositor2 = makeAddr("depositor2");
        depositor3 = makeAddr("depositor3");
        depositor4 = makeAddr("depositor4");
        depositor5 = makeAddr("depositor5");
        depositor6 = makeAddr("depositor6");
        vm.deal(depositor0, 300 ether);
        vm.deal(depositor1, 300 ether);
        vm.deal(depositor2, 300 ether);
        vm.deal(depositor3, 300 ether);
        vm.deal(depositor4, 300 ether);
        vm.deal(depositor5, 300 ether);
        vm.deal(depositor6, 300 ether);

        voter = makeAddr("voter");
        vm.deal(voter, _voterBalance());
        createCeloAccount(voter);
    }

    function _registerGroups() private {
        for (uint256 i = 0; i < _numberOfGroups(); i++) {
            address group = makeAddr(string(abi.encodePacked("group", vm.toString(i))));
            vm.deal(group, _groupBalance());
            groups.push(group);
            if (i < 3) {
                activatedGroupAddresses.push(group);
            }

            uint256 members = _validatorsPerGroup(i);
            registerValidatorGroup(group, members);
            for (uint256 j = 0; j < members; j++) {
                address validator = createWallet(11_000 ether);
                validators.push(validator);
                registerValidatorAndAddToGroupMembers(group, validator);
            }
        }
    }

    // =========================================================================
    //                  activateValidators (utils-validators.ts)
    // =========================================================================

    /// @notice Adds and activates `groupAddresses` in DefaultStrategy through the MultiSig.
    function activateValidators(address[] memory groupAddresses) internal {
        (address nextGroup, ) = defaultStrategy.getGroupsTail();

        address[] memory destinations = new address[](1);
        destinations[0] = address(defaultStrategy);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);

        for (uint256 i = 0; i < groupAddresses.length; i++) {
            require(groupHealthMock.isGroupValid(groupAddresses[i]), "not a valid group");

            payloads[0] = abi.encodeWithSignature(
                "addActivatableGroup(address)",
                groupAddresses[i]
            );
            submitAndExecuteMultiSigProposal(
                multiSig,
                destinations,
                values,
                payloads,
                multisigOwner0
            );

            payloads[0] = abi.encodeWithSignature(
                "activateGroup(address,address,address)",
                groupAddresses[i],
                ADDRESS_ZERO,
                nextGroup
            );
            submitAndExecuteMultiSigProposal(
                multiSig,
                destinations,
                values,
                payloads,
                multisigOwner0
            );

            nextGroup = groupAddresses[i];
        }
    }

    // =========================================================================
    //                     ACCOUNT TASKS (lib/account-tasks)
    // =========================================================================

    /// @notice Ports the ACCOUNT_ACTIVATE_AND_VOTE task (activateAndVoteHelper.ts).
    function activateAndVote() internal {
        address[] memory groupList = getGroupsOfAllStrategies(
            defaultStrategy,
            specificGroupStrategy
        );

        for (uint256 i = 0; i < groupList.length; i++) {
            address group = groupList[i];
            bool canActivateForGroup = celoElection.hasActivatablePendingVotes(
                address(account),
                group
            );
            uint256 amountScheduled = account.scheduledVotesForGroup(group);

            if (amountScheduled > 0 || canActivateForGroup) {
                (address lesser, address greater) = findLesserAndGreaterAfterVote(
                    group,
                    int256(amountScheduled)
                );
                vm.prank(taskSigner);
                account.activateAndVote(group, lesser, greater);
            }
        }
    }

    /// @notice Ports the ACCOUNT_REVOKE task (revokeHelper.ts).
    function revoke() internal {
        address[] memory groupList = getGroupsOfAllStrategies(
            defaultStrategy,
            specificGroupStrategy
        );

        for (uint256 i = 0; i < groupList.length; i++) {
            address group = groupList[i];
            uint256 scheduledToRevokeAmount = account.scheduledRevokeForGroup(group);
            if (scheduledToRevokeAmount == 0) continue;

            RevokeNeighbours memory n = _revokeNeighbours(group, scheduledToRevokeAmount);
            vm.prank(taskSigner);
            account.revokeVotes(
                group,
                n.lesserAfterPendingRevoke,
                n.greaterAfterPendingRevoke,
                n.lesserAfterActiveRevoke,
                n.greaterAfterActiveRevoke,
                n.index
            );
        }
    }

    /// @notice Ports the ACCOUNT_WITHDRAW task (withdrawalHelper.ts).
    function withdraw(address beneficiary) internal {
        address[] memory groupList = getGroupsOfAllStrategies(
            defaultStrategy,
            specificGroupStrategy
        );

        for (uint256 i = 0; i < groupList.length; i++) {
            address group = groupList[i];
            uint256 scheduledWithdrawalAmount = account.scheduledWithdrawalsForGroupAndBeneficiary(
                group,
                beneficiary
            );
            if (scheduledWithdrawalAmount == 0) continue;

            RevokeNeighbours memory n = _revokeNeighbours(group, scheduledWithdrawalAmount);
            vm.prank(taskSigner);
            account.withdraw(
                beneficiary,
                group,
                n.lesserAfterPendingRevoke,
                n.greaterAfterPendingRevoke,
                n.lesserAfterActiveRevoke,
                n.greaterAfterActiveRevoke,
                n.index
            );
        }
    }

    /// @notice Finishes every pending withdrawal of `beneficiary`.
    /// @dev Ports the local helper of the original end-to-end tests, which always passes
    ///      index (0, 0) because a finished withdrawal is swapped out of both lists.
    function finishPendingWithdrawals(address beneficiary) internal {
        (, uint256[] memory timestamps) = account.getPendingWithdrawals(beneficiary);
        for (uint256 i = 0; i < timestamps.length; i++) {
            account.finishPendingWithdrawal(beneficiary, 0, 0);
        }
    }

    /// @dev The lesser/greater pairs and the group index used by revokeVotes / withdraw.
    function _revokeNeighbours(address group, uint256 scheduledAmount)
        private
        view
        returns (RevokeNeighbours memory n)
    {
        uint256 immediateWithdrawalAmount = account.scheduledVotesForGroup(group);

        if (immediateWithdrawalAmount < scheduledAmount) {
            uint256 remainingToRevokeAmount = scheduledAmount - immediateWithdrawalAmount;
            uint256 pendingVotes = celoElection.getPendingVotesForGroupByAccount(
                group,
                address(account)
            );
            uint256 toRevokeFromPending = remainingToRevokeAmount < pendingVotes
                ? remainingToRevokeAmount
                : pendingVotes;

            (n.lesserAfterPendingRevoke, n.greaterAfterPendingRevoke) = (
                findLesserAndGreaterAfterVote(group, -int256(toRevokeFromPending))
            );

            // Revoking pending votes happens before revoking active votes in the same
            // transaction, so the neighbours of the active revocation are computed from the
            // full remaining amount.
            (n.lesserAfterActiveRevoke, n.greaterAfterActiveRevoke) = (
                findLesserAndGreaterAfterVote(group, -int256(remainingToRevokeAmount))
            );
        }

        n.index = _findAddressIndex(group);
    }

    /// @dev Index of `group` in the groups the Account contract voted for.
    function _findAddressIndex(address group) private view returns (uint256) {
        address[] memory list = celoElection.getGroupsVotedForByAccount(address(account));
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == group) return i;
        }
        revert("group not voted for by Account");
    }

    // =========================================================================
    //                          TEST UTILITIES
    // =========================================================================

    /// @notice rebalanceAllAndActivate() of the original suites.
    function rebalanceAllAndActivate() internal {
        rebalanceDefaultGroups(defaultStrategy);
        rebalanceGroups(manager, specificGroupStrategy, defaultStrategy);
        revoke();
        activateAndVote();
    }

    /// @notice Distributes `amount` of epoch rewards to `groups[groupIndex]`.
    function distributeRewards(uint256 groupIndex, uint256 amount) internal {
        distributeEpochRewards(groups[groupIndex], amount);
    }

    /// @notice Waits out the LockedGold unlocking period.
    /// @dev Deviation: the Hardhat suite waited `LOCKED_GOLD_UNLOCKING_PERIOD` (3 days), the
    ///      constant of the ganache devchain. The anvil devchain unlocks after 6 hours, so the
    ///      period is read from LockedGold; the semantics (wait out the whole period) are kept.
    function timeTravelUnlockingPeriod() internal {
        timeTravel(celoLockedGold.unlockingPeriod() + 1);
    }

    /// @notice Deposits `amount` CELO for `depositor`.
    function deposit(address depositor, uint256 amount) internal {
        vm.prank(depositor);
        manager.deposit{value: amount}();
    }

    /// @dev Asserts `real` is within `range` of `expected` (expectBigNumberInRange).
    function assertInRange(
        uint256 real,
        uint256 expected,
        uint256 range
    ) internal pure {
        require(real + range >= expected, "value below expected range");
        require(real <= expected + range, "value above expected range");
    }
}
