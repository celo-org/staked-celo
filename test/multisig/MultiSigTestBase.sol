// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/deploy/TestAccountDeployHelper.sol";
import "../helpers/MultiSigHelper.sol";

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
    function getProposal(uint256 proposalId)
        external
        view
        returns (address[] memory destinations, uint256[] memory values, bytes[] memory payloads);
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

/// @dev Additional VM cheatcodes not in CeloTestVm. Cast onto the same cheatcode address.
interface IVmExt {
    /// @dev Layout of a recorded log, matching the cheatcode ABI.
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function etch(address target, bytes calldata code) external;
    function store(address target, bytes32 slot, bytes32 value) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
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

/**
 * @title MultiSigTestBase
 * @notice Shared fixture for the port of legacy/test-ts/multisig.test.ts.
 * @dev Ports the `beforeEach` of the top-level `describe("MultiSig")`: a MultiSig with two
 *      owners and a 7 day delay, a PausableTest whose pauser is that MultiSig, and a
 *      MockGovernance registered on the canonical registry so the governance-gated entry
 *      points resolve. Each `describe` block of the original lives in its own `.t.sol`.
 */
abstract contract MultiSigTestBase is TestAccountDeployHelper, MultiSigHelper {
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
        IVmExt(address(vm)).store(REGISTRY_ADDRESS, bytes32(0), bytes32(uint256(uint160(deployer))));

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
}
