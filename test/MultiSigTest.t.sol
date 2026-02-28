// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/deploy/TestAccountDeployHelper.sol";
import "./helpers/MultiSigHelper.sol";
import "../contracts/test/ProposalTester.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Extended MultiSig interface with ALL functions needed for tests.
///      DO NOT import MultiSig.sol directly (Initializable collision).
interface IMultiSigFull {
    // --- from IMultiSig ---
    function submitProposal(
        address[] calldata destinations,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) external returns (uint256 proposalId);
    function scheduleProposal(uint256 proposalId) external;
    function executeProposal(uint256 proposalId) external;
    function delay() external view returns (uint256);
    function required() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function isOwner(address owner) external view returns (bool);
    function proposalCount() external view returns (uint256);

    // --- additional ---
    function minDelay() external view returns (uint256);
    function initialize(address[] calldata, uint256, uint256) external;
    function getProposal(uint256 proposalId) external view returns (
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory payloads
    );
    function getConfirmations(uint256 proposalId) external view returns (address[] memory);
    function isFullyConfirmed(uint256 proposalId) external view returns (bool);
    function isConfirmedBy(uint256 proposalId, address owner) external view returns (bool);
    function isScheduled(uint256 proposalId) external view returns (bool);
    function getTimestamp(uint256 proposalId) external view returns (uint256);
    function isProposalTimelockReached(uint256 proposalId) external view returns (bool);
    function confirmProposal(uint256 proposalId) external;
    function revokeConfirmation(uint256 proposalId) external;
    function addOwner(address owner) external;
    function removeOwner(address owner) external;
    function replaceOwner(address owner, address newOwner) external;
    function changeRequirement(uint256 newRequired) external;
    function changeDelay(uint256 newDelay) external;
    function setPauser(address pauser) external;
    function pauseContracts(address[] calldata contracts) external;
    function unpauseContracts(address[] calldata contracts) external;
    function governanceProposeAndExecute(
        address[] calldata destinations,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) external;
    function pauser() external view returns (address);
    function isPaused() external view returns (bool);
    function pause() external;
    function unpause() external;
    function owner() external view returns (address);
}

/// @dev Additional VM cheatcodes not in CeloTestVm.
interface IVmExt {
    function etch(address target, bytes calldata code) external;
    function store(address target, bytes32 slot, bytes32 value) external;
}

/// @dev Errors emitted by MultiSig (for vm.expectRevert matching).
interface IMultiSigErrors {
    error SenderMustBeMultisigWallet(address account);
    error OwnerDoesNotExist(address owner);
    error OwnerAlreadyExists(address owner);
    error ProposalAlreadyConfirmed(uint256 proposalId, address owner);
    error ProposalNotConfirmed(uint256 proposalId, address owner);
    error ProposalNotFullyConfirmed(uint256 proposalId);
    error ProposalAlreadyScheduled(uint256 proposalId);
    error ProposalNotScheduled(uint256 proposalId);
    error ProposalTimelockNotReached(uint256 proposalId);
    error ParamLengthsMismatch();
    error AddressZeroNotAllowed();
    error SenderNotGovernance(address sender);
    error SenderNotGovernanceOrOwner(address sender);
    error InvalidRequirement(uint256 ownerCount, uint256 required);
    error Paused();
    error OnlyPauser();
}

/// @dev Error from ExternalCall library.
interface IExternalCallErrors {
    error ExecutionFailed();
}

