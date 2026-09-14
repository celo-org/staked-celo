// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../CeloTestHelper.sol";
import "../interfaces/IMultiSig.sol";

// Safe imports (no Initializable collision)
import "../../../contracts/StakedCelo.sol";
import "../../../contracts/Vote.sol";
import "../../../contracts/RebasedStakedCelo.sol";
import "../../../contracts/mock/MockManager.sol";
import "../../../contracts/mock/MockStakedCelo.sol";
import "../../../contracts/mock/MockVote.sol";
import "../../../contracts/test/PausableTest.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// NOTE: Do NOT import contracts/common/MultiSig.sol (Initializable collision with non-upgradeable OZ)
// NOTE: Do NOT import contracts/mock/MockRegistry.sol (Initializable collision via Ownable)

/// @dev Extended VM interface for getCode (not declared in CeloTestVm).
///      The standard Foundry VM at the cheatcode address supports getCode.
interface IVmExtended {
    function getCode(string calldata artifactPath) external returns (bytes memory);
}

/// @dev Minimal Ownable view interface, used to find out who may write to a registry.
///      Declared here because Ownable cannot be imported (Initializable collision).
interface IOwnable {
    function owner() external view returns (address);
}

/// @dev Minimal mock for Celo's core Accounts contract.
///      Satisfies Account.initialize() which calls getAccounts().createAccount().
contract MockAccountsCelo {
    function createAccount() external pure returns (bool) {
        return true;
    }
}

/**
 * @title TestAccountDeployHelper
 * @notice Abstract contract providing deploy fixtures for Wave 3 simple unit tests.
 *         Replicates the 15 test deploy scripts from deploy/test/*.ts.
 * @dev Extends CeloTestHelper. Each deployTestXxx() function deploys MockRegistry,
 *      required mock Celo contracts, and the contract under test behind ERC1967Proxy.
 *      Every fixture that deploys a registry-dependent contract also has a
 *      deployTestXxx(address registry) overload that skips the mock Celo
 *      infrastructure and wires the contracts to the given registry instead —
 *      for example the Celo core registry of a devchain. The overloads never
 *      write to that registry, since they do not own it.
 *
 *      UNSAFE contracts (MockRegistry, MultiSig) are deployed via vm.getCode()
 *      to avoid Initializable name collision between OZ contracts and
 *      OZ contracts-upgradeable.
 */
