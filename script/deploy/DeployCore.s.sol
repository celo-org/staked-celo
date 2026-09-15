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
import {
    AddressSortedLinkedList
} from "../../contracts/common/linkedlists/AddressSortedLinkedList.sol";

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
 *        VALIDATOR_GROUPS                Comma separated validator groups to make
 *                                        healthy and activate; empty by default.
 */
contract DeployCore is DeployBase {
    /// @notice Parameters that used to come from `.env` and hardhat-deploy named accounts.
    struct CoreConfig {
        uint256 timeLockMinDelay;
        uint256 timeLockDelay;
        uint256 requiredConfirmations;
        address[] multiSigOwners;
        address[] validatorGroups;
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
    /// @dev Calling this twice on the same instance reuses what the first call deployed,
    ///      which is what `deployments/<network>/` does for a second `run()`.
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
        config.validatorGroups = vm.envOr("VALIDATOR_GROUPS", ",", new address[](0));
    }

    /// @dev Address to reuse for `name`: the one an earlier step of this script already
    ///      deployed, or the one recorded in `deployments/<network>/`. Zero when the
    ///      contract still has to be deployed.
    function _reused(address current, string memory name) private view returns (address) {
        address existing = current != address(0) ? current : readDeploymentAddress(name);
        if (existing != address(0)) {
            DeployLog.a(string(abi.encodePacked(name, ": reused")), existing);
        }
        return existing;
    }

    // =========================================================================
    //                      CONTRACT DEPLOYMENT STEPS
    // =========================================================================

    /// @dev deploy/00: MultiSig. `minDelay` is a constructor argument, the owner set and
    ///      the proposal delay are initializer arguments.
    function _deployMultiSig() private {
        multiSig = _reused(multiSig, "MultiSig");
        if (multiSig != address(0)) {
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
        manager = _reused(manager, "Manager");
        if (manager != address(0)) {
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
        account = _reused(account, "Account");
        if (account != address(0)) {
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
        stakedCelo = _reused(stakedCelo, "StakedCelo");
        if (stakedCelo != address(0)) {
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
        vote = _reused(vote, "Vote");
        if (vote != address(0)) {
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
        groupHealth = _reused(groupHealth, "GroupHealth");
        if (groupHealth != address(0)) {
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
        _updateValidatorGroupHealth();
    }

    /// @dev deploy/05, second part: record the health of every `VALIDATOR_GROUPS` entry.
    ///      `updateGroupHealth` is permissionless, but like the Hardhat script this only
    ///      runs right after a fresh GroupHealth deployment, so re-running the script
    ///      against an existing deployment still sends no transactions.
    function _updateValidatorGroupHealth() private {
        for (uint256 i = 0; i < config.validatorGroups.length; i++) {
            address group = config.validatorGroups[i];
            GroupHealth(groupHealth).updateGroupHealth(group);
            DeployLog.a("GroupHealth: health recorded for", group);
        }
    }

    /// @dev deploy/06: SpecificGroupStrategy.
    function _deploySpecificGroupStrategy() private {
        specificGroupStrategy = _reused(specificGroupStrategy, "SpecificGroupStrategy");
        if (specificGroupStrategy != address(0)) {
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
        defaultStrategy = _reused(defaultStrategy, "DefaultStrategy");
        if (defaultStrategy != address(0)) {
            return;
        }
        address implementation = address(new DefaultStrategy());
        defaultStrategy = _deployProxy(
            implementation,
            abi.encodeWithSelector(DefaultStrategy.initialize.selector, deployer, manager)
        );
        _recordProxyDeployment("DefaultStrategy", defaultStrategy, implementation);
        // The library Forge linked is a contract of its own on chain and has to be
        // verified separately, so record where it ended up.
        _recordImplementationDeployment(
            "AddressSortedLinkedList",
            address(AddressSortedLinkedList)
        );
        DeployLog.a("DefaultStrategy: deployed", defaultStrategy);
        DeployLog.a("AddressSortedLinkedList: linked", address(AddressSortedLinkedList));
    }

    /// @dev deploy/13: RebasedStakedCelo, owned by the MultiSig from the start.
    function _deployRebasedStakedCelo() private {
        rebasedStakedCelo = _reused(rebasedStakedCelo, "RebasedStakedCelo");
        if (rebasedStakedCelo != address(0)) {
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
        _activateValidatorGroups();
    }

    /// @dev deploy/11, second part: activate every healthy `VALIDATOR_GROUPS` entry in the
    ///      DefaultStrategy, the group holding the most CELO first. `addActivatableGroup`
    ///      is `onlyOwner`, so this only works while the deployer still owns the strategy.
    function _activateValidatorGroups() private {
        if (config.validatorGroups.length == 0) {
            return;
        }
        // The Hardhat script used the Manager to detect an upgrade of an already deployed
        // protocol, where activating a group is part of the upgrade proposal instead.
        if (IOwnable(manager).owner() == multiSig) {
            DeployLog.s(
                "DefaultStrategy: Manager owned by MultiSig, activate the groups through it"
            );
            return;
        }
        address[] memory groups = _groupsByCeloDescending();
        for (uint256 i = 0; i < groups.length; i++) {
            _activateValidatorGroup(groups[i]);
        }
    }

    /// @dev Make one group activatable and activate it at the tail of the sorted list.
    ///      Groups the strategy already knows are left alone, so listing a group twice or
    ///      resuming an interrupted run does not revert.
    function _activateValidatorGroup(address group) private {
        DefaultStrategy strategy = DefaultStrategy(defaultStrategy);
        if (strategy.isActive(group)) {
            DeployLog.a("DefaultStrategy: group already active", group);
            return;
        }
        if (!GroupHealth(groupHealth).isGroupValid(group)) {
            DeployLog.a("DefaultStrategy: group is not healthy, not activated", group);
            return;
        }
        if (!_isActivatable(group)) {
            strategy.addActivatableGroup(group);
        }
        // Every group starts with no stCELO, so each one goes in below the current tail
        // and the list ends up in the order the groups were sorted in.
        (address tail, ) = strategy.getGroupsTail();
        strategy.activateGroup(group, address(0), tail);
        DeployLog.a("DefaultStrategy: group activated", group);
    }

    /// @dev Whether the DefaultStrategy already holds `group` in its activatable set.
    function _isActivatable(address group) private view returns (bool) {
        DefaultStrategy strategy = DefaultStrategy(defaultStrategy);
        uint256 count = strategy.activatableGroupsCount();
        for (uint256 i = 0; i < count; i++) {
            if (strategy.getActivatableGroupAt(i) == group) {
                return true;
            }
        }
        return false;
    }

    /// @dev `VALIDATOR_GROUPS` ordered by the CELO the Account holds for each group, most
    ///      first. The sort is stable, so groups holding the same amount - all of them on
    ///      a first deployment - keep the order they were listed in.
    function _groupsByCeloDescending() private view returns (address[] memory groups) {
        uint256 length = config.validatorGroups.length;
        groups = new address[](length);
        uint256[] memory celo = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            groups[i] = config.validatorGroups[i];
            celo[i] = Account(payable(account)).getCeloForGroup(groups[i]);
        }
        // Insertion sort; the list is as long as an environment variable makes it.
        for (uint256 i = 1; i < length; i++) {
            address group = groups[i];
            uint256 value = celo[i];
            uint256 j = i;
            while (j > 0 && celo[j - 1] < value) {
                groups[j] = groups[j - 1];
                celo[j] = celo[j - 1];
                j--;
            }
            groups[j] = group;
            celo[j] = value;
        }
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