contract MultiSigTest is TestAccountDeployHelper, MultiSigHelper {
    // =========================================================================
    //                          STATE
    // =========================================================================

    IMultiSigFull internal msig;
    address internal owner1;
    address internal owner2;
    address internal nonOwner;
    address internal mockPauserAddr;
    address[] internal owners;
    uint256 internal constant REQUIRED_SIGS = 2;
    uint256 internal delay;

    // Events for expectEmit
    event CeloDeposited(address indexed sender, uint256 value);
    event GovernanceTransactionExecuted(uint256 index, bytes returnData);

    // =========================================================================
    //                          SETUP
    // =========================================================================

    function setUp() public {
        // Deploy MultiSig + PausableTest
        deployTestMultiSig();
        deployTestPausable();

        msig = IMultiSigFull(address(multiSig));
        delay = 7 * DAY;

        // Set up canonical registry so MultiSig governance functions work
        _setupCanonicalRegistry();

        // Set MultiSig as pauser for PausableTest
        pausableTest.setPauser(address(multiSig));

        // Named accounts
        owner1 = multisigOwner0;
        owner2 = multisigOwner1;
        (nonOwner,) = randomSigner(100 ether);
        (mockPauserAddr,) = randomSigner(100 ether);

        owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
    }

    function _setupCanonicalRegistry() internal {
        // Deploy MockRegistry to temp address just to get runtime code
        vm.startPrank(deployer);
        address tempRegistry = _deployMockRegistry();
        vm.stopPrank();

        // Copy runtime code to canonical address 0xce10
        bytes memory runtimeCode = _getRuntimeCode(tempRegistry);
        IVmExt(address(vm)).etch(REGISTRY_ADDRESS, runtimeCode);

        // Set deployer as owner at slot 0 (Ownable._owner)
        IVmExt(address(vm)).store(
            REGISTRY_ADDRESS,
            bytes32(0),
            bytes32(uint256(uint160(deployer)))
        );

        // Deploy MockGovernance and register it via direct call on 0xce10
        mockGovernance = new MockGovernance();

        vm.prank(deployer);
        IRegistry(REGISTRY_ADDRESS).setAddressFor("Governance", address(mockGovernance));
    }

    function _getRuntimeCode(address target) internal view returns (bytes memory code) {
        assembly {
            let size := extcodesize(target)
            code := mload(0x40)
            mstore(code, size)
            extcodecopy(target, add(code, 0x20), 0, size)
            mstore(0x40, add(add(code, 0x20), size))
        }
    }

    // =========================================================================
    //                     HELPER FUNCTIONS
    // =========================================================================

    function _submitProposal(
        address signer,
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory payloads
    ) internal returns (uint256) {
        vm.prank(signer);
        return msig.submitProposal(destinations, values, payloads);
    }

    function _executeMultisigProposal(
        IMultiSigFull ms,
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 _delay,
        address signer1,
        address signer2
    ) internal {
        vm.prank(signer1);
        uint256 proposalId = ms.submitProposal(destinations, values, payloads);

        if (!ms.isFullyConfirmed(proposalId)) {
            vm.prank(signer2);
            ms.confirmProposal(proposalId);
        }

        vm.warp(block.timestamp + _delay + 1);
        vm.prank(signer2);
        ms.executeProposal(proposalId);
    }

    /// @dev Deploy a new MultiSig behind proxy (for initialize tests).
    ///      Reuses the existing impl from the already-deployed proxy.
    function _multiSigInitialize(
        address[] memory _owners,
        uint256 _required
    ) internal returns (address) {
        // Read impl address from existing proxy (EIP-1967 implementation slot)
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 implAddrBytes = vm.load(address(multiSig), implSlot);
        address msImpl = address(uint160(uint256(implAddrBytes)));

        bytes memory initData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address[],uint256,uint256)")),
            _owners,
            _required,
            7 * DAY
        );
        ERC1967Proxy proxy = new ERC1967Proxy(msImpl, initData);
        return address(proxy);
    }

    function _singleAddress(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _singleUint(uint256 v) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = v;
    }

    function _singleBytes(bytes memory b) internal pure returns (bytes[] memory arr) {
        arr = new bytes[](1);
        arr[0] = b;
    }

    function _addOwnerPayload(address newOwner) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IMultiSigFull.addOwner.selector, newOwner);
    }

    // =========================================================================
    //                       #constructor (1)
    // =========================================================================

    function test_Constructor_ShouldHaveSetMinDelayTo3Days() public {
        assertEq(msig.minDelay(), 3 * DAY);
    }

    // =========================================================================
    //                       #initialize (7)
    // =========================================================================

    function test_Initialize_ShouldHaveSetOwners() public {
        address[] memory currentOwners = msig.getOwners();
        assertEq(currentOwners.length, owners.length);
        assertEq(currentOwners[0], owners[0]);
        assertEq(currentOwners[1], owners[1]);
    }

    function test_Initialize_ShouldHaveSetDelay() public {
        assertEq(msig.delay(), delay);
    }

    function test_Initialize_ShouldHaveSetRequired() public {
        assertEq(msig.required(), REQUIRED_SIGS);
    }

    function test_Initialize_ShouldNotBeCallableAgain() public {
        vm.expectRevert("Initializable: contract is already initialized");
        msig.initialize(owners, REQUIRED_SIGS, 3 * DAY);
    }

    function test_Initialize_ShouldFailIfOwnersCountIsZero() public {
        address[] memory emptyOwners = new address[](0);
        vm.expectRevert();
        _multiSigInitialize(emptyOwners, 10);
    }

    function test_Initialize_ShouldFailIfOwnersLessThanRequired() public {
        vm.expectRevert();
        _multiSigInitialize(owners, 10);
    }

    function test_Initialize_ShouldFailIfRequiredIsZero() public {
        vm.expectRevert();
        _multiSigInitialize(owners, 0);
    }

    // =========================================================================
    //                    #fallback function (2)
    // =========================================================================

    function test_Fallback_WhenReceivingCeloEmitsDepositEvent() public {
        uint256 value = 100;
        vm.deal(owner1, value);

        vm.expectEmit(true, false, false, true);
        emit CeloDeposited(owner1, value);

        vm.prank(owner1);
        (bool ok,) = address(multiSig).call{value: value}("");
        assertTrue(ok);
    }

    function test_Fallback_WhenReceiving0ValueDoesNotEmitEvent() public {
        // Send 0 value — no CeloDeposited event should be emitted, tx succeeds
        vm.prank(owner1);
        (bool ok,) = address(multiSig).call{value: 0}("");
        assertTrue(ok);
    }

    // =========================================================================
    //                    #submitProposal (8)
    // =========================================================================

    function test_SubmitProposal_AllowsOwnerToSubmit() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 proposalId = _submitProposal(
            owner1,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );

        (address[] memory destinations,,) = msig.getProposal(proposalId);
        assertEq(destinations.length, 1);
        assertEq(destinations[0], address(multiSig));
    }

    function test_SubmitProposal_SetsProposalAsConfirmedBySender() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 proposalId = _submitProposal(
            owner1,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );
        assertTrue(msig.isConfirmedBy(proposalId, owner1));
    }

    function test_SubmitProposal_UpdatesProposalCount() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        _submitProposal(
            owner1,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );
        assertEq(msig.proposalCount(), 1);
    }

    function test_SubmitProposal_DoesNotAllowSubmitToNullAddress() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.AddressZeroNotAllowed.selector));
        vm.prank(owner1);
        msig.submitProposal(
            _singleAddress(ADDRESS_ZERO),
            _singleUint(0),
            _singleBytes(txData)
        );
    }

    function test_SubmitProposal_DoesNotAllowNonOwnerToSubmit() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.OwnerDoesNotExist.selector, nonOwner));
        vm.prank(nonOwner);
        msig.submitProposal(
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );
    }

    function test_SubmitProposal_FailsWhenDestinationsDoesNotMatchValues() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256[] memory vals = new uint256[](2);
        vals[0] = 0;
        vals[1] = 1;
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ParamLengthsMismatch.selector));
        vm.prank(owner1);
        msig.submitProposal(
            _singleAddress(address(multiSig)),
            vals,
            _singleBytes(txData)
        );
    }

    function test_SubmitProposal_FailsWhenDestinationsDoesNotMatchPayloads() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = txData;
        payloads[1] = txData;
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ParamLengthsMismatch.selector));
        vm.prank(owner1);
        msig.submitProposal(
            _singleAddress(address(multiSig)),
            _singleUint(0),
            payloads
        );
    }

    function test_SubmitProposal_AllowsMultipleTransactions() public {
        bytes memory txData1 = _addOwnerPayload(nonOwner);
        bytes memory txData2 = abi.encodeWithSelector(IMultiSigFull.changeDelay.selector, 9 * DAY);

        address[] memory dests = new address[](2);
        dests[0] = address(multiSig);
        dests[1] = address(multiSig);
        uint256[] memory vals = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = txData1;
        payloads[1] = txData2;

        uint256 proposalId = _submitProposal(owner1, dests, vals, payloads);

        (address[] memory retDests,,) = msig.getProposal(proposalId);
        assertEq(retDests.length, 2);
    }

    // =========================================================================
    //                    #confirmProposal (5)
    // =========================================================================

    function test_ConfirmProposal_AllowsOwnerToConfirm() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        assertTrue(msig.isConfirmedBy(pid, owner2));
    }

    function test_ConfirmProposal_SchedulesOnceEnoughConfirmations() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        assertTrue(msig.isScheduled(pid));
    }

    function test_ConfirmProposal_StoresCorrectTimestamp() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);

        uint256 expectedTimestamp = block.timestamp + msig.delay();
        assertEq(msig.getTimestamp(pid), expectedTimestamp);
    }

    function test_ConfirmProposal_DoesNotAllowOwnerToConfirmTwice() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalAlreadyConfirmed.selector, uint256(0), owner1));
        vm.prank(owner1);
        msig.confirmProposal(pid);
    }

    function test_ConfirmProposal_DoesNotAllowNonOwnerToConfirm() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.OwnerDoesNotExist.selector, nonOwner));
        vm.prank(nonOwner);
        msig.confirmProposal(pid);
    }

    // =========================================================================
    //                    #scheduleProposal (2)
    // =========================================================================

    function test_ScheduleProposal_CannotScheduleTwice() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid); // auto-schedules

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalAlreadyScheduled.selector, uint256(0)));
        vm.prank(owner1);
        msig.scheduleProposal(pid);
    }

    function test_ScheduleProposal_CannotScheduleNotFullyConfirmed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalNotFullyConfirmed.selector, uint256(0)));
        vm.prank(owner1);
        msig.scheduleProposal(pid);
    }

    // =========================================================================
    //                    #executeProposal (6)
    // =========================================================================

    function test_ExecuteProposal_OwnerCanExecuteAfterTimelock() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);
        vm.prank(owner2);
        msig.executeProposal(pid);
        assertEq(msig.getTimestamp(pid), 1);
    }

    function test_ExecuteProposal_AnyAccountCanExecuteAfterTimelock() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        (address randomAcc,) = randomSigner(100 ether);
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);
        vm.prank(randomAcc);
        msig.executeProposal(pid);
        assertEq(msig.getTimestamp(pid), 1);
    }

    function test_ExecuteProposal_FailsToExecuteTwice() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);
        vm.prank(owner2);
        msig.executeProposal(pid);

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalNotScheduled.selector, uint256(0)));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_ExecuteProposal_FailsWhenTimelockNotPassed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalTimelockNotReached.selector, uint256(0)));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_ExecuteProposal_FailsWhenNotScheduled() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.warp(block.timestamp + delay + 1);
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalNotScheduled.selector, uint256(0)));
        vm.prank(owner1);
        msig.executeProposal(pid);
    }

    function test_ExecuteProposal_ExecutesManyTransactions() public {
        bytes memory txData1 = _addOwnerPayload(nonOwner);
        bytes memory txData2 = abi.encodeWithSelector(IMultiSigFull.changeDelay.selector, 9 * DAY);

        address[] memory dests = new address[](2);
        dests[0] = address(multiSig);
        dests[1] = address(multiSig);
        uint256[] memory vals = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = txData1;
        payloads[1] = txData2;

        _executeMultisigProposal(msig, dests, vals, payloads, delay, owner1, owner2);

        assertEq(msig.delay(), 9 * DAY);
        assertTrue(msig.isOwner(nonOwner));
    }

    // =========================================================================
    //                       #setPauser (4)
    // =========================================================================

    function test_SetPauser_AllowsMultiSigToSetPauser() public {
        bytes memory payload = abi.encodeWithSelector(IMultiSigFull.setPauser.selector, nonOwner);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(payload),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.pauser(), nonOwner);
    }

    function test_SetPauser_AllowsMultiSigToSetItselfAsPauser() public {
        bytes memory payload = abi.encodeWithSelector(IMultiSigFull.setPauser.selector, address(multiSig));
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(payload),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.pauser(), address(multiSig));
    }

    function test_SetPauser_DoesNotAllowOwnerToSetPauser() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, owner1));
        vm.prank(owner1);
        msig.setPauser(nonOwner);
    }

    function test_SetPauser_DoesNotAllowNonOwnerToSetPauser() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.setPauser(nonOwner);
    }

    // =========================================================================
    //                     #pauseContracts (6)
    // =========================================================================

    function test_PauseContracts_CanBeCalledByOwner() public {
        vm.prank(owner1);
        msig.pauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_PauseContracts_CanBeCalledByOwnerToPauseMultisig() public {
        // Set MultiSig as its own pauser (impersonate wallet)
        vm.prank(address(multiSig));
        msig.setPauser(address(multiSig));

        vm.prank(owner1);
        msig.pauseContracts(_singleAddress(address(multiSig)));
        assertTrue(msig.isPaused());
    }

    function test_PauseContracts_CanBeCalledByDifferentOwner() public {
        vm.prank(owner2);
        msig.pauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_PauseContracts_CanBeCalledByGovernance() public {
        vm.prank(address(mockGovernance));
        msig.pauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_PauseContracts_RevertsWhenMultiSigPauserIsNotMultiSig() public {
        // Set governance as pauser (not multisig itself)
        vm.prank(address(multiSig));
        msig.setPauser(address(mockGovernance));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.OnlyPauser.selector));
        vm.prank(owner1);
        msig.pauseContracts(_singleAddress(address(multiSig)));
        assertFalse(pausableTest.isPaused());
    }

    function test_PauseContracts_RevertsWhenCalledByNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernanceOrOwner.selector, nonOwner));
        vm.prank(nonOwner);
        msig.pauseContracts(_singleAddress(address(pausableTest)));
        assertFalse(pausableTest.isPaused());
    }

    // =========================================================================
    //                    #unpauseContracts (4)
    // =========================================================================

    function _pausePausableTest() internal {
        vm.prank(owner1);
        msig.pauseContracts(_singleAddress(address(pausableTest)));
    }

    function test_UnpauseContracts_CanBeCalledByGovernance() public {
        _pausePausableTest();
        vm.prank(address(mockGovernance));
        msig.unpauseContracts(_singleAddress(address(pausableTest)));
        assertFalse(pausableTest.isPaused());
    }

    function test_UnpauseContracts_RevertsWhenCalledByOwner() public {
        _pausePausableTest();
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, owner1));
        vm.prank(owner1);
        msig.unpauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_UnpauseContracts_RevertsWhenCalledByMultiSig() public {
        _pausePausableTest();
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, address(multiSig)));
        vm.prank(address(multiSig));
        msig.unpauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_UnpauseContracts_RevertsWhenCalledByNonOwner() public {
        _pausePausableTest();
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, nonOwner));
        vm.prank(nonOwner);
        msig.unpauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    // =========================================================================
    //                    #revokeConfirmation (3)
    // =========================================================================

    function test_RevokeConfirmation_AllowsOwnerToRevoke() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner1);
        msig.revokeConfirmation(pid);
        assertFalse(msig.isConfirmedBy(pid, owner1));
    }

    function test_RevokeConfirmation_DoesNotAllowNonOwnerToRevoke() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.OwnerDoesNotExist.selector, nonOwner));
        vm.prank(nonOwner);
        msig.revokeConfirmation(pid);
    }

    function test_RevokeConfirmation_DoesNotAllowOwnerToRevokeBeforeConfirming() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalNotConfirmed.selector, uint256(0), owner2));
        vm.prank(owner2);
        msig.revokeConfirmation(pid);
    }

    // =========================================================================
    //                       #addOwner (4)
    // =========================================================================

    function test_AddOwner_AllowsNewOwnerViaMultiSig() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertTrue(msig.isOwner(nonOwner));

        address[] memory currentOwners = msig.getOwners();
        assertEq(currentOwners.length, 3);
        assertEq(currentOwners[0], owner1);
        assertEq(currentOwners[1], owner2);
        assertEq(currentOwners[2], nonOwner);
    }

    function test_AddOwner_DoesNotAllowExternalAccountToAdd() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.addOwner(nonOwner);
    }

    function test_AddOwner_DoesNotAllowAddingNullAddress() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.addOwner.selector, ADDRESS_ZERO);

        // Submit, confirm, warp
        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_AddOwner_FailsWhenMaxOwnersReached() public {
        // Already 2 owners. MAX_OWNER_COUNT = 50. Need 48 more to reach 50.
        uint256 count = 48;
        address[] memory dests = new address[](count);
        uint256[] memory vals = new uint256[](count);
        bytes[] memory payloads = new bytes[](count);

        for (uint256 i = 0; i < count; i++) {
            (address newOwner,) = randomSigner(100 ether);
            dests[i] = address(multiSig);
            payloads[i] = _addOwnerPayload(newOwner);
        }

        _executeMultisigProposal(msig, dests, vals, payloads, delay, owner1, owner2);

        // Now try to add one more (51st owner)
        (address oneMore,) = randomSigner(100 ether);
        bytes memory payload = _addOwnerPayload(oneMore);

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(payload));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    // =========================================================================
    //                      #removeOwner (4)
    // =========================================================================

    function test_RemoveOwner_AllowsOwnerToBeRemoved() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.removeOwner.selector, owner2);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertFalse(msig.isOwner(owner2));
    }

    function test_RemoveOwner_ReducesRequiredIfEqualToOwners() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.removeOwner.selector, owner2);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.required(), 1);
    }

    function test_RemoveOwner_DoesNotAllowExternalAccountToRemove() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.removeOwner(owner2);
    }

    function test_RemoveOwner_CannotRemoveLastOwner() public {
        // First remove owner2
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.removeOwner.selector, owner2);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );

        // Now try to remove owner1 (last owner) — required is now 1
        bytes memory txData2 = abi.encodeWithSelector(IMultiSigFull.removeOwner.selector, owner1);

        // With required=1, submitProposal auto-confirms and auto-schedules
        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData2));
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner1);
        msig.executeProposal(pid);
    }

    // =========================================================================
    //                     #replaceOwner (4)
    // =========================================================================

    function test_ReplaceOwner_AllowsOwnerToBeReplaced() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.replaceOwner.selector, owner2, nonOwner);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );

        assertTrue(msig.isOwner(nonOwner));
        assertFalse(msig.isOwner(owner2));

        address[] memory currentOwners = msig.getOwners();
        assertEq(currentOwners.length, 2);
        assertEq(currentOwners[0], owner1);
        assertEq(currentOwners[1], nonOwner);
    }

    function test_ReplaceOwner_DoesNotAllowExternalAccountToReplace() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.replaceOwner(owner2, nonOwner);
    }

    function test_ReplaceOwner_DoesNotAllowReplacingWithNullAddress() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.replaceOwner.selector, owner2, ADDRESS_ZERO);

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_ReplaceOwner_DoesNotAllowReplacingWithExistingOwner() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.replaceOwner.selector, owner1, owner2);

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    // =========================================================================
    //                   #changeRequirement (3)
    // =========================================================================

    function test_ChangeRequirement_AllowsChangeViaMultiSig() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.changeRequirement.selector, uint256(1));
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.required(), 1);
    }

    function test_ChangeRequirement_DoesNotAllowExternalAccountToChange() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.changeRequirement(3);
    }

    function test_ChangeRequirement_FailsIfRequiredMoreThanOwners() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.changeRequirement.selector, uint256(5));

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    // =========================================================================
    //                      #changeDelay (3)
    // =========================================================================

    function test_ChangeDelay_AllowsChangeViaMultiSig() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.changeDelay.selector, 4 * DAY);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.delay(), 4 * DAY);
    }

    function test_ChangeDelay_FailsToChangeBelowMinDelay() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.changeDelay.selector, 1 * DAY);

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_ChangeDelay_DoesNotAllowExternalAccountToChange() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.changeDelay(4 * DAY);
    }

    // =========================================================================
    //                       #getOwners (1)
    // =========================================================================

    function test_GetOwners_ReturnsOwners() public {
        address[] memory currentOwners = msig.getOwners();
        assertEq(currentOwners.length, owners.length);
        assertEq(currentOwners[0], owners[0]);
        assertEq(currentOwners[1], owners[1]);
    }

    // =========================================================================
    //                    #getConfirmations (1)
    // =========================================================================

    function test_GetConfirmations_ReturnsConfirmations() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        address[] memory confirmations = msig.getConfirmations(pid);
        assertEq(confirmations.length, 1);
        assertEq(confirmations[0], owner1);
    }

    // =========================================================================
    //                   #isFullyConfirmed (2)
    // =========================================================================

    function test_IsFullyConfirmed_ReturnsTrueWhenFullyConfirmed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        assertTrue(msig.isFullyConfirmed(pid));
    }

    function test_IsFullyConfirmed_ReturnsFalseWhenNotFullyConfirmed() public {
        // proposalId 0 doesn't exist yet, isFullyConfirmed returns false
        assertFalse(msig.isFullyConfirmed(0));
    }

    // =========================================================================
    //                    #isConfirmedBy (2)
    // =========================================================================

    function test_IsConfirmedBy_ReturnsTrueWhenConfirmed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        assertTrue(msig.isConfirmedBy(pid, owner1));
    }

    function test_IsConfirmedBy_ReturnsFalseWhenNotConfirmed() public {
        // proposalId 0, owner1 — no proposals submitted yet
        assertFalse(msig.isConfirmedBy(0, owner1));
    }

    // =========================================================================
    //              #isProposalTimelockReached (4)
    // =========================================================================

    function test_IsProposalTimelockReached_ReturnsTrueWhenReached() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);
        assertTrue(msig.isProposalTimelockReached(pid));
    }

    function test_IsProposalTimelockReached_ReturnsFalseForUnscheduled() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        assertFalse(msig.isProposalTimelockReached(pid));
    }

    function test_IsProposalTimelockReached_ReturnsFalseForUnscheduledAfterDelay() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.warp(block.timestamp + delay + 1);
        assertFalse(msig.isProposalTimelockReached(pid));
    }

    function test_IsProposalTimelockReached_ReturnsFalseWhenTimelockNotElapsed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        // Don't warp — timelock not elapsed
        assertFalse(msig.isProposalTimelockReached(pid));
    }

    // =========================================================================
    //              #governanceProposeAndExecute (8)
    // =========================================================================

    function test_GovernanceProposeAndExecute_SucceedsForGovernance() public {
        address[] memory emptyDests = new address[](0);
        uint256[] memory emptyVals = new uint256[](0);
        bytes[] memory emptyPayloads = new bytes[](0);

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(emptyDests, emptyVals, emptyPayloads);
    }

    function test_GovernanceProposeAndExecute_AllowsGovernanceToCallContract() public {
        ProposalTester proposalTester = new ProposalTester();
        bytes memory txData = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(42));

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(
            _singleAddress(address(proposalTester)),
            _singleUint(0),
            _singleBytes(txData)
        );

        (address caller, uint256 value, uint256 arg) = proposalTester.getCall(0);
        assertEq(caller, address(multiSig));
        assertEq(value, 0);
        assertEq(arg, 42);
    }

    function test_GovernanceProposeAndExecute_AllowsGovernanceToSendValue() public {
        ProposalTester proposalTester = new ProposalTester();

        // Fund multiSig with 300 wei
        vm.deal(owner1, 300);
        vm.prank(owner1);
        (bool ok,) = address(multiSig).call{value: 300}("");
        assertTrue(ok);

        bytes memory txData = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(42));

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(
            _singleAddress(address(proposalTester)),
            _singleUint(100),
            _singleBytes(txData)
        );

        assertEq(address(multiSig).balance, 200);
        assertEq(address(proposalTester).balance, 100);

        (address caller, uint256 value, uint256 arg) = proposalTester.getCall(0);
        assertEq(caller, address(multiSig));
        assertEq(value, 100);
        assertEq(arg, 42);
    }

    function test_GovernanceProposeAndExecute_AllowsGovernanceToCallMultipleFunctions() public {
        ProposalTester proposalTester = new ProposalTester();
        bytes memory txData1 = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(42));
        bytes memory txData2 = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(1337));

        address[] memory dests = new address[](2);
        dests[0] = address(proposalTester);
        dests[1] = address(proposalTester);
        uint256[] memory vals = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = txData1;
        payloads[1] = txData2;

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(dests, vals, payloads);

        (address caller1, uint256 val1, uint256 arg1) = proposalTester.getCall(0);
        (address caller2, uint256 val2, uint256 arg2) = proposalTester.getCall(1);
        assertEq(caller1, address(multiSig));
        assertEq(val1, 0);
        assertEq(arg1, 42);
        assertEq(caller2, address(multiSig));
        assertEq(val2, 0);
        assertEq(arg2, 1337);
    }

    function test_GovernanceProposeAndExecute_AllowsGovernanceToExecuteMultiSigFunction() public {
        bytes memory txData = _addOwnerPayload(nonOwner);

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );

        assertTrue(msig.isOwner(nonOwner));
    }

    function test_GovernanceProposeAndExecute_EmitsGovernanceTransactionExecutedEvent() public {
        ProposalTester proposalTester = new ProposalTester();
        bytes memory txData = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(42));

        vm.expectEmit(false, false, false, true);
        emit GovernanceTransactionExecuted(0, hex"");

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(
            _singleAddress(address(proposalTester)),
            _singleUint(0),
            _singleBytes(txData)
        );
    }

    function test_GovernanceProposeAndExecute_RevertsForOwner() public {
        address[] memory emptyDests = new address[](0);
        uint256[] memory emptyVals = new uint256[](0);
        bytes[] memory emptyPayloads = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, owner1));
        vm.prank(owner1);
        msig.governanceProposeAndExecute(emptyDests, emptyVals, emptyPayloads);
    }

    function test_GovernanceProposeAndExecute_RevertsForRandomAddress() public {
        address[] memory emptyDests = new address[](0);
        uint256[] memory emptyVals = new uint256[](0);
        bytes[] memory emptyPayloads = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, nonOwner));
        vm.prank(nonOwner);
        msig.governanceProposeAndExecute(emptyDests, emptyVals, emptyPayloads);
    }

    // =========================================================================
    //                      when paused (4)
    // =========================================================================

    function _setupPaused() internal returns (uint256 submittedProposal) {
        // Submit a proposal (confirmed only by owner1, not fully confirmed)
        submittedProposal = _submitProposal(
            owner1,
            _singleAddress(nonOwner),
            _singleUint(0),
            _singleBytes(hex"")
        );

        // Set mockPauserAddr as the pauser via multisig proposal
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.setPauser.selector, mockPauserAddr);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );

        // Pause the multisig
        vm.prank(mockPauserAddr);
        msig.pause();
    }

    function test_WhenPaused_CantCallSubmitProposal() public {
        _setupPaused();

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.Paused.selector));
        vm.prank(owner1);
        msig.submitProposal(_singleAddress(nonOwner), _singleUint(0), _singleBytes(hex""));
    }

    function test_WhenPaused_CantCallConfirmProposal() public {
        uint256 submittedProposal = _setupPaused();

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.Paused.selector));
        vm.prank(owner2);
        msig.confirmProposal(submittedProposal);
    }

    function test_WhenPaused_CantCallScheduleProposal() public {
        uint256 submittedProposal = _setupPaused();

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.Paused.selector));
        vm.prank(owner2);
        msig.scheduleProposal(submittedProposal);
    }

    function test_WhenPaused_CantCallExecuteProposal() public {
        uint256 submittedProposal = _setupPaused();

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.Paused.selector));
        vm.prank(owner2);
        msig.executeProposal(submittedProposal);
    }
}