abstract contract TestAccountDeployHelper is CeloTestHelper {
    // =========================================================================
    //                          STATE VARIABLES
    // =========================================================================

    // -- MockRegistry (deployed via vm.getCode, not imported) --
    address public mockRegistryAddr;

    // -- Mock Celo core contracts --
    MockElection public mockElection;
    MockLockedGold public mockLockedGold;
    MockValidators public mockValidators;
    MockGovernance public mockGovernance;
    MockAccountsCelo public mockAccountsCelo;

    // -- Mock project contracts (direct deploy, no proxy) --
    MockAccount public mockAccount;
    MockManager public mockManager;
    MockStakedCelo public mockStakedCelo;
    MockVote public mockVote;

    // -- Protocol contracts behind proxies --
    Manager public manager;
    Account public account;
    StakedCelo public stakedCelo;
    Vote public vote;
    MockGroupHealth public mockGroupHealth;
    MockDefaultStrategy public mockDefaultStrategy;
    SpecificGroupStrategy public specificGroupStrategy;
    RebasedStakedCelo public rebasedStakedCelo;

    // -- Direct deploy (no proxy) --
    PausableTest public pausableTest;

    // -- MultiSig (via interface, deployed via vm.getCode) --
    IMultiSig public multiSig;

    // =========================================================================
    //                     INTERNAL DEPLOY HELPERS
    // =========================================================================

    /// @dev Deploy MockRegistry via vm.getCode to avoid Initializable collision.
    ///      The owner of the deployed MockRegistry is the current msg.sender
    ///      (deployer when called under vm.startPrank(deployer)).
    function _deployMockRegistry() internal returns (address) {
        bytes memory code = IVmExtended(address(vm)).getCode("MockRegistry.sol:MockRegistry");
        address addr;
        assembly {
            addr := create(0, add(code, 0x20), mload(code))
        }
        require(addr != address(0), "MockRegistry deploy failed");
        return addr;
    }

    /// @dev Deploy the mock Celo core contracts. Must be called while pranked as
    ///      `deployer` so that they match the Hardhat fixtures' deployer.
    function _deployCoreMocks() internal {
        mockElection = new MockElection();
        mockLockedGold = new MockLockedGold();
        mockValidators = new MockValidators();
        mockGovernance = new MockGovernance();
        mockAccountsCelo = new MockAccountsCelo();
    }

    /// @dev Register the mock Celo core contracts deployed by _deployCoreMocks()
    ///      in the given registry. Must be called outside of any prank.
    function _registerCoreMocks(address registryAddr) internal {
        _setRegistryAddress(registryAddr, "Election", address(mockElection));
        _setRegistryAddress(registryAddr, "LockedGold", address(mockLockedGold));
        _setRegistryAddress(registryAddr, "Validators", address(mockValidators));
        _setRegistryAddress(registryAddr, "Governance", address(mockGovernance));
        _setRegistryAddress(registryAddr, "Accounts", address(mockAccountsCelo));
    }

    /// @dev Deploy MockRegistry plus the mock Celo core contracts as `deployer` and
    ///      register them. Must be called outside of any prank.
    /// @return registryAddr Address of the freshly deployed MockRegistry.
    function _deployMockCeloInfrastructure() internal returns (address registryAddr) {
        vm.startPrank(deployer);
        registryAddr = _deployMockRegistry();
        _deployCoreMocks();
        vm.stopPrank();

        _registerCoreMocks(registryAddr);
    }

    /// @dev Write a registry entry as the registry owner. Works both for MockRegistry
    ///      (owned by `deployer`) and for the Celo core registry of a devchain
    ///      (owned by the governance multisig). Must be called outside of any prank.
    function _setRegistryAddress(
        address registry,
        string memory id,
        address addr
    ) internal {
        address registryOwner = IOwnable(registry).owner();
        vm.prank(registryOwner);
        IRegistry(registry).setAddressFor(id, addr);
    }

    /// @dev Deploy Manager behind ERC1967Proxy, initialized with registry and owner.
    function _deployManagerBehindProxy(address registryAddr) internal returns (Manager) {
        Manager impl = new Manager();
        bytes memory data = abi.encodeWithSelector(Manager.initialize.selector, registryAddr, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        return Manager(address(proxy));
    }

    // -------------------------------------------------------------------------
    // One function per proxy so that each stack frame stays small enough to
    // compile without via_ir. All of them must run while pranked as `deployer`.
    // -------------------------------------------------------------------------

    /// @dev Account — initialize(registry, managerProxy, owner).
    ///      REQUIRES: "Accounts" resolvable in the registry, because
    ///      Account.initialize() calls getAccounts().createAccount().
    function _deployAccountProxy(address registryAddr) private {
        Account impl = new Account();
        bytes memory data = abi.encodeWithSelector(
            Account.initialize.selector,
            registryAddr,
            address(manager),
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        account = Account(payable(address(proxy)));
    }

    /// @dev StakedCelo — initialize(managerProxy, owner).
    function _deployStakedCeloProxy() private {
        StakedCelo impl = new StakedCelo();
        bytes memory data = abi.encodeWithSelector(
            StakedCelo.initialize.selector,
            address(manager),
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        stakedCelo = StakedCelo(address(proxy));
    }

    /// @dev Vote — initialize(registry, owner, managerProxy).
    function _deployVoteProxy(address registryAddr) private {
        Vote impl = new Vote();
        bytes memory data = abi.encodeWithSelector(
            Vote.initialize.selector,
            registryAddr,
            owner,
            address(manager)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        vote = Vote(address(proxy));
    }

    /// @dev MockGroupHealth — initialize(registry, owner).
    function _deployMockGroupHealthProxy(address registryAddr) private {
        MockGroupHealth impl = new MockGroupHealth();
        bytes memory data = abi.encodeWithSelector(
            GroupHealth.initialize.selector,
            registryAddr,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        mockGroupHealth = MockGroupHealth(address(proxy));
    }

    /// @dev MockDefaultStrategy — initialize(owner, managerProxy).
    ///      NOTE: AddressSortedLinkedList library is linked automatically by Forge.
    function _deployMockDefaultStrategyProxy() private {
        MockDefaultStrategy impl = new MockDefaultStrategy();
        bytes memory data = abi.encodeWithSelector(
            DefaultStrategy.initialize.selector,
            owner,
            address(manager)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        mockDefaultStrategy = MockDefaultStrategy(payable(address(proxy)));
    }

    /// @dev SpecificGroupStrategy — initialize(owner, managerProxy).
    function _deploySpecificGroupStrategyProxy() private {
        SpecificGroupStrategy impl = new SpecificGroupStrategy();
        bytes memory data = abi.encodeWithSelector(
            SpecificGroupStrategy.initialize.selector,
            owner,
            address(manager)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        specificGroupStrategy = SpecificGroupStrategy(address(proxy));
    }

    // =========================================================================
    //                        FIXTURE FUNCTIONS
    // =========================================================================

    /// @notice Deploy PausableTest contract (no proxy, direct deploy).
    ///         Replicates deploy/test/pausable.ts [tag: TestPausable].
    function deployTestPausable() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);
        pausableTest = new PausableTest();
        vm.stopPrank();
    }

    /// @notice Deploy MultiSig behind proxy with 2 owners, required=2, delay=7*DAY.
    ///         Replicates deploy/test/multisig.ts [tag: TestMultiSig].
    function deployTestMultiSig() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        // Deploy MultiSig implementation via getCode (UNSAFE to import directly).
        // MultiSig constructor(uint256 _minDelay) sets minDelay on impl.
        uint256 minDelay = 3 * DAY;
        bytes memory msCode = IVmExtended(address(vm)).getCode("MultiSig.sol:MultiSig");
        bytes memory msCreation = abi.encodePacked(msCode, abi.encode(minDelay));
        address msImpl;
        assembly {
            msImpl := create(0, add(msCreation, 0x20), mload(msCreation))
        }
        require(msImpl != address(0), "MultiSig impl deploy failed");

        // Initialize via proxy: owners=[multisigOwner0, multisigOwner1], required=2, delay=7*DAY
        address[] memory msOwners = new address[](2);
        msOwners[0] = multisigOwner0;
        msOwners[1] = multisigOwner1;
        bytes memory initData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address[],uint256,uint256)")),
            msOwners,
            uint256(2),
            7 * DAY
        );
        ERC1967Proxy msProxy = new ERC1967Proxy(msImpl, initData);
        multiSig = IMultiSig(address(msProxy));

        vm.stopPrank();
    }

    /// @notice Deploy Manager behind proxy on top of a fresh MockRegistry.
    ///         Replicates deploy/test/manager.ts + mock_vote.ts [tag: TestManager].
    function deployTestManager() internal {
        _initNamedAccounts();
        mockRegistryAddr = _deployMockCeloInfrastructure();
        deployTestManager(mockRegistryAddr);
    }

    /// @notice Deploy Manager behind proxy against an existing registry.
    /// @param registry Registry the Manager resolves Celo core contracts from.
    ///        Nothing is registered in it, so it may be owned by someone else.
    function deployTestManager(address registry) internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        // MockVote (from mock_vote.ts, tag TestManager)
        mockVote = new MockVote();

        // Manager behind proxy
        manager = _deployManagerBehindProxy(registry);

        vm.stopPrank();
    }

    /// @notice Deploy Manager + Account behind proxies on top of a fresh MockRegistry.
    ///         Replicates deploy/test/account.ts + deps [tag: TestAccount].
    ///         Includes: MockGovernance (tag TestAccount), MockVote (tag TestManager).
    function deployTestAccount() internal {
        _initNamedAccounts();
        mockRegistryAddr = _deployMockCeloInfrastructure();
        deployTestAccount(mockRegistryAddr);
    }

    /// @notice Deploy Manager + Account behind proxies against an existing registry.
    /// @param registry Registry the Manager and Account resolve Celo core contracts
    ///        from. It must resolve "Accounts", because Account.initialize() calls
    ///        getAccounts().createAccount().
    function deployTestAccount(address registry) internal {
        deployTestManager(registry);

        vm.startPrank(deployer);

        // MockGovernance (from mock_governance.ts, tag TestAccount). Already deployed
        // when the mock Celo infrastructure is in use.
        if (address(mockGovernance) == address(0)) {
            mockGovernance = new MockGovernance();
        }

        // Account behind proxy — needs "Accounts" resolvable for createAccount()
        _deployAccountProxy(registry);

        vm.stopPrank();
    }

    /// @notice Deploy MockManager (direct) + StakedCelo behind proxy.
    ///         Replicates deploy/test/staked_celo.ts + mock_manager.ts [tag: TestStakedCelo].
    function deployTestStakedCelo() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        // MockManager (direct, no proxy)
        mockManager = new MockManager();

        // StakedCelo behind proxy
        StakedCelo scImpl = new StakedCelo();
        bytes memory scData = abi.encodeWithSelector(
            StakedCelo.initialize.selector,
            address(mockManager),
            owner
        );
        ERC1967Proxy scProxy = new ERC1967Proxy(address(scImpl), scData);
        stakedCelo = StakedCelo(address(scProxy));

        vm.stopPrank();
    }

    /// @notice Deploy full Vote test environment on top of a fresh MockRegistry:
    ///         Manager + Account + StakedCelo + Vote + MockGroupHealth +
    ///         MockDefaultStrategy + SpecificGroupStrategy behind proxies.
    ///         Replicates all deploy/test/*.ts with [tag: TestVote].
    function deployTestVote() internal {
        _initNamedAccounts();
        mockRegistryAddr = _deployMockCeloInfrastructure();
        deployTestVote(mockRegistryAddr);
    }

    /// @notice Deploy the full Vote test environment against an existing registry.
    /// @param registry Registry the registry-dependent contracts resolve Celo core
    ///        contracts from. It must resolve "Accounts" for Account.initialize().
    function deployTestVote(address registry) internal {
        deployTestManager(registry);

        vm.startPrank(deployer);

        _deployAccountProxy(registry);
        // StakedCelo uses the real Manager address per staked_celo.ts
        _deployStakedCeloProxy();
        _deployVoteProxy(registry);
        _deployMockGroupHealthProxy(registry);
        _deployMockDefaultStrategyProxy();
        _deploySpecificGroupStrategyProxy();

        vm.stopPrank();
    }

    /// @notice Deploy MockGroupHealth behind proxy on top of a fresh MockRegistry.
    ///         Replicates deploy/test/group_health.ts [tag: TestGroupHealth].
    function deployTestGroupHealth() internal {
        _initNamedAccounts();
        mockRegistryAddr = _deployMockCeloInfrastructure();
        deployTestGroupHealth(mockRegistryAddr);
    }

    /// @notice Deploy MockGroupHealth behind proxy against an existing registry.
    /// @param registry Registry MockGroupHealth resolves Celo core contracts from.
    function deployTestGroupHealth(address registry) internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        _deployMockGroupHealthProxy(registry);

        vm.stopPrank();
    }

    /// @notice Deploy Manager + MockDefaultStrategy behind proxy on top of a fresh
    ///         MockRegistry.
    ///         Replicates deploy/test/default_strategy.ts [tag: TestDefaultStrategy].
    ///         AddressSortedLinkedList library is auto-linked by Forge.
    function deployTestDefaultStrategy() internal {
        _initNamedAccounts();
        mockRegistryAddr = _deployMockCeloInfrastructure();
        deployTestDefaultStrategy(mockRegistryAddr);
    }

    /// @notice Deploy Manager + MockDefaultStrategy behind proxy against an existing
    ///         registry.
    /// @param registry Registry the Manager resolves Celo core contracts from.
    function deployTestDefaultStrategy(address registry) internal {
        deployTestManager(registry);

        vm.startPrank(deployer);

        _deployMockDefaultStrategyProxy();

        vm.stopPrank();
    }

    /// @notice Deploy Manager + SpecificGroupStrategy behind proxy on top of a fresh
    ///         MockRegistry.
    ///         Replicates deploy/test/specific_group_strategy.ts [tag: TestSpecificGroupStrategy].
    function deployTestSpecificGroupStrategy() internal {
        _initNamedAccounts();
        mockRegistryAddr = _deployMockCeloInfrastructure();
        deployTestSpecificGroupStrategy(mockRegistryAddr);
    }

    /// @notice Deploy Manager + SpecificGroupStrategy behind proxy against an existing
    ///         registry.
    /// @param registry Registry the Manager resolves Celo core contracts from.
    function deployTestSpecificGroupStrategy(address registry) internal {
        deployTestManager(registry);

        vm.startPrank(deployer);

        _deploySpecificGroupStrategyProxy();

        vm.stopPrank();
    }

    /// @notice Deploy MockStakedCelo + MockAccount (direct) + RebasedStakedCelo behind proxy.
    ///         Replicates deploy/test/rebased_staked_celo.ts + deps [tag: TestRebasedStakedCelo].
    function deployTestRebasedStakedCelo() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        // MockStakedCelo (direct, no proxy)
        mockStakedCelo = new MockStakedCelo();

        // MockAccount (direct, no proxy)
        mockAccount = new MockAccount();

        // RebasedStakedCelo behind proxy
        RebasedStakedCelo rscImpl = new RebasedStakedCelo();
        bytes memory rscData = abi.encodeWithSelector(
            RebasedStakedCelo.initialize.selector,
            address(mockStakedCelo),
            address(mockAccount),
            owner
        );
        ERC1967Proxy rscProxy = new ERC1967Proxy(address(rscImpl), rscData);
        rebasedStakedCelo = RebasedStakedCelo(address(rscProxy));

        vm.stopPrank();
    }
}
