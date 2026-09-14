// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";
import "../helpers/deploy/CoreDeployHelper.sol";

import "../../script/tasks/lib/AccountTaskLib.sol";
import "../../script/tasks/lib/ElectionLib.sol";
import "../../script/tasks/lib/GroupsLib.sol";
import "../../script/tasks/lib/ManagerTaskLib.sol";
import "../../script/tasks/lib/MultiSigTaskLib.sol";
import "../../script/tasks/lib/PayloadLib.sol";
import "../../script/tasks/lib/UpgradeProposalLib.sol";

/**
 * @title TaskScriptsTestBase
 * @notice Deploys the production protocol fixture against the real Celo Registry of the
 *         devchain, so the operational task scripts run against the real Election,
 *         LockedGold and Validators contracts.
 */
abstract contract TaskScriptsTestBase is CoreDeployHelper, DevchainHelper {
    /// @dev Minimum delay baked into the MultiSig implementation, and the delay used here.
    uint256 internal constant MULTISIG_DELAY = 3 * DAY;

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
}

/**
 * @title MultiSigTaskScriptsTest
 * @notice Exercises the logic behind script/tasks/multisig/*.s.sol in process: a proposal
 *         carrying a Manager.setDependencies payload is submitted, its confirmation is
 *         revoked and re-added, it is scheduled and finally executed.
 * @dev The scripts keep their task logic in script/tasks/lib/*, so calling those libraries
 *      runs exactly the code `forge script` runs. Library functions are internal and get
 *      inlined, which is why vm.prank applies to the MultiSig calls they make.
 */
