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
        (address[] memory destinations, uint256[] memory values, bytes[] memory payloads) =
            ms.getProposal(proposalId);

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
            keccak256(PayloadLib.encodePayload("setMinCountOfActiveGroups(uint256)", "3"))
                == keccak256(
                    abi.encodeWithSignature("setMinCountOfActiveGroups(uint256)", uint256(3))
                )
        );
        assertTrue(
            keccak256(
                    PayloadLib.encodePayload("setAllowedToVoteOverMaxNumberOfGroups(bool)", "true")
                )
                == keccak256(
                    abi.encodeWithSignature("setAllowedToVoteOverMaxNumberOfGroups(bool)", true)
                )
        );
        assertTrue(
            keccak256(PayloadLib.encodePayload("setPauser()", ""))
                == keccak256(abi.encodeWithSignature("setPauser()"))
        );
    }

    // =========================================================================
    //                              HELPERS
    // =========================================================================

    /// @dev Submits the setDependencies proposal as the first MultiSig owner.
    function _submitSetDependenciesProposal() private returns (uint256 proposalId) {
        (address[] memory destinations, uint256[] memory values, bytes[] memory payloads) =
            _singleOperation(address(manager), _setDependenciesPayload());

        vm.prank(multisigOwner0);
        proposalId = MultiSigTaskLib.submitProposal(ms, destinations, values, payloads);
    }

    /// @dev Runs a second proposal that lowers the confirmation requirement to one.
    function _lowerRequirementToOne() private {
        (address[] memory destinations, uint256[] memory values, bytes[] memory payloads) = _singleOperation(
            multiSigProxy, abi.encodeWithSignature("changeRequirement(uint256)", uint256(1))
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
        return UpgradeProposalLib.managerSetDependenciesPayload(
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
        return string(
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
        returns (address[] memory destinations, uint256[] memory values, bytes[] memory payloads)
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

        mockGroupHealth =
            upgradeToMockGroupHealthE2E(multiSig, multisigOwner0, address(groupHealth));

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
            accountTask, defaultStrategyTask, specificGroupStrategyTask, electionTask
        );

        assertEq(accountTask.scheduledVotesForGroup(votedGroup), 0);
        assertTrue(celoElection.getPendingVotesForGroupByAccount(votedGroup, address(account)) > 0);

        // A second run after the epoch boundary activates the pending votes.
        mineToNextEpoch();
        assertTrue(celoElection.hasActivatablePendingVotes(address(account), votedGroup));

        AccountTaskLib.activateAndVote(
            accountTask, defaultStrategyTask, specificGroupStrategyTask, electionTask
        );
        assertTrue(celoElection.getActiveVotesForGroupByAccount(votedGroup, address(account)) > 0);
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

        uint256 votesBefore =
            celoElection.getTotalVotesForGroupByAccount(fromGroup, address(account));

        AccountTaskLib.revoke(
            accountTask, defaultStrategyTask, specificGroupStrategyTask, electionTask
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
            accountTask, defaultStrategyTask, specificGroupStrategyTask, electionTask, depositor
        );
        assertEq(_totalScheduledWithdrawals(), 0);

        uint256 pending = accountTask.getNumberPendingWithdrawals(depositor);
        assertTrue(pending > 0);

        // The withdrawal is still inside the LockedGold unlocking period.
        (bool readyEarly,,) =
            AccountTaskLib.pendingWithdrawalIndexes(accountTask, lockedGoldTask, depositor);
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
            accountTask, defaultStrategyTask, specificGroupStrategyTask, electionTask
        );
        mineToNextEpoch();
        AccountTaskLib.activateAndVote(
            accountTask, defaultStrategyTask, specificGroupStrategyTask, electionTask
        );
    }

    /// @dev Registers `count` validator groups with one validator each.
    function _registerGroups(uint256 count) private {
        for (uint256 i = 0; i < count; i++) {
            address group = makeAddr(string(abi.encodePacked("task-group-", vm.toString(i))));
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
        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        for (uint256 i = 0; i < groups.length; i++) {
            (address head,) = defaultStrategy.getGroupsHead();
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
        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);
    }

    /// @dev Moves `amount` CELO from one group to another, which schedules a revoke.
    function _scheduleTransfer(address fromGroup, address toGroup, uint256 amount) private {
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
            total += accountTask.scheduledWithdrawalsForGroupAndBeneficiary(groups[i], depositor);
        }
    }
}

