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
 *      Usage: extend this contract and call deployFullTestManager() in setUp().
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
     * @notice Deploy the full Manager test fixture.
     * @dev Deployment sequence:
     *      1. MockRegistry (via getCode — cannot import directly)
     *      2. Mock Celo core contracts + registry registration
     *      3. Manager (proxy) — initialize(registry, owner)
     *      4. MockGroupHealth (proxy) — initialize(registry, owner)
     *      5. MockDefaultStrategy (proxy) — initialize(owner, managerProxy)
     *      6. SpecificGroupStrategy (proxy) — initialize(owner, managerProxy)
     *      7. Account (proxy) — initialize(registry, managerProxy, owner)
     *      8. StakedCelo (proxy) — initialize(managerProxy, owner)
     *      9. Vote (proxy) — initialize(registry, owner, managerProxy)
     *      10. Manager.setDependencies(...)
     *      11. Vote.setDependencies(...)
     *      12. SpecificGroupStrategy.setDependencies(...)
     *      13. MockDefaultStrategy.setDependencies(...)
     */
    function deployFullTestManager() internal {
        _initNamedAccounts();

        // ================================================================
        // Phase 1: MockRegistry + Celo core mocks
        // ================================================================
        // MockRegistry is deployed via getCode + assembly create because
        // importing it directly causes Initializable name collision.
        // The registry owner is address(this) (the test contract), so
        // setAddressFor calls must happen outside any prank context.
        // ================================================================

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

        // ================================================================
        // Phase 2: Protocol contracts behind ERC1967 proxies
        // ================================================================

        vm.startPrank(deployer);

        // --- Manager ---
        // initialize(address _registry, address _owner)
        Manager managerImpl = new Manager();
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImpl),
            abi.encodeWithSelector(Manager.initialize.selector, mockRegistryAddr, owner)
        );
        manager = Manager(address(managerProxy));

        // --- MockGroupHealth ---
        // initialize(address _registry, address _owner)
        MockGroupHealth ghImpl = new MockGroupHealth();
        ERC1967Proxy ghProxy = new ERC1967Proxy(
            address(ghImpl),
            abi.encodeWithSelector(GroupHealth.initialize.selector, mockRegistryAddr, owner)
        );
        mockGroupHealth = MockGroupHealth(address(ghProxy));

        // --- MockDefaultStrategy ---
        // initialize(address _owner, address _manager)
        // Note: DefaultStrategy uses AddressSortedLinkedList library — Forge auto-links at compile.
        MockDefaultStrategy dsImpl = new MockDefaultStrategy();
        ERC1967Proxy dsProxy = new ERC1967Proxy(
            address(dsImpl),
            abi.encodeWithSelector(
                DefaultStrategy.initialize.selector,
                owner,
                address(managerProxy)
            )
        );
        mockDefaultStrategy = MockDefaultStrategy(payable(address(dsProxy)));

        // --- SpecificGroupStrategy ---
        // initialize(address _owner, address _manager)
        SpecificGroupStrategy sgsImpl = new SpecificGroupStrategy();
        ERC1967Proxy sgsProxy = new ERC1967Proxy(
            address(sgsImpl),
            abi.encodeWithSelector(
                SpecificGroupStrategy.initialize.selector,
                owner,
                address(managerProxy)
            )
        );
        specificGroupStrategy = SpecificGroupStrategy(address(sgsProxy));

        // --- Account ---
        // initialize(address _registry, address _manager, address _owner)
        // Note: Account.initialize() calls getAccounts().createAccount(), requiring
        //       "Accounts" to be registered in MockRegistry (done in Phase 1).
        Account accountImpl = new Account();
        ERC1967Proxy accountProxy = new ERC1967Proxy(
            address(accountImpl),
            abi.encodeWithSelector(
                Account.initialize.selector,
                mockRegistryAddr,
                address(managerProxy),
                owner
            )
        );
        account = Account(payable(address(accountProxy)));

        // --- StakedCelo ---
        // initialize(address _manager, address _owner)
        StakedCelo stCeloImpl = new StakedCelo();
        ERC1967Proxy stCeloProxy = new ERC1967Proxy(
            address(stCeloImpl),
            abi.encodeWithSelector(
                StakedCelo.initialize.selector,
                address(managerProxy),
                owner
            )
        );
        stakedCelo = StakedCelo(address(stCeloProxy));

        // --- Vote ---
        // initialize(address _registry, address _owner, address _manager)
        Vote voteImpl = new Vote();
        ERC1967Proxy voteProxy = new ERC1967Proxy(
            address(voteImpl),
            abi.encodeWithSelector(
                Vote.initialize.selector,
                mockRegistryAddr,
                owner,
                address(managerProxy)
            )
        );
        vote = Vote(address(voteProxy));

        vm.stopPrank();

        // ================================================================
        // Phase 3: Wire dependencies (as owner)
        // ================================================================

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
