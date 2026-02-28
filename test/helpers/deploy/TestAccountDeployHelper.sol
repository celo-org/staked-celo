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

    /// @dev Deploy mock Celo core contracts and register them in MockRegistry.
    ///      Must be called after _deployMockRegistry() and while still pranked
    ///      as the registry owner (deployer).
    function _registerCoreMocks(address registryAddr) internal {
        mockElection = new MockElection();
        mockLockedGold = new MockLockedGold();
        mockValidators = new MockValidators();
        mockGovernance = new MockGovernance();
        mockAccountsCelo = new MockAccountsCelo();

        IRegistry reg = IRegistry(registryAddr);
        reg.setAddressFor("Election", address(mockElection));
        reg.setAddressFor("LockedGold", address(mockLockedGold));
        reg.setAddressFor("Validators", address(mockValidators));
        reg.setAddressFor("Governance", address(mockGovernance));
        reg.setAddressFor("Accounts", address(mockAccountsCelo));
    }

    /// @dev Deploy Manager behind ERC1967Proxy, initialized with registry and owner.
    function _deployManagerBehindProxy(address registryAddr) internal returns (Manager) {
        Manager impl = new Manager();
        bytes memory data = abi.encodeWithSelector(Manager.initialize.selector, registryAddr, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        return Manager(address(proxy));
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

    /// @notice Deploy Manager behind proxy.
    ///         Replicates deploy/test/manager.ts + mock_vote.ts [tag: TestManager].
    function deployTestManager() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        mockRegistryAddr = _deployMockRegistry();
        _registerCoreMocks(mockRegistryAddr);

        // MockVote (from mock_vote.ts, tag TestManager)
        mockVote = new MockVote();

        // Manager behind proxy
        manager = _deployManagerBehindProxy(mockRegistryAddr);

        vm.stopPrank();
    }

    /// @notice Deploy Manager + Account behind proxies.
    ///         Replicates deploy/test/account.ts + deps [tag: TestAccount].
    ///         Includes: MockGovernance (tag TestAccount), MockVote (tag TestManager).
    function deployTestAccount() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        mockRegistryAddr = _deployMockRegistry();
        _registerCoreMocks(mockRegistryAddr);

        // MockVote (from mock_vote.ts, tag TestManager)
        mockVote = new MockVote();

        // Manager behind proxy
        manager = _deployManagerBehindProxy(mockRegistryAddr);

        // Account behind proxy — needs "Accounts" registered for createAccount()
        Account accountImpl = new Account();
        bytes memory accountData = abi.encodeWithSelector(
            Account.initialize.selector,
            mockRegistryAddr,
            address(manager),
            owner
        );
        ERC1967Proxy accountProxy = new ERC1967Proxy(address(accountImpl), accountData);
        account = Account(payable(address(accountProxy)));

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

    /// @notice Deploy full Vote test environment:
    ///         Manager + Account + StakedCelo + Vote + MockGroupHealth +
    ///         MockDefaultStrategy + SpecificGroupStrategy behind proxies.
    ///         Replicates all deploy/test/*.ts with [tag: TestVote].
    function deployTestVote() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        // Deploy MockRegistry and register core mocks
        mockRegistryAddr = _deployMockRegistry();
        _registerCoreMocks(mockRegistryAddr);

        // MockVote (from mock_vote.ts, tag TestManager)
        mockVote = new MockVote();

        // Manager behind proxy
        manager = _deployManagerBehindProxy(mockRegistryAddr);

        // Account behind proxy
        {
            Account accountImpl = new Account();
            bytes memory accountData = abi.encodeWithSelector(
                Account.initialize.selector,
                mockRegistryAddr,
                address(manager),
                owner
            );
            ERC1967Proxy accountProxy = new ERC1967Proxy(
                address(accountImpl),
                accountData
            );
            account = Account(payable(address(accountProxy)));
        }

        // StakedCelo behind proxy (uses real Manager address per staked_celo.ts)
        {
            StakedCelo scImpl = new StakedCelo();
            bytes memory scData = abi.encodeWithSelector(
                StakedCelo.initialize.selector,
                address(manager),
                owner
            );
            ERC1967Proxy scProxy = new ERC1967Proxy(address(scImpl), scData);
            stakedCelo = StakedCelo(address(scProxy));
        }

        // Vote behind proxy
        {
            Vote voteImpl = new Vote();
            bytes memory voteData = abi.encodeWithSelector(
                Vote.initialize.selector,
                mockRegistryAddr,
                owner,
                address(manager)
            );
            ERC1967Proxy voteProxy = new ERC1967Proxy(address(voteImpl), voteData);
            vote = Vote(address(voteProxy));
        }

        // MockGroupHealth behind proxy
        {
            MockGroupHealth ghImpl = new MockGroupHealth();
            bytes memory ghData = abi.encodeWithSelector(
                GroupHealth.initialize.selector,
                mockRegistryAddr,
                owner
            );
            ERC1967Proxy ghProxy = new ERC1967Proxy(address(ghImpl), ghData);
            mockGroupHealth = MockGroupHealth(address(ghProxy));
        }

        // MockDefaultStrategy behind proxy (library auto-linked by Forge)
        {
            MockDefaultStrategy dsImpl = new MockDefaultStrategy();
            bytes memory dsData = abi.encodeWithSelector(
                DefaultStrategy.initialize.selector,
                owner,
                address(manager)
            );
            ERC1967Proxy dsProxy = new ERC1967Proxy(address(dsImpl), dsData);
            mockDefaultStrategy = MockDefaultStrategy(payable(address(dsProxy)));
        }

        // SpecificGroupStrategy behind proxy
        {
            SpecificGroupStrategy sgsImpl = new SpecificGroupStrategy();
            bytes memory sgsData = abi.encodeWithSelector(
                SpecificGroupStrategy.initialize.selector,
                owner,
                address(manager)
            );
            ERC1967Proxy sgsProxy = new ERC1967Proxy(address(sgsImpl), sgsData);
            specificGroupStrategy = SpecificGroupStrategy(address(sgsProxy));
        }

        vm.stopPrank();
    }

    /// @notice Deploy MockGroupHealth behind proxy.
    ///         Replicates deploy/test/group_health.ts [tag: TestGroupHealth].
    function deployTestGroupHealth() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        mockRegistryAddr = _deployMockRegistry();
        _registerCoreMocks(mockRegistryAddr);

        MockGroupHealth ghImpl = new MockGroupHealth();
        bytes memory ghData = abi.encodeWithSelector(
            GroupHealth.initialize.selector,
            mockRegistryAddr,
            owner
        );
        ERC1967Proxy ghProxy = new ERC1967Proxy(address(ghImpl), ghData);
        mockGroupHealth = MockGroupHealth(address(ghProxy));

        vm.stopPrank();
    }

    /// @notice Deploy Manager + MockDefaultStrategy behind proxy.
    ///         Replicates deploy/test/default_strategy.ts [tag: TestDefaultStrategy].
    ///         AddressSortedLinkedList library is auto-linked by Forge.
    function deployTestDefaultStrategy() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        mockRegistryAddr = _deployMockRegistry();
        _registerCoreMocks(mockRegistryAddr);

        // MockVote (from mock_vote.ts, tag TestManager)
        mockVote = new MockVote();

        // Manager behind proxy
        manager = _deployManagerBehindProxy(mockRegistryAddr);

        // MockDefaultStrategy behind proxy
        MockDefaultStrategy dsImpl = new MockDefaultStrategy();
        bytes memory dsData = abi.encodeWithSelector(
            DefaultStrategy.initialize.selector,
            owner,
            address(manager)
        );
        ERC1967Proxy dsProxy = new ERC1967Proxy(address(dsImpl), dsData);
        mockDefaultStrategy = MockDefaultStrategy(payable(address(dsProxy)));

        vm.stopPrank();
    }

    /// @notice Deploy Manager + SpecificGroupStrategy behind proxy.
    ///         Replicates deploy/test/specific_group_strategy.ts [tag: TestSpecificGroupStrategy].
    function deployTestSpecificGroupStrategy() internal {
        _initNamedAccounts();
        vm.startPrank(deployer);

        mockRegistryAddr = _deployMockRegistry();
        _registerCoreMocks(mockRegistryAddr);

        // MockVote (from mock_vote.ts, tag TestManager)
        mockVote = new MockVote();

        // Manager behind proxy
        manager = _deployManagerBehindProxy(mockRegistryAddr);

        // SpecificGroupStrategy behind proxy
        SpecificGroupStrategy sgsImpl = new SpecificGroupStrategy();
        bytes memory sgsData = abi.encodeWithSelector(
            SpecificGroupStrategy.initialize.selector,
            owner,
            address(manager)
        );
        ERC1967Proxy sgsProxy = new ERC1967Proxy(address(sgsImpl), sgsData);
        specificGroupStrategy = SpecificGroupStrategy(address(sgsProxy));

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