/**
 * @dev Calls PayloadLib across a call boundary. The library is internal and gets inlined,
 *      so a direct call would revert the test itself instead of the call vm.expectRevert
 *      watches.
 */
contract PayloadEncoderHarness {
    function encodePayload(string memory signature, string memory argsCsv)
        external
        pure
        returns (bytes memory)
    {
        return PayloadLib.encodePayload(signature, argsCsv);
    }
}

/**
 * @title PayloadEncodingTest
 * @notice Covers the argument validation of script/tasks/lib/PayloadLib.sol: the encoder
 *         writes one 32 byte word per argument, so every type it cannot write that way, and
 *         every value that does not fit its declared type, has to be rejected rather than
 *         encoded into a payload the MultiSig would not be able to execute.
 * @dev No devchain fixture is needed: the encoder is pure string handling.
 */
contract PayloadEncodingTest is CeloTestHelper {
    /// @dev The lower case spelling of ADDRESS_ARGUMENT, to show the parse ignores casing.
    string internal constant ADDRESS_ARGUMENT_LOWER_CASE =
        "0xabcdef0123456789abcdef0123456789abcdef01";
    address internal constant ADDRESS_ARGUMENT = 0xabCDeF0123456789AbcdEf0123456789aBCDEF01;

    string internal constant BYTES32_ARGUMENT =
        "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    bytes32 internal constant BYTES32_VALUE =
        0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

    PayloadEncoderHarness internal encoder;

    function setUp() public {
        encoder = new PayloadEncoderHarness();
    }

    // =========================================================================
    //                            SUPPORTED TYPES
    // =========================================================================

    function test_encodesUintBoundaries() public view {
        _assertEncodes("setCap(uint8)", "255", abi.encodeWithSignature("setCap(uint8)", uint8(255)));
        _assertEncodes("setCap(uint8)", "0", abi.encodeWithSignature("setCap(uint8)", uint8(0)));
        _assertEncodes(
            "setCap(uint256)",
            "115792089237316195423570985008687907853269984665640564039457584007913129639935",
            abi.encodeWithSignature("setCap(uint256)", type(uint256).max)
        );
    }

    function test_encodesIntBoundaries() public view {
        _assertEncodes(
            "setDelta(int8)", "-128", abi.encodeWithSignature("setDelta(int8)", int8(-128))
        );
        _assertEncodes(
            "setDelta(int8)", "127", abi.encodeWithSignature("setDelta(int8)", int8(127))
        );
        _assertEncodes(
            "setDelta(int256)", "-1", abi.encodeWithSignature("setDelta(int256)", int256(-1))
        );
    }

    function test_encodesBytes32() public view {
        _assertEncodes(
            "setHash(bytes32)",
            BYTES32_ARGUMENT,
            abi.encodeWithSignature("setHash(bytes32)", BYTES32_VALUE)
        );
    }

    function test_encodesAddressIgnoringCase() public view {
        _assertEncodes(
            "upgradeTo(address)",
            ADDRESS_ARGUMENT_LOWER_CASE,
            abi.encodeWithSignature("upgradeTo(address)", ADDRESS_ARGUMENT)
        );
        _assertEncodes(
            "upgradeTo(address)",
            vm.toString(ADDRESS_ARGUMENT),
            abi.encodeWithSignature("upgradeTo(address)", ADDRESS_ARGUMENT)
        );
    }

    function test_encodesMixedArgumentsWithSpaces() public view {
        _assertEncodes(
            "setGroup(address,uint256,bool)",
            string(abi.encodePacked(ADDRESS_ARGUMENT_LOWER_CASE, ", 7, false")),
            abi.encodeWithSignature(
                "setGroup(address,uint256,bool)", ADDRESS_ARGUMENT, uint256(7), false
            )
        );
    }

    // =========================================================================
    //                           REJECTED TYPES
    // =========================================================================

    /// @dev The reported reproduction: an array argument used to encode as a single word,
    ///      producing a payload that could never be executed.
    function test_rejectsArrayType() public {
        vm.expectRevert("payload: unsupported argument type: uint256[]");
        encoder.encodePayload("setValues(uint256[])", "1");
    }

    function test_rejectsWhitespaceInSignature() public {
        // "setMinCountOfActiveGroups( uint256 )" hashes to a selector of a different function.
        vm.expectRevert("payload: signature must not contain whitespace");
        encoder.encodePayload("setMinCountOfActiveGroups( uint256 )", "1");
    }

    function test_canonicalSignatureSelector() public view {
        bytes memory payload = encoder.encodePayload("setMinCountOfActiveGroups(uint256)", "1");
        assertEq(uint256(uint32(bytes4(payload))), uint256(uint32(bytes4(0x41b9179f))));
    }

    function test_rejectsTupleType() public {
        vm.expectRevert("payload: unsupported argument type: (uint256,address)");
        encoder.encodePayload("setConfig((uint256,address))", "1");
    }

    function test_rejectsDynamicTypes() public {
        vm.expectRevert("payload: unsupported argument type: string");
        encoder.encodePayload("setName(string)", "celo");

        vm.expectRevert("payload: unsupported argument type: bytes");
        encoder.encodePayload("setBlob(bytes)", "0x1234");
    }

    function test_rejectsUnknownAndNonCanonicalTypes() public {
        vm.expectRevert("payload: unsupported argument type: uint12");
        encoder.encodePayload("setCap(uint12)", "1");

        vm.expectRevert("payload: unsupported argument type: uint");
        encoder.encodePayload("setCap(uint)", "1");

        vm.expectRevert("payload: unsupported argument type: bytes4");
        encoder.encodePayload("setSelector(bytes4)", "0x12345678");

        vm.expectRevert("payload: unsupported argument type: celo");
        encoder.encodePayload("setThing(celo)", "1");
    }

    function test_rejectsMalformedSignature() public {
        vm.expectRevert("payload: malformed signature");
        encoder.encodePayload("setCap(uint256", "1");
    }

    // =========================================================================
    //                           REJECTED VALUES
    // =========================================================================

    function test_rejectsOutOfRangeUint() public {
        vm.expectRevert("payload: uint8 argument out of range: 256");
        encoder.encodePayload("setCap(uint8)", "256");
    }

    function test_rejectsOutOfRangeInt() public {
        vm.expectRevert("payload: int8 argument out of range: -129");
        encoder.encodePayload("setDelta(int8)", "-129");

        vm.expectRevert("payload: int8 argument out of range: 128");
        encoder.encodePayload("setDelta(int8)", "128");
    }

    function test_rejectsNonDecimalInteger() public {
        vm.expectRevert("payload: invalid uint256 argument: 0x10");
        encoder.encodePayload("setCap(uint256)", "0x10");

        vm.expectRevert("payload: invalid int256 argument: -");
        encoder.encodePayload("setDelta(int256)", "-");
    }

    function test_rejectsBadBool() public {
        vm.expectRevert("payload: invalid bool argument: yes");
        encoder.encodePayload("setFlag(bool)", "yes");

        vm.expectRevert("payload: invalid bool argument: True");
        encoder.encodePayload("setFlag(bool)", "True");
    }

    function test_rejectsBadAddress() public {
        vm.expectRevert("payload: invalid address argument: 0x1234");
        encoder.encodePayload("upgradeTo(address)", "0x1234");

        vm.expectRevert(
            "payload: invalid address argument: abcdef0123456789abcdef0123456789abcdef01"
        );
        encoder.encodePayload("upgradeTo(address)", "abcdef0123456789abcdef0123456789abcdef01");

        vm.expectRevert(
            "payload: invalid address argument: 0xzzcdef0123456789abcdef0123456789abcdef01"
        );
        encoder.encodePayload("upgradeTo(address)", "0xzzcdef0123456789abcdef0123456789abcdef01");
    }

    function test_rejectsBadBytes32() public {
        vm.expectRevert("payload: invalid bytes32 argument: 0x1234");
        encoder.encodePayload("setHash(bytes32)", "0x1234");
    }

    function test_rejectsArgumentCountMismatch() public {
        vm.expectRevert("payload: argument count mismatch");
        encoder.encodePayload("setPair(address,address)", ADDRESS_ARGUMENT_LOWER_CASE);

        vm.expectRevert("payload: argument count mismatch");
        encoder.encodePayload("setPauser()", "1");

        vm.expectRevert("payload: argument count mismatch");
        encoder.encodePayload("setCap(uint256)", "");
    }

    // =========================================================================
    //                                HELPERS
    // =========================================================================

    /// @dev Asserts the encoder reproduces what the compiler would encode for the same call.
    function _assertEncodes(string memory signature, string memory argsCsv, bytes memory expected)
        private
        view
    {
        assertTrue(keccak256(encoder.encodePayload(signature, argsCsv)) == keccak256(expected));
    }
}

