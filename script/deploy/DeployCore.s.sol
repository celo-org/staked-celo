// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import {DeployBase, DeployLog, IOwnable} from "./DeployBase.s.sol";

// Named imports keep `Initializable` out of this file's scope: MultiSig uses the
// non-upgradeable OpenZeppelin variant while every other contract uses the upgradeable
// one, and a plain import of both would be an ambiguous declaration.
import {MultiSig} from "../../contracts/common/MultiSig.sol";
import {Manager} from "../../contracts/Manager.sol";
import {Account} from "../../contracts/Account.sol";
import {StakedCelo} from "../../contracts/StakedCelo.sol";
import {Vote} from "../../contracts/Vote.sol";
import {GroupHealth} from "../../contracts/GroupHealth.sol";
import {SpecificGroupStrategy} from "../../contracts/SpecificGroupStrategy.sol";
import {DefaultStrategy} from "../../contracts/DefaultStrategy.sol";
import {RebasedStakedCelo} from "../../contracts/RebasedStakedCelo.sol";

/**
 * @title DeployCore
 * @notice The deploy/00 .. deploy/13 sequence, replacing `yarn deploy`
 *         (`hardhat stakedCelo:deploy --tags core`).
 * @dev Every contract sits behind an ERC1967 proxy and the implementations are deployed
 *      with a plain `new`, so the code on chain is exactly the artifact compiled with the
 *      production profile (solc 0.8.11, evm istanbul, no optimizer, no via-ir).
 *
 *      The script is idempotent the way hardhat-deploy was: a contract that already has a
 *      record in `deployments/<network>/` is reused, and the wiring steps are skipped once
 *      ownership has moved to the MultiSig (they then have to be proposed through it).
 *
 *      Required environment variables:
 *        TIME_LOCK_MIN_DELAY             MultiSig constructor argument, in seconds.
 *        TIME_LOCK_DELAY                 MultiSig proposal delay, in seconds.
 *        MULTISIG_REQUIRED_CONFIRMATIONS Confirmations needed to execute a proposal.
 *        MULTISIG_OWNERS                 Comma separated list of MultiSig owners.
 *      Optional:
 *        NETWORK                         Deployments directory name; defaults to the
 *                                        chain id mapping (celo / alfajores / local).
 */
