// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../CeloTestHelper.sol";
import "../../../contracts/common/ERC1967Proxy.sol";
import "../../../contracts/StakedCelo.sol";
import "../../../contracts/Vote.sol";

// Manager, Account, MockElection, MockLockedGold, MockValidators, MockGovernance,
// MockAccount, MockGroupHealth, MockDefaultStrategy, SpecificGroupStrategy, DefaultStrategy
// are all transitively imported via CeloTestHelper.sol

// ---- Interfaces for unsafe imports (Initializable collision) ----

// Interface for MockRegistry. Cannot import contracts/mock/MockRegistry.sol
// directly because it pulls in the non-upgradeable Initializable.sol
// which collides with the upgradeable Initializable used by
// Manager, Account, GroupHealth, DefaultStrategy, etc.
interface IMockRegistry {
    function setAddressFor(string calldata identifier, address addr) external;
    function getAddressForOrDie(bytes32 identifierHash) external view returns (address);
    function getAddressFor(bytes32 identifierHash) external view returns (address);
}

/// @dev Extended VM interface — CeloTestVm omits getCode; cast vm to this to use it.
interface IVmExtended {
    function getCode(string calldata) external returns (bytes memory);
}

// ---- Minimal Celo core Accounts mock ----

/// @dev Mock for the Celo core "Accounts" contract registered in Registry under "Accounts".
///      Account.initialize() calls getAccounts().createAccount() which requires an IAccounts
///      implementation at the registry address. This mock satisfies that requirement.
contract MockCeloAccount {
    function createAccount() external pure returns (bool) {
        return true;
    }

    function getValidatorSigner(address account) external pure returns (address) {
        return account;
    }

    function isAccount(address) external pure returns (bool) {
        return true;
    }
}

/**
 * @title FullTestManagerDeployHelper
 * @notice Abstract helper that deploys the full Manager test fixture for Foundry.
 * @dev Replicates the FullTestManager hardhat-deploy fixture:
 *      - Manager, MockGroupHealth, MockDefaultStrategy, SpecificGroupStrategy (from FullTestManager tag)
 *      - Account, StakedCelo, Vote (from TestVote tag / test before() blocks)
 *      - All setDependencies wiring
 *
 *      Also deploys MockRegistry + mock Celo core contracts (Election, LockedGold,
 *      Validators, Governance, Accounts) and registers them in the registry.
 *
 *      Usage: extend this contract and call deployFullTestManager() in setUp(),
 *      or deployFullTestManager(registry) to wire the protocol against an
 *      already existing registry (for example the Celo core registry of a devchain).
 */