contract MultiSigTaskScriptsTest is TaskScriptsTestBase {
    /// @dev Cheatcode interface the task scripts use (toString(address) and friends).
    TaskVm internal constant taskVm =
        TaskVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev MultiSig.DONE_TIMESTAMP, the timestamp an executed proposal is marked with.
    uint256 internal constant DONE_TIMESTAMP = 1;

    IMultiSigTask internal ms;

    function setUp() public {
        loadDevchain();
        _initNamedAccounts();

        address[] memory owners = new address[](2);
        owners[0] = multisigOwner0;
        owners[1] = multisigOwner1;
        deployCore(REGISTRY_ADDRESS, owners, MULTISIG_DELAY, MULTISIG_DELAY, 2);

        ms = IMultiSigTask(multiSigProxy);
    }

    // =========================================================================
    //                     SUBMIT -> CONFIRM -> SCHEDULE -> EXECUTE
    // =========================================================================

    function test_setDependenciesProposalRoundTrip() public {
        uint256 proposalId = _submitSetDependenciesProposal();

        // One of two confirmations: neither fully confirmed nor scheduled yet.
        assertFalse(ms.isFullyConfirmed(proposalId));
        assertFalse(ms.isScheduled(proposalId));
        assertEq(ms.getConfirmations(proposalId).length, 1);
        assertTrue(ms.isConfirmedBy(proposalId, multisigOwner0));

        vm.prank(multisigOwner0);
        MultiSigTaskLib.revokeConfirmation(ms, proposalId);
        assertFalse(ms.isConfirmedBy(proposalId, multisigOwner0));
        assertEq(ms.getConfirmations(proposalId).length, 0);

        vm.prank(multisigOwner0);
        MultiSigTaskLib.confirmProposal(ms, proposalId);
        assertTrue(ms.isConfirmedBy(proposalId, multisigOwner0));

        // Lowering the requirement makes the proposal fully confirmed without scheduling it,
        // which is the situation the scheduleProposal task exists for.
        _lowerRequirementToOne();
        assertTrue(ms.isFullyConfirmed(proposalId));
        assertFalse(ms.isScheduled(proposalId));

        vm.prank(multisigOwner0);
        MultiSigTaskLib.scheduleProposal(ms, proposalId);
        assertTrue(ms.isScheduled(proposalId));
        assertFalse(ms.isProposalTimelockReached(proposalId));

        vm.warp(block.timestamp + ms.delay() + 1);
        assertTrue(ms.isProposalTimelockReached(proposalId));

        vm.prank(multisigOwner0);
        MultiSigTaskLib.executeProposal(ms, proposalId);

        assertEq(ms.getTimestamp(proposalId), DONE_TIMESTAMP);
        assertEq(address(manager.defaultStrategy()), address(defaultStrategy));
        assertEq(address(manager.groupHealth()), address(groupHealth));
    }

    function test_getOwnersAndProposalReadTasks() public {
        assertEq(ms.getOwners().length, 2);
        assertTrue(ms.isOwner(multisigOwner0));
        assertFalse(ms.isOwner(makeAddr("stranger")));

        uint256 proposalId = _submitSetDependenciesProposal();
        (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        ) = ms.getProposal(proposalId);

        assertEq(destinations.length, 1);
        assertEq(destinations[0], address(manager));
        assertEq(values[0], 0);
        assertTrue(keccak256(payloads[0]) == keccak256(_setDependenciesPayload()));
    }

    // =========================================================================
    //                          PAYLOAD ENCODING
    // =========================================================================

    function test_encodeProposalPayloadMatchesAbiEncoding() public view {
        bytes memory encoded = PayloadLib.encodePayload(
            "setDependencies(address,address,address,address,address,address)",
            _setDependenciesArgs()
        );
        assertTrue(keccak256(encoded) == keccak256(_setDependenciesPayload()));
    }

    function test_encodeProposalPayloadSupportsUintBoolAndNoArguments() public pure {
        assertTrue(
            keccak256(PayloadLib.encodePayload("setMinCountOfActiveGroups(uint256)", "3")) ==
                keccak256(
                    abi.encodeWithSignature("setMinCountOfActiveGroups(uint256)", uint256(3))
                )
        );
        assertTrue(
            keccak256(
                PayloadLib.encodePayload("setAllowedToVoteOverMaxNumberOfGroups(bool)", "true")
            ) ==
                keccak256(
                    abi.encodeWithSignature("setAllowedToVoteOverMaxNumberOfGroups(bool)", true)
                )
        );
        assertTrue(
            keccak256(PayloadLib.encodePayload("setPauser()", "")) ==
                keccak256(abi.encodeWithSignature("setPauser()"))
        );
    }

    // =========================================================================
    //                              HELPERS
    // =========================================================================

    /// @dev Submits the setDependencies proposal as the first MultiSig owner.
    function _submitSetDependenciesProposal() private returns (uint256 proposalId) {
        (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        ) = _singleOperation(address(manager), _setDependenciesPayload());

        vm.prank(multisigOwner0);
        proposalId = MultiSigTaskLib.submitProposal(ms, destinations, values, payloads);
    }

    /// @dev Runs a second proposal that lowers the confirmation requirement to one.
    function _lowerRequirementToOne() private {
        (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        ) = _singleOperation(
                multiSigProxy,
                abi.encodeWithSignature("changeRequirement(uint256)", uint256(1))
            );

        vm.prank(multisigOwner0);
        uint256 proposalId = MultiSigTaskLib.submitProposal(ms, destinations, values, payloads);

        vm.prank(multisigOwner1);
        MultiSigTaskLib.confirmProposal(ms, proposalId);
        assertTrue(ms.isScheduled(proposalId));

        vm.warp(block.timestamp + ms.delay() + 1);
        vm.prank(multisigOwner1);
        MultiSigTaskLib.executeProposal(ms, proposalId);
        assertEq(ms.required(), 1);
    }

    /// @dev The Manager.setDependencies payload the encode scripts produce.
    function _setDependenciesPayload() private view returns (bytes memory) {
        return
            UpgradeProposalLib.managerSetDependenciesPayload(
                address(stakedCelo),
                address(account),
                address(vote),
                address(groupHealth),
                address(specificGroupStrategy),
                address(defaultStrategy)
            );
    }

    /// @dev The same dependencies as the comma separated ARGS string of the encode script.
    function _setDependenciesArgs() private view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    taskVm.toString(address(stakedCelo)),
                    ",",
                    taskVm.toString(address(account)),
                    ",",
                    taskVm.toString(address(vote)),
                    ",",
                    taskVm.toString(address(groupHealth)),
                    ",",
                    taskVm.toString(address(specificGroupStrategy)),
                    ",",
                    taskVm.toString(address(defaultStrategy))
                )
            );
    }

    /// @dev A one operation proposal with a zero CELO value.
    function _singleOperation(address destination, bytes memory payload)
        private
        pure
        returns (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        )
    {
        destinations = new address[](1);
        values = new uint256[](1);
        payloads = new bytes[](1);
        destinations[0] = destination;
        payloads[0] = payload;
    }
}