contract DeployCore is DeployBase {
    /// @notice Parameters that used to come from `.env` and hardhat-deploy named accounts.
    struct CoreConfig {
        uint256 timeLockMinDelay;
        uint256 timeLockDelay;
        uint256 requiredConfirmations;
        address[] multiSigOwners;
    }

    CoreConfig internal config;

    // Proxy addresses of the deployed protocol.
    address public multiSig;
    address public manager;
    address public account;
    address public stakedCelo;
    address public vote;
    address public groupHealth;
    address public specificGroupStrategy;
    address public defaultStrategy;
    address public rebasedStakedCelo;

    // =========================================================================
    //                            ENTRY POINTS
    // =========================================================================

    /// @notice Deploy the protocol against the connected node, broadcasting every
    ///         transaction from the configured signer.
    function run() external {
        _initNetwork();
        deployer = msg.sender;
        _loadConfigFromEnv();
        vm.startBroadcast();
        _deployAll();
        vm.stopBroadcast();
        _logSummary();
    }

    /// @notice Run the exact same sequence in-process, impersonating `broadcaster` and
    ///         without touching the deployment records. Used by the tests.
    /// @param broadcaster The address the deployment is attributed to.
    /// @param coreConfig The MultiSig parameters to deploy with.
    function runInProcess(address broadcaster, CoreConfig memory coreConfig) external {
        network = "in-process";
        useDeploymentRecords = false;
        deployer = broadcaster;
        config = coreConfig;
        vm.startPrank(broadcaster, broadcaster);
        _deployAll();
        vm.stopPrank();
    }

    // =========================================================================
    //                              SEQUENCE
    // =========================================================================

    /// @dev The deploy/00 .. deploy/13 sequence, in order.
    function _deployAll() internal {
        _deployMultiSig();
        _deployManager();
        _deployAccount();
        _deployStakedCelo();
        _deployVote();
        _deployGroupHealth();
        _deploySpecificGroupStrategy();
        _deployDefaultStrategy();
        _setManagerDependencies();
        _setVoteDependencies();
        _setSpecificGroupStrategyDependencies();
        _setDefaultStrategyDependencies();
        _transferOwnershipToMultiSig();
        _deployRebasedStakedCelo();
    }

    /// @dev Read the MultiSig parameters from the environment.
    function _loadConfigFromEnv() internal {
        config.timeLockMinDelay = vm.envUint("TIME_LOCK_MIN_DELAY");
        config.timeLockDelay = vm.envUint("TIME_LOCK_DELAY");
        config.requiredConfirmations = vm.envUint("MULTISIG_REQUIRED_CONFIRMATIONS");
        config.multiSigOwners = vm.envAddress("MULTISIG_OWNERS", ",");
    }

    // =========================================================================
    //                      CONTRACT DEPLOYMENT STEPS
    // =========================================================================

    /// @dev deploy/00: MultiSig. `minDelay` is a constructor argument, the owner set and
    ///      the proposal delay are initializer arguments.
    function _deployMultiSig() private {
        multiSig = readDeploymentAddress("MultiSig");
        if (multiSig != address(0)) {
            DeployLog.a("MultiSig: reused", multiSig);
            return;
        }
        address implementation = address(new MultiSig(config.timeLockMinDelay));
        multiSig = _deployProxy(
            implementation,
            abi.encodeWithSelector(
                MultiSig.initialize.selector,
                config.multiSigOwners,
                config.requiredConfirmations,
                config.timeLockDelay
            )
        );
        _recordProxyDeployment("MultiSig", multiSig, implementation);
        DeployLog.a("MultiSig: deployed", multiSig);
    }

    /// @dev deploy/01: Manager, initially owned by the deployer so it can be wired up.
    function _deployManager() private {
        manager = readDeploymentAddress("Manager");
        if (manager != address(0)) {
            DeployLog.a("Manager: reused", manager);
            return;
        }
        address implementation = address(new Manager());
        manager = _deployProxy(
            implementation,
            abi.encodeWithSelector(Manager.initialize.selector, CANONICAL_REGISTRY, deployer)
        );
        _recordProxyDeployment("Manager", manager, implementation);
        DeployLog.a("Manager: deployed", manager);
    }

    /// @dev deploy/02: Account. Its initializer registers the proxy as a Celo account.
    function _deployAccount() private {
        account = readDeploymentAddress("Account");
        if (account != address(0)) {
            DeployLog.a("Account: reused", account);
            return;
        }
        address implementation = address(new Account());
        account = _deployProxy(
            implementation,
            abi.encodeWithSelector(
                Account.initialize.selector,
                CANONICAL_REGISTRY,
                manager,
                deployer
            )
        );
        _recordProxyDeployment("Account", account, implementation);
        DeployLog.a("Account: deployed", account);
    }

    /// @dev deploy/03: StakedCelo.
    function _deployStakedCelo() private {
        stakedCelo = readDeploymentAddress("StakedCelo");
        if (stakedCelo != address(0)) {
            DeployLog.a("StakedCelo: reused", stakedCelo);
            return;
        }
        address implementation = address(new StakedCelo());
        stakedCelo = _deployProxy(
            implementation,
            abi.encodeWithSelector(StakedCelo.initialize.selector, manager, deployer)
        );
        _recordProxyDeployment("StakedCelo", stakedCelo, implementation);
        DeployLog.a("StakedCelo: deployed", stakedCelo);
    }

    /// @dev deploy/04: Vote.
    function _deployVote() private {
        vote = readDeploymentAddress("Vote");
        if (vote != address(0)) {
            DeployLog.a("Vote: reused", vote);
            return;
        }
        address implementation = address(new Vote());
        vote = _deployProxy(
            implementation,
            abi.encodeWithSelector(
                Vote.initialize.selector,
                CANONICAL_REGISTRY,
                deployer,
                manager
            )
        );
        _recordProxyDeployment("Vote", vote, implementation);
        DeployLog.a("Vote: deployed", vote);
    }

    /// @dev deploy/05: GroupHealth, owned by the MultiSig from the start because it needs
    ///      no wiring afterwards.
    function _deployGroupHealth() private {
        groupHealth = readDeploymentAddress("GroupHealth");
        if (groupHealth != address(0)) {
            DeployLog.a("GroupHealth: reused", groupHealth);
            return;
        }
        address implementation = address(new GroupHealth());
        groupHealth = _deployProxy(
            implementation,
            abi.encodeWithSelector(
                GroupHealth.initialize.selector,
                CANONICAL_REGISTRY,
                multiSig
            )
        );
        _recordProxyDeployment("GroupHealth", groupHealth, implementation);
        DeployLog.a("GroupHealth: deployed", groupHealth);
    }

    /// @dev deploy/06: SpecificGroupStrategy.
    function _deploySpecificGroupStrategy() private {
        specificGroupStrategy = readDeploymentAddress("SpecificGroupStrategy");
        if (specificGroupStrategy != address(0)) {
            DeployLog.a("SpecificGroupStrategy: reused", specificGroupStrategy);
            return;
        }
        address implementation = address(new SpecificGroupStrategy());
        specificGroupStrategy = _deployProxy(
            implementation,
            abi.encodeWithSelector(SpecificGroupStrategy.initialize.selector, deployer, manager)
        );
        _recordProxyDeployment("SpecificGroupStrategy", specificGroupStrategy, implementation);
        DeployLog.a("SpecificGroupStrategy: deployed", specificGroupStrategy);
    }

    /// @dev deploy/07: DefaultStrategy. Forge deploys and links AddressSortedLinkedList.
    function _deployDefaultStrategy() private {
        defaultStrategy = readDeploymentAddress("DefaultStrategy");
        if (defaultStrategy != address(0)) {
            DeployLog.a("DefaultStrategy: reused", defaultStrategy);
            return;
        }
        address implementation = address(new DefaultStrategy());
        defaultStrategy = _deployProxy(
            implementation,
            abi.encodeWithSelector(DefaultStrategy.initialize.selector, deployer, manager)
        );
        _recordProxyDeployment("DefaultStrategy", defaultStrategy, implementation);
        DeployLog.a("DefaultStrategy: deployed", defaultStrategy);
    }

    /// @dev deploy/13: RebasedStakedCelo, owned by the MultiSig from the start.
    function _deployRebasedStakedCelo() private {
        rebasedStakedCelo = readDeploymentAddress("RebasedStakedCelo");
        if (rebasedStakedCelo != address(0)) {
            DeployLog.a("RebasedStakedCelo: reused", rebasedStakedCelo);
            return;
        }
        address implementation = address(new RebasedStakedCelo());
        rebasedStakedCelo = _deployProxy(
            implementation,
            abi.encodeWithSelector(
                RebasedStakedCelo.initialize.selector,
                stakedCelo,
                account,
                multiSig
            )
        );
        _recordProxyDeployment("RebasedStakedCelo", rebasedStakedCelo, implementation);
        DeployLog.a("RebasedStakedCelo: deployed", rebasedStakedCelo);
    }

    // =========================================================================
    //                          WIRING STEPS
    // =========================================================================

    /// @dev deploy/08: Manager.setDependencies.
    function _setManagerDependencies() private {
        if (_ownedByMultiSig(manager, "Manager")) {
            return;
        }
        Manager(manager).setDependencies(
            stakedCelo,
            account,
            vote,
            groupHealth,
            specificGroupStrategy,
            defaultStrategy
        );
        DeployLog.s("Manager: dependencies set");
    }

    /// @dev deploy/09: Vote.setDependencies.
    function _setVoteDependencies() private {
        if (_ownedByMultiSig(vote, "Vote")) {
            return;
        }
        Vote(vote).setDependencies(stakedCelo, account);
        DeployLog.s("Vote: dependencies set");
    }

    /// @dev deploy/10: SpecificGroupStrategy.setDependencies.
    function _setSpecificGroupStrategyDependencies() private {
        if (_ownedByMultiSig(specificGroupStrategy, "SpecificGroupStrategy")) {
            return;
        }
        SpecificGroupStrategy(specificGroupStrategy).setDependencies(
            account,
            groupHealth,
            defaultStrategy
        );
        DeployLog.s("SpecificGroupStrategy: dependencies set");
    }

    /// @dev deploy/11: DefaultStrategy.setDependencies.
    function _setDefaultStrategyDependencies() private {
        if (_ownedByMultiSig(defaultStrategy, "DefaultStrategy")) {
            return;
        }
        DefaultStrategy(defaultStrategy).setDependencies(
            account,
            groupHealth,
            specificGroupStrategy
        );
        DeployLog.s("DefaultStrategy: dependencies set");
    }

    /// @dev deploy/12: hand the six deployer owned contracts over to the MultiSig.
    function _transferOwnershipToMultiSig() private {
        _transferOwnership(account, "Account");
        _transferOwnership(stakedCelo, "StakedCelo");
        _transferOwnership(manager, "Manager");
        _transferOwnership(vote, "Vote");
        _transferOwnership(specificGroupStrategy, "SpecificGroupStrategy");
        _transferOwnership(defaultStrategy, "DefaultStrategy");
    }

    /// @dev Transfer ownership unless the MultiSig already owns the contract.
    function _transferOwnership(address target, string memory name) private {
        if (IOwnable(target).owner() == multiSig) {
            DeployLog.s(string(abi.encodePacked(name, ": already owned by MultiSig")));
            return;
        }
        IOwnable(target).transferOwnership(multiSig);
        DeployLog.s(string(abi.encodePacked(name, ": ownership transferred to MultiSig")));
    }

    /// @dev True when the contract already belongs to the MultiSig, in which case the
    ///      wiring call has to be proposed through the MultiSig instead.
    function _ownedByMultiSig(address target, string memory name) private view returns (bool) {
        if (IOwnable(target).owner() != multiSig) {
            return false;
        }
        DeployLog.s(
            string(
                abi.encodePacked(
                    name,
                    ": owned by MultiSig, propose setDependencies through the MultiSig"
                )
            )
        );
        return true;
    }

    // =========================================================================
    //                             SUMMARY
    // =========================================================================

    /// @dev Print every proxy address at the end of a run.
    function _logSummary() internal view {
        DeployLog.a("MultiSig", multiSig);
        DeployLog.a("Manager", manager);
        DeployLog.a("Account", account);
        DeployLog.a("StakedCelo", stakedCelo);
        DeployLog.a("Vote", vote);
        DeployLog.a("GroupHealth", groupHealth);
        DeployLog.a("SpecificGroupStrategy", specificGroupStrategy);
        DeployLog.a("DefaultStrategy", defaultStrategy);
        DeployLog.a("RebasedStakedCelo", rebasedStakedCelo);
    }
}