abstract contract FullTestManagerDeployHelper is CeloTestHelper {
    // =========================================================================
    //                       MOCK CELO CONTRACTS
    // =========================================================================

    MockElection public mockElection;
    MockLockedGold public mockLockedGold;
    MockValidators public mockValidators;
    MockGovernance public mockGovernance;
    MockCeloAccount public mockCeloAccount;

    // =========================================================================
    //                    PROTOCOL CONTRACTS (behind proxies)
    // =========================================================================

    Manager public manager;
    Account public account;
    StakedCelo public stakedCelo;
    Vote public vote;
    MockGroupHealth public mockGroupHealth;
    MockDefaultStrategy public mockDefaultStrategy;
    SpecificGroupStrategy public specificGroupStrategy;

    // =========================================================================
    //                              REGISTRY
    // =========================================================================

    address public mockRegistryAddr;

    // =========================================================================
    //                         DEPLOY FUNCTION
    // =========================================================================

    /**
     * @notice Deploy the full Manager test fixture against mock Celo core contracts.
     * @dev Deployment sequence:
     *      1. MockRegistry (via getCode — cannot import directly)
     *      2. Mock Celo core contracts + registry registration
     *      3-13. Everything deployFullTestManager(registry) does.
     */
    function deployFullTestManager() internal {
        _initNamedAccounts();
        _deployMockCeloInfrastructure();
        deployFullTestManager(mockRegistryAddr);
    }

    /**
     * @notice Deploy the full Manager test fixture against an existing registry.
     * @param registry Registry the protocol contracts resolve Celo core contracts from.
     *        Nothing is registered in it, so it may be a registry owned by someone else
     *        (for example the Celo core registry of a devchain).
     * @dev Deployment sequence:
     *      1. Manager (proxy) — initialize(registry, owner)
     *      2. MockGroupHealth (proxy) — initialize(registry, owner)
     *      3. MockDefaultStrategy (proxy) — initialize(owner, managerProxy)
     *      4. SpecificGroupStrategy (proxy) — initialize(owner, managerProxy)
     *      5. Account (proxy) — initialize(registry, managerProxy, owner)
     *      6. StakedCelo (proxy) — initialize(managerProxy, owner)
     *      7. Vote (proxy) — initialize(registry, owner, managerProxy)
     *      8. Manager.setDependencies(...)
     *      9. Vote.setDependencies(...)
     *      10. SpecificGroupStrategy.setDependencies(...)
     *      11. MockDefaultStrategy.setDependencies(...)
     */
    function deployFullTestManager(address registry) internal {
        // Idempotent — harmless when called again from the no-argument fixture.
        _initNamedAccounts();

        // ================================================================
        // Phase 2: Protocol contracts behind ERC1967 proxies
        // ================================================================

        vm.startPrank(deployer);

        _deployManagerProxy(registry);
        _deployMockGroupHealthProxy(registry);
        _deployMockDefaultStrategyProxy();
        _deploySpecificGroupStrategyProxy();
        _deployAccountProxy(registry);
        _deployStakedCeloProxy();
        _deployVoteProxy(registry);

        vm.stopPrank();

        // ================================================================
        // Phase 3: Wire dependencies (as owner)
        // ================================================================

        _setDependencies();
    }

    // =========================================================================
    //                    MOCK INFRASTRUCTURE DEPLOYMENT
    // =========================================================================

    /**
     * @dev Deploy MockRegistry + mock Celo core contracts and register them.
     *      MockRegistry is deployed via getCode + assembly create because
     *      importing it directly causes Initializable name collision.
     *      Called without prank, so the registry owner is address(this) (the
     *      test contract) and setAddressFor needs no prank either.
     */
    function _deployMockCeloInfrastructure() private {
        bytes memory registryCode = IVmExtended(address(vm)).getCode(
            "MockRegistry.sol:MockRegistry"
        );
        address _mockRegistryAddr;
        assembly {
            _mockRegistryAddr := create(0, add(registryCode, 0x20), mload(registryCode))
        }
        mockRegistryAddr = _mockRegistryAddr;

        // Deploy mock Celo core contracts (plain deploys, no proxy needed)
        mockElection = new MockElection();
        mockLockedGold = new MockLockedGold();
        mockValidators = new MockValidators();
        mockGovernance = new MockGovernance();
        mockCeloAccount = new MockCeloAccount();

        // Register mock Celo contracts in MockRegistry.
        // MockRegistry.owner() == address(this), so no prank is needed.
        IMockRegistry(mockRegistryAddr).setAddressFor("Election", address(mockElection));
        IMockRegistry(mockRegistryAddr).setAddressFor("LockedGold", address(mockLockedGold));
        IMockRegistry(mockRegistryAddr).setAddressFor("Validators", address(mockValidators));
        IMockRegistry(mockRegistryAddr).setAddressFor("Governance", address(mockGovernance));
        IMockRegistry(mockRegistryAddr).setAddressFor("Accounts", address(mockCeloAccount));
    }

    // =========================================================================
    //                    PROTOCOL CONTRACT DEPLOYMENT
    // =========================================================================
    //
    // One function per proxy so that each stack frame stays small enough to
    // compile without via_ir.

    /// @dev Manager — initialize(registry, owner)
    function _deployManagerProxy(address registry) private {
        Manager impl = new Manager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(Manager.initialize.selector, registry, owner)
        );
        manager = Manager(address(proxy));
    }

    /// @dev MockGroupHealth — initialize(registry, owner)
    function _deployMockGroupHealthProxy(address registry) private {
        MockGroupHealth impl = new MockGroupHealth();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(GroupHealth.initialize.selector, registry, owner)
        );
        mockGroupHealth = MockGroupHealth(address(proxy));
    }

    /// @dev MockDefaultStrategy — initialize(owner, managerProxy)
    ///      NOTE: AddressSortedLinkedList library is linked automatically by Forge.
    function _deployMockDefaultStrategyProxy() private {
        MockDefaultStrategy impl = new MockDefaultStrategy();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(DefaultStrategy.initialize.selector, owner, address(manager))
        );
        mockDefaultStrategy = MockDefaultStrategy(payable(address(proxy)));
    }

    /// @dev SpecificGroupStrategy — initialize(owner, managerProxy)
    function _deploySpecificGroupStrategyProxy() private {
        SpecificGroupStrategy impl = new SpecificGroupStrategy();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                SpecificGroupStrategy.initialize.selector,
                owner,
                address(manager)
            )
        );
        specificGroupStrategy = SpecificGroupStrategy(address(proxy));
    }

    /// @dev Account — initialize(registry, managerProxy, owner)
    ///      REQUIRES: "Accounts" resolvable in the registry, because
    ///      Account.initialize() calls getAccounts().createAccount().
    function _deployAccountProxy(address registry) private {
        Account impl = new Account();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                Account.initialize.selector,
                registry,
                address(manager),
                owner
            )
        );
        account = Account(payable(address(proxy)));
    }

    /// @dev StakedCelo — initialize(managerProxy, owner)
    function _deployStakedCeloProxy() private {
        StakedCelo impl = new StakedCelo();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(StakedCelo.initialize.selector, address(manager), owner)
        );
        stakedCelo = StakedCelo(address(proxy));
    }

    /// @dev Vote — initialize(registry, owner, managerProxy)
    function _deployVoteProxy(address registry) private {
        Vote impl = new Vote();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                Vote.initialize.selector,
                registry,
                owner,
                address(manager)
            )
        );
        vote = Vote(address(proxy));
    }

    /// @dev Wire Manager, Vote, SpecificGroupStrategy and DefaultStrategy together.
    function _setDependencies() private {
        vm.startPrank(owner);

        // Manager.setDependencies(stakedCelo, account, vote, groupHealth, sgs, ds)
        manager.setDependencies(
            address(stakedCelo),
            address(account),
            address(vote),
            address(mockGroupHealth),
            address(specificGroupStrategy),
            address(mockDefaultStrategy)
        );

        // Vote.setDependencies(stakedCelo, account)
        vote.setDependencies(address(stakedCelo), address(account));

        // SpecificGroupStrategy.setDependencies(account, groupHealth, defaultStrategy)
        specificGroupStrategy.setDependencies(
            address(account),
            address(mockGroupHealth),
            address(mockDefaultStrategy)
        );

        // DefaultStrategy.setDependencies(account, groupHealth, specificGroupStrategy)
        mockDefaultStrategy.setDependencies(
            address(account),
            address(mockGroupHealth),
            address(specificGroupStrategy)
        );

        vm.stopPrank();
    }
}