/**
 * @dev Election stub returning a fixed eligible group list. The core contract returns the
 *      groups ordered from most to least votes, and so does this.
 */
contract EligibleGroupsStub {
    address[] private groups;
    uint256[] private votes;

    function setGroups(address[] memory newGroups, uint256[] memory newVotes) external {
        groups = newGroups;
        votes = newVotes;
    }

    function getTotalVotesForEligibleValidatorGroups()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        return (groups, votes);
    }
}

/**
 * @title ElectionLibNeighbourTest
 * @notice Covers script/tasks/lib/ElectionLib.sol's neighbour search for the deltas the
 *         account tasks actually pass it: revoking or withdrawing more than the group holds
 *         right now, and a group that has dropped out of the eligible list entirely. Both
 *         leave the group below every other one, which is what the caller has to be told
 *         instead of the panic unsigned arithmetic would raise.
 * @dev A stub stands in for Election: only the eligible group list is read, and a fixed one
 *      makes the expected neighbours exact.
 */
contract ElectionLibNeighbourTest is CeloTestHelper {
    /// @dev Votes of the three groups, most first.
    uint256 internal constant MOST_VOTES = 100 ether;
    uint256 internal constant MIDDLE_VOTES = 50 ether;
    uint256 internal constant FEWEST_VOTES = 10 ether;

    IElectionLookup internal election;
    address internal mostVoted;
    address internal middleVoted;
    address internal fewestVoted;

    function setUp() public {
        mostVoted = makeAddr("most-voted-group");
        middleVoted = makeAddr("middle-voted-group");
        fewestVoted = makeAddr("fewest-voted-group");

        address[] memory groups = new address[](3);
        groups[0] = mostVoted;
        groups[1] = middleVoted;
        groups[2] = fewestVoted;

        uint256[] memory votes = new uint256[](3);
        votes[0] = MOST_VOTES;
        votes[1] = MIDDLE_VOTES;
        votes[2] = FEWEST_VOTES;

        EligibleGroupsStub stub = new EligibleGroupsStub();
        stub.setGroups(groups, votes);
        election = IElectionLookup(address(stub));
    }

    /// @dev The group keeps a positive vote total: it moves down the list but stays in it.
    function test_revokeWithinTheGroupTotal() public view {
        (address lesser, address greater) = ElectionLib.findLesserAndGreaterAfterVote(
            election, mostVoted, -int256(MOST_VOTES - 2 * FEWEST_VOTES)
        );

        assertEq(greater, middleVoted);
        assertEq(lesser, fewestVoted);
    }

    /// @dev More is revoked than the group holds. The total goes negative rather than
    ///      panicking, and the group belongs below every eligible one.
    function test_revokeLargerThanTheGroupTotal() public view {
        (address lesser, address greater) =
            ElectionLib.findLesserAndGreaterAfterVote(election, middleVoted, -int256(MOST_VOTES));

        assertEq(greater, fewestVoted);
        assertEq(lesser, ADDRESS_ZERO);
    }

    /// @dev The group is not eligible any more, so it holds nothing in this list. Any
    ///      revoke is larger than that.
    function test_revokeForAGroupThatIsNoLongerEligible() public {
        (address lesser, address greater) = ElectionLib.findLesserAndGreaterAfterVote(
            election, makeAddr("ineligible-group"), -int256(FEWEST_VOTES)
        );

        assertEq(greater, fewestVoted);
        assertEq(lesser, ADDRESS_ZERO);
    }

    /// @dev The voting direction is unchanged: the group moves up the list.
    function test_voteMovesTheGroupUp() public view {
        (address lesser, address greater) =
            ElectionLib.findLesserAndGreaterAfterVote(election, fewestVoted, int256(MIDDLE_VOTES));

        assertEq(greater, mostVoted);
        assertEq(lesser, middleVoted);
    }
}