/**
 * @title AccountAndManagerTaskScriptsTest
 * @notice Exercises the logic behind script/tasks/account/*.s.sol and
 *         script/tasks/manager/*.s.sol against the real Celo core contracts of the devchain
 *         fixture: deposit, activateAndVote, revoke, withdraw and finishPendingWithdrawal.
 */
contract AccountAndManagerTaskScriptsTest is TaskScriptsTestBase {
    uint256 internal constant DEPOSIT_AMOUNT = 30 ether;

    MockGroupHealth internal mockGroupHealth;
    address[] internal groups;
    address internal depositor;

    IAccountTask internal accountTask;
    IManagerTask internal managerTask;
    IDefaultStrategyTask internal defaultStrategyTask;
    ISpecificGroupStrategyTask internal specificGroupStrategyTask;
    IElectionLookup internal electionTask;
    ILockedGoldLookup internal lockedGoldTask;

    function setUp() public {
        loadDevchain();
        _initNamedAccounts();

        address[] memory owners = new address[](1);
        owners[0] = multisigOwner0;
        deployCore(REGISTRY_ADDRESS, owners, MULTISIG_DELAY, MULTISIG_DELAY, 1);

        mockGroupHealth = upgradeToMockGroupHealthE2E(
            multiSig,
            multisigOwner0,
            address(groupHealth)
        );

        _registerGroups(3);
        electMockValidatorGroupsAndUpdate(mockGroupHealth, groups);
        _activateGroups();

        // vm.prank replaces the caller of the next call, so the CELO a pranked deposit sends
        // is taken from the depositor's own balance.
        depositor = makeAddr("depositor");
        vm.deal(depositor, 10_000 ether);

        accountTask = IAccountTask(address(account));
        managerTask = IManagerTask(address(manager));
        defaultStrategyTask = IDefaultStrategyTask(address(defaultStrategy));
        specificGroupStrategyTask = ISpecificGroupStrategyTask(address(specificGroupStrategy));
        electionTask = IElectionLookup(address(celoElection));
        lockedGoldTask = ILockedGoldLookup(address(celoLockedGold));
    }

    // =========================================================================
    //                         MANAGER: GET GROUPS
    // =========================================================================

    function test_getGroupsListsTheActiveGroups() public view {
        address[] memory active = GroupsLib.defaultGroups(defaultStrategyTask);
        assertEq(active.length, groups.length);

        address[] memory all = GroupsLib.allGroups(defaultStrategyTask, specificGroupStrategyTask);
        assertEq(all.length, groups.length);
    }

    // =========================================================================
    //                      ACCOUNT: ACTIVATE AND VOTE
    // =========================================================================

    function test_activateAndVote() public {
        _deposit(DEPOSIT_AMOUNT);

        address votedGroup = _groupWithScheduledVotes();
        assertNotEq(votedGroup, ADDRESS_ZERO);

        AccountTaskLib.activateAndVote(
            accountTask,
            defaultStrategyTask,
            specificGroupStrategyTask,
            electionTask
        );

        assertEq(accountTask.scheduledVotesForGroup(votedGroup), 0);
        assertTrue(
            celoElection.getPendingVotesForGroupByAccount(votedGroup, address(account)) > 0
        );

        // A second run after the epoch boundary activates the pending votes.
        mineToNextEpoch();
        assertTrue(celoElection.hasActivatablePendingVotes(address(account), votedGroup));

        AccountTaskLib.activateAndVote(
            accountTask,
            defaultStrategyTask,
            specificGroupStrategyTask,
            electionTask
        );
        assertTrue(
            celoElection.getActiveVotesForGroupByAccount(votedGroup, address(account)) > 0
        );
    }

    // =========================================================================
    //                            ACCOUNT: REVOKE
    // =========================================================================

    function test_revoke() public {
        _depositActivateAndVote();

        address fromGroup = _groupWithCelo(1 ether);
        address toGroup = _otherGroup(fromGroup);
        _scheduleTransfer(fromGroup, toGroup, 1 ether);
        assertEq(accountTask.scheduledRevokeForGroup(fromGroup), 1 ether);

        uint256 votesBefore = celoElection.getTotalVotesForGroupByAccount(
            fromGroup,
            address(account)
        );

        AccountTaskLib.revoke(
            accountTask,
            defaultStrategyTask,
            specificGroupStrategyTask,
            electionTask
        );

        assertEq(accountTask.scheduledRevokeForGroup(fromGroup), 0);
        assertEq(
            celoElection.getTotalVotesForGroupByAccount(fromGroup, address(account)),
            votesBefore - 1 ether
        );
    }

    // =========================================================================
    //              ACCOUNT: WITHDRAW AND FINISH PENDING WITHDRAWAL
    // =========================================================================

    function test_withdrawAndFinishPendingWithdrawal() public {
        _depositActivateAndVote();

        uint256 stCeloBalance = stakedCelo.balanceOf(depositor);
        assertTrue(stCeloBalance > 0);

        vm.prank(depositor);
        ManagerTaskLib.withdraw(managerTask, stCeloBalance);
        assertTrue(_totalScheduledWithdrawals() > 0);

        AccountTaskLib.withdraw(
            accountTask,
            defaultStrategyTask,
            specificGroupStrategyTask,
            electionTask,
            depositor
        );
        assertEq(_totalScheduledWithdrawals(), 0);

        uint256 pending = accountTask.getNumberPendingWithdrawals(depositor);
        assertTrue(pending > 0);

        // The withdrawal is still inside the LockedGold unlocking period.
        (bool readyEarly, , ) = AccountTaskLib.pendingWithdrawalIndexes(
            accountTask,
            lockedGoldTask,
            depositor
        );
        assertFalse(readyEarly);

        timeTravel(celoLockedGold.unlockingPeriod() + 1);

        uint256 balanceBefore = depositor.balance;
        AccountTaskLib.finishPendingWithdrawals(accountTask, lockedGoldTask, depositor);

        assertEq(accountTask.getNumberPendingWithdrawals(depositor), 0);
        assertTrue(depositor.balance > balanceBefore);
    }

    // =========================================================================
    //            ACCOUNT: ALLOWED TO VOTE OVER MAX NUMBER OF GROUPS
    // =========================================================================

    function test_checkAllowedToVoteOverMaxNumberOfGroups() public {
        assertFalse(electionTask.allowedToVoteOverMaxNumberOfGroups(address(account)));

        _setAllowedToVoteOverMaxNumberOfGroups();
        assertTrue(electionTask.allowedToVoteOverMaxNumberOfGroups(address(account)));
    }

    // =========================================================================
    //                              HELPERS
    // =========================================================================

    /// @dev Deposits CELO through the Manager task on behalf of `depositor`.
    function _deposit(uint256 amount) private {
        vm.prank(depositor);
        ManagerTaskLib.deposit(managerTask, amount);
    }

    /// @dev Deposits, votes and activates the votes at the next epoch boundary.
    function _depositActivateAndVote() private {
        _deposit(DEPOSIT_AMOUNT);
        AccountTaskLib.activateAndVote(
            accountTask,
            defaultStrategyTask,
            specificGroupStrategyTask,
            electionTask
        );
        mineToNextEpoch();
        AccountTaskLib.activateAndVote(
            accountTask,
            defaultStrategyTask,
            specificGroupStrategyTask,
            electionTask
        );
    }

    /// @dev Registers `count` validator groups with one validator each.
    function _registerGroups(uint256 count) private {
        for (uint256 i = 0; i < count; i++) {
            address group = makeAddr(
                string(abi.encodePacked("task-group-", vm.toString(i)))
            );
            vm.deal(group, 100_000 ether);
            address validator = createWallet(100_000 ether);
            registerValidatorGroup(group, 1);
            registerValidatorAndAddToGroupMembers(group, validator);
            groups.push(group);
        }
    }

    /// @dev Marks the groups activatable through the MultiSig, then activates them.
    function _activateGroups() private {
        address[] memory destinations = new address[](groups.length);
        uint256[] memory values = new uint256[](groups.length);
        bytes[] memory payloads = new bytes[](groups.length);
        for (uint256 i = 0; i < groups.length; i++) {
            destinations[i] = address(defaultStrategy);
            payloads[i] = abi.encodeWithSignature("addActivatableGroup(address)", groups[i]);
        }
        submitAndExecuteMultiSigProposal(
            multiSig,
            destinations,
            values,
            payloads,
            multisigOwner0
        );

        for (uint256 i = 0; i < groups.length; i++) {
            (address head, ) = defaultStrategy.getGroupsHead();
            defaultStrategy.activateGroup(groups[i], ADDRESS_ZERO, head);
        }
    }

    /// @dev Lets the Account contract vote for more groups than the Election maximum.
    function _setAllowedToVoteOverMaxNumberOfGroups() private {
        address[] memory destinations = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        destinations[0] = address(account);
        payloads[0] = UpgradeProposalLib.setAllowedToVoteOverMaxNumberOfGroupsPayload(true);
        submitAndExecuteMultiSigProposal(
            multiSig,
            destinations,
            values,
            payloads,
            multisigOwner0
        );
    }

    /// @dev Moves `amount` CELO from one group to another, which schedules a revoke.
    function _scheduleTransfer(
        address fromGroup,
        address toGroup,
        uint256 amount
    ) private {
        address[] memory fromGroups = new address[](1);
        uint256[] memory fromVotes = new uint256[](1);
        address[] memory toGroups = new address[](1);
        uint256[] memory toVotes = new uint256[](1);
        fromGroups[0] = fromGroup;
        fromVotes[0] = amount;
        toGroups[0] = toGroup;
        toVotes[0] = amount;

        vm.prank(address(manager));
        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
    }

    /// @dev The first group the deposit scheduled votes for.
    function _groupWithScheduledVotes() private view returns (address) {
        for (uint256 i = 0; i < groups.length; i++) {
            if (accountTask.scheduledVotesForGroup(groups[i]) > 0) {
                return groups[i];
            }
        }
        return ADDRESS_ZERO;
    }

    /// @dev The first group holding at least `amount` CELO for the protocol.
    function _groupWithCelo(uint256 amount) private view returns (address) {
        for (uint256 i = 0; i < groups.length; i++) {
            if (accountTask.getCeloForGroup(groups[i]) >= amount) {
                return groups[i];
            }
        }
        revert("no group holds enough CELO");
    }

    /// @dev Any group other than `group`.
    function _otherGroup(address group) private view returns (address) {
        for (uint256 i = 0; i < groups.length; i++) {
            if (groups[i] != group) {
                return groups[i];
            }
        }
        revert("no other group");
    }

    /// @dev Total CELO scheduled to be withdrawn for the depositor across all groups.
    function _totalScheduledWithdrawals() private view returns (uint256 total) {
        for (uint256 i = 0; i < groups.length; i++) {
            total += accountTask.scheduledWithdrawalsForGroupAndBeneficiary(
                groups[i],
                depositor
            );
        }
    }
}
