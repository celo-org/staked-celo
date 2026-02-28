// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../CeloTestHelper.sol";
import "../interfaces/IMultiSig.sol";
import {IVmExtended, MockCeloAccount} from "./FullTestManagerDeployHelper.sol";

// Additional protocol contracts not imported by CeloTestHelper
import "../../../contracts/StakedCelo.sol";
import "../../../contracts/Vote.sol";
import "../../../contracts/GroupHealth.sol";
import "../../../contracts/RebasedStakedCelo.sol";

// ERC1967Proxy (SAFE — no Initializable in import chain)
import "../../../contracts/common/ERC1967Proxy.sol";

/**
 * @title CoreDeployHelper
 * @notice Abstract helper that replicates the FULL production deployment sequence
 *         from deploy scripts 00-13. Deploys ALL 9 protocol contracts behind
 *         ERC1967Proxy, calls setDependencies on 4 contracts, and transfers
 *         ownership to MultiSig.
 * @dev Extend this contract in concrete test files and call deployCoreWithMockRegistry()
 *      inside setUp().
 *
 *      IMPORTANT: MultiSig.sol and MockRegistry.sol are NOT imported directly to avoid
 *      Initializable name collision between OZ contracts (non-upgradeable)
 *      and OZ contracts-upgradeable. They are deployed via vm.getCode().
 *
 *      Deployment order mirrors production scripts:
 *        00: MultiSig (constructor + proxy + initialize)
 *        01: Manager
 *        02: Account (requires "Accounts" in registry for createAccount())
 *        03: StakedCelo
 *        04: Vote
 *        05: GroupHealth (owner = MultiSig from start)
 *        06: SpecificGroupStrategy
 *        07: DefaultStrategy (AddressSortedLinkedList auto-linked by Forge)
 *        08: Manager.setDependencies
 *        09: Vote.setDependencies
 *        10: SpecificGroupStrategy.setDependencies
 *        11: DefaultStrategy.setDependencies
 *        12: Transfer ownership to MultiSig
 *        13: RebasedStakedCelo (owner = MultiSig from start)
 */
abstract contract CoreDeployHelper is CeloTestHelper {
    // =========================================================================
    //                       MOCK CELO CONTRACTS
    // =========================================================================

    MockElection public mockElection;
    MockLockedGold public mockLockedGold;
    MockValidators public mockValidators;
    MockGovernance public mockGovernance;
    MockCeloAccount public mockCeloAccount;
    address public mockGoldToken;
    address public mockRegistryAddr;

    // =========================================================================
    //                    PROTOCOL CONTRACTS (behind proxies)
    // =========================================================================

    Manager public manager;
    Account public account;
    StakedCelo public stakedCelo;
    Vote public vote;
    GroupHealth public groupHealth;
    SpecificGroupStrategy public specificGroupStrategy;
    DefaultStrategy public defaultStrategy;
    RebasedStakedCelo public rebasedStakedCelo;

    // =========================================================================
    //                    MULTISIG (via interface — no direct import)
    // =========================================================================

    IMultiSig public multiSig;
    address public multiSigProxy;

    // =========================================================================
    //                         DEPLOY FUNCTION
    // =========================================================================

    /// @notice Deploy all protocol contracts with a MockRegistry, replicating
    ///         the full production deploy sequence from scripts 00-13.
    function deployCoreWithMockRegistry() internal {
        _initNamedAccounts();

        // ================================================================
        // Phase 1: MockRegistry + Celo core mocks (no prank)
        // ================================================================
        // MockRegistry is deployed via getCode + assembly create because
        // importing it directly causes Initializable name collision.
        // The registry owner is address(this) (the test contract), so
        // setAddressFor calls must happen outside any prank context.
        // ================================================================
        _deployMockCeloInfrastructure();

        // ================================================================
        // Phase 2: Protocol contracts behind ERC1967 proxies (as deployer)
        // ================================================================
        vm.startPrank(deployer);

        // Script 00: MultiSig
        _deployMultiSigProxy();

        // Script 01: Manager — initialize(registry, deployer)
        _deployManagerProxy();

        // Script 02: Account — initialize(registry, managerProxy, deployer)
        _deployAccountProxy();

        // Script 03: StakedCelo — initialize(managerProxy, deployer)
        _deployStakedCeloProxy();

        // Script 04: Vote — initialize(registry, deployer, managerProxy)
        _deployVoteProxy();

        // Script 05: GroupHealth — initialize(registry, multiSigProxy)
        _deployGroupHealthProxy();

        // Script 06: SpecificGroupStrategy — initialize(deployer, managerProxy)
        _deploySpecificGroupStrategyProxy();

        // Script 07: DefaultStrategy — initialize(deployer, managerProxy)
        _deployDefaultStrategyProxy();

        // ================================================================
        // Phase 3: Wire dependencies (scripts 08-11)
        // ================================================================

        // Script 08: Manager.setDependencies
        manager.setDependencies(
            address(stakedCelo),
            address(account),
            address(vote),
            address(groupHealth),
            address(specificGroupStrategy),
            address(defaultStrategy)
        );

        // Script 09: Vote.setDependencies
        vote.setDependencies(address(stakedCelo), address(account));

        // Script 10: SpecificGroupStrategy.setDependencies
        specificGroupStrategy.setDependencies(
            address(account),
            address(groupHealth),
            address(defaultStrategy)
        );

        // Script 11: DefaultStrategy.setDependencies
        defaultStrategy.setDependencies(
            address(account),
            address(groupHealth),
            address(specificGroupStrategy)
        );

        // ================================================================
        // Phase 4: Transfer ownership to MultiSig (script 12)
        // ================================================================

        account.transferOwnership(multiSigProxy);
        stakedCelo.transferOwnership(multiSigProxy);
        manager.transferOwnership(multiSigProxy);
        vote.transferOwnership(multiSigProxy);
        specificGroupStrategy.transferOwnership(multiSigProxy);
        defaultStrategy.transferOwnership(multiSigProxy);

        // ================================================================
        // Phase 5: RebasedStakedCelo (script 13, owner = multiSig)
        // ================================================================

        _deployRebasedStakedCeloProxy();

        vm.stopPrank();
    }

    // =========================================================================
    //                    MOCK INFRASTRUCTURE DEPLOYMENT
    // =========================================================================

    /// @dev Deploy MockRegistry + mock Celo core contracts and register them.
    ///      Called without prank — test contract owns MockRegistry.
    function _deployMockCeloInfrastructure() private {
        // Deploy MockRegistry via getCode (UNSAFE to import — Initializable collision)
        bytes memory registryCode = IVmExtended(address(vm)).getCode(
            "MockRegistry.sol:MockRegistry"
        );
        address _mockRegistryAddr;
        assembly {
            _mockRegistryAddr := create(0, add(registryCode, 0x20), mload(registryCode))
        }
        require(_mockRegistryAddr != address(0), "MockRegistry deploy failed");
        mockRegistryAddr = _mockRegistryAddr;

        // Deploy mock Celo core contracts (SAFE to import — no Initializable)
        mockElection = new MockElection();
        mockLockedGold = new MockLockedGold();
        mockValidators = new MockValidators();
        mockGovernance = new MockGovernance();
        mockCeloAccount = new MockCeloAccount();
        mockGoldToken = makeAddr("goldToken");

        // Register all 6 mock Celo contracts in MockRegistry.
        // MockRegistry.owner() == address(this), so no prank is needed.
        IRegistry reg = IRegistry(mockRegistryAddr);
        reg.setAddressFor("Election", address(mockElection));
        reg.setAddressFor("LockedGold", address(mockLockedGold));
        reg.setAddressFor("Validators", address(mockValidators));
        reg.setAddressFor("Governance", address(mockGovernance));
        reg.setAddressFor("Accounts", address(mockCeloAccount));
        reg.setAddressFor("GoldToken", mockGoldToken);
    }

    // =========================================================================
    //                    PROTOCOL CONTRACT DEPLOYMENT
    // =========================================================================

    /// @dev Script 00: Deploy MultiSig implementation via getCode + proxy.
    ///      MultiSig.sol is UNSAFE to import (non-upgradeable Initializable).
    ///      constructor(minDelay = 3 * DAY), initialize(owners, required = 1, delay = DAY)
    function _deployMultiSigProxy() private {
        // Deploy implementation with constructor arg: minDelay = 3 days
        bytes memory msCode = IVmExtended(address(vm)).getCode("MultiSig.sol:MultiSig");
        bytes memory msCreation = abi.encodePacked(msCode, abi.encode(3 * DAY));
        address msImpl;
        assembly {
            msImpl := create(0, add(msCreation, 0x20), mload(msCreation))
        }
        require(msImpl != address(0), "MultiSig impl deploy failed");

        // Deploy proxy with initialize(owners, required, delay)
        address[] memory owners = new address[](1);
        owners[0] = multisigOwner0;

        bytes memory msInit = abi.encodeWithSignature(
            "initialize(address[],uint256,uint256)",
            owners,
            uint256(1), // required confirmations
            uint256(3 * DAY) // delay (must be >= minDelay of 3 * DAY)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(msImpl, msInit);
        multiSigProxy = address(proxy);
        multiSig = IMultiSig(multiSigProxy);
    }

    /// @dev Script 01: Manager — initialize(registry, owner)
    function _deployManagerProxy() private {
        Manager impl = new Manager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(Manager.initialize.selector, mockRegistryAddr, deployer)
        );
        manager = Manager(address(proxy));
    }

    /// @dev Script 02: Account — initialize(registry, managerProxy, owner)
    ///      REQUIRES: "Accounts" registered in MockRegistry (for createAccount())
    function _deployAccountProxy() private {
        Account impl = new Account();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                Account.initialize.selector,
                mockRegistryAddr,
                address(manager),
                deployer
            )
        );
        account = Account(payable(address(proxy)));
    }

    /// @dev Script 03: StakedCelo — initialize(managerProxy, owner)
    function _deployStakedCeloProxy() private {
        StakedCelo impl = new StakedCelo();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(StakedCelo.initialize.selector, address(manager), deployer)
        );
        stakedCelo = StakedCelo(address(proxy));
    }

    /// @dev Script 04: Vote — initialize(registry, owner, managerProxy)
    function _deployVoteProxy() private {
        Vote impl = new Vote();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                Vote.initialize.selector,
                mockRegistryAddr,
                deployer,
                address(manager)
            )
        );
        vote = Vote(address(proxy));
    }

    /// @dev Script 05: GroupHealth — initialize(registry, owner = multiSig)
    ///      GroupHealth is owned by MultiSig from the start (matching production).
    function _deployGroupHealthProxy() private {
        GroupHealth impl = new GroupHealth();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                GroupHealth.initialize.selector,
                mockRegistryAddr,
                multiSigProxy
            )
        );
        groupHealth = GroupHealth(address(proxy));
    }

    /// @dev Script 06: SpecificGroupStrategy — initialize(owner, managerProxy)
    function _deploySpecificGroupStrategyProxy() private {
        SpecificGroupStrategy impl = new SpecificGroupStrategy();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                SpecificGroupStrategy.initialize.selector,
                deployer,
                address(manager)
            )
        );
        specificGroupStrategy = SpecificGroupStrategy(address(proxy));
    }

    /// @dev Script 07: DefaultStrategy — initialize(owner, managerProxy)
    ///      NOTE: AddressSortedLinkedList library is linked automatically by Forge.
    function _deployDefaultStrategyProxy() private {
        DefaultStrategy impl = new DefaultStrategy();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                DefaultStrategy.initialize.selector,
                deployer,
                address(manager)
            )
        );
        defaultStrategy = DefaultStrategy(address(proxy));
    }

    /// @dev Script 13: RebasedStakedCelo — initialize(stakedCeloProxy, accountProxy, owner = multiSig)
    function _deployRebasedStakedCeloProxy() private {
        RebasedStakedCelo impl = new RebasedStakedCelo();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                RebasedStakedCelo.initialize.selector,
                address(stakedCelo),
                address(account),
                multiSigProxy
            )
        );
        rebasedStakedCelo = RebasedStakedCelo(address(proxy));
    }
}
