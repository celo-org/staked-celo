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
 *        MULTISIG_OWNERS                 Comma separated list of MultiSig owners, or the
 *                                        Hardhat era MULTISIG_SIGNER_0, MULTISIG_SIGNER_1,
 *                                        ... which the encrypted per-network env files
 *                                        still carry.
 *      Optional:
 *        NETWORK                         Deployments directory name; defaults to the chain
 *                                        id mapping (celo / sepolia / alfajores / staging /
 *                                        local).
 *        VALIDATOR_GROUPS                Comma separated validator groups to make
 *                                        healthy and activate; empty by default.
 *
 *      DEPLOYER, the Hardhat named account, is not read: the deployer is the signer forge
 *      is given (--ledger, --private-key, --account). --ledger needs --sender next to it,
 *      because the address is only known to the device; without it the run stops before the
 *      first transaction instead of handing the protocol to forge's default sender.
 */
contract DeployCore is DeployBase {
    /// @notice Parameters that used to come from `.env` and hardhat-deploy named accounts.
    struct CoreConfig {
        uint256 timeLockMinDelay;
        uint256 timeLockDelay;
        uint256 requiredConfirmations;
        address[] multiSigOwners;
        address[] validatorGroups;
        /// @dev The account the deployment is attributed to and that initially owns the
        ///      wired contracts. `run()` fills it in from the broadcast, the tests set it.
        address deployer;
    }

    CoreConfig internal config;

    /// @notice How far the `MULTISIG_SIGNER_<i>` scan goes. `MultiSig.MAX_OWNER_COUNT`;
    ///         the initializer rejects a longer owner set anyway.
    uint256 internal constant MAX_MULTISIG_SIGNER_VARS = 50;

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
    /// @dev The deployer is read from inside the broadcast rather than from `msg.sender`:
    ///      the two differ whenever the signer is not the simulation sender, which is
    ///      exactly the `--ledger` without `--sender` case, and the contracts would then be
    ///      initialized as owned by an account nobody holds the key to.
    function run() external {
        _initNetwork();
        config = _configFromEnv();
        vm.startBroadcast();
        deployer = _readBroadcaster("DeployCore");
        config.deployer = deployer;
        _deployAll();
        vm.stopBroadcast();
        _logSummary();
    }

    /// @notice Run the exact same sequence in-process, impersonating `coreConfig.deployer`
    ///         and without touching the deployment records. Used by the tests.
    /// @dev Calling this twice on the same instance reuses what the first call deployed,
    ///      which is what `deployments/<network>/` does for a second `run()`.
    /// @param coreConfig The MultiSig parameters and the deployer to deploy with.
    function runInProcess(CoreConfig memory coreConfig) external {
        network = "in-process";
        useDeploymentRecords = false;
        deployer = coreConfig.deployer;
        config = coreConfig;
        vm.startPrank(deployer, deployer);
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
    function _configFromEnv() internal view returns (CoreConfig memory coreConfig) {
        coreConfig.timeLockMinDelay = vm.envUint("TIME_LOCK_MIN_DELAY");
        coreConfig.timeLockDelay = vm.envUint("TIME_LOCK_DELAY");
        coreConfig.requiredConfirmations = vm.envUint("MULTISIG_REQUIRED_CONFIRMATIONS");
        coreConfig.multiSigOwners = _multiSigOwnersFromEnv();
        coreConfig.validatorGroups = vm.envOr("VALIDATOR_GROUPS", ",", new address[](0));
    }

    /// @dev The MultiSig owner set, from either spelling of it.
    ///      `MULTISIG_OWNERS` is the canonical one. When it is empty the Hardhat era
    ///      `MULTISIG_SIGNER_0`, `MULTISIG_SIGNER_1`, ... are read instead, which is what
    ///      the encrypted per-network env files (`yarn keys:decrypt`) still carry.
    function _multiSigOwnersFromEnv() private view returns (address[] memory owners) {
        string memory list = vm.envOr("MULTISIG_OWNERS", string(""));
        if (bytes(list).length > 0) {
            return vm.envAddress("MULTISIG_OWNERS", ",");
        }
        owners = _multiSigSignersFromEnv();
        require(
            owners.length > 0, "set MULTISIG_OWNERS, or MULTISIG_SIGNER_0, MULTISIG_SIGNER_1, ..."
        );
    }

    /// @dev `MULTISIG_SIGNER_<i>` from 0 upwards, stopping at the first one that is unset
    ///      or empty. The addresses are parsed by hand so that an empty value reads as the
    ///      end of the list rather than as a parse failure.
    function _multiSigSignersFromEnv() private view returns (address[] memory signers) {
        address[] memory found = new address[](MAX_MULTISIG_SIGNER_VARS);
        uint256 count = 0;
        while (count < found.length) {
            string memory value = vm.envOr(_multiSigSignerName(count), string(""));
            if (bytes(value).length == 0) {
                break;
            }
            found[count] = vm.parseAddress(value);
            count++;
        }
        signers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            signers[i] = found[i];
        }
    }

    /// @dev `MULTISIG_SIGNER_<index>`.
    function _multiSigSignerName(uint256 index) private pure returns (string memory) {
        return string(abi.encodePacked("MULTISIG_SIGNER_", vm.toString(index)));
    }

    /// @dev Address to reuse for `name`: the one an earlier step of this script already
    ///      deployed, or the one recorded in `deployments/<network>/`. Zero when the
    ///      contract still has to be deployed.
    function _reused(address current, string memory name) private view returns (address) {
        if (current != address(0)) {
            return current;
        }
        address existing = readDeploymentAddress(name);
        if (existing == address(0)) {
            return address(0);
        }
        // A dry run writes records too, so a record may point at an address that was never
        // deployed. Reusing it would skip the deployment and fail at the first call.
        if (existing.code.length == 0) {
            DeployLog.a(
                string(abi.encodePacked(name, ": record has no code on this chain, deploying")),
                existing
            );
            return address(0);
        }
        DeployLog.a(string(abi.encodePacked(name, ": reused")), existing);
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
        bytes memory initializeCalldata = abi.encodeWithSelector(
            MultiSig.initialize.selector,
            config.multiSigOwners,
            config.requiredConfirmations,
            config.timeLockDelay
        );
        multiSig = _deployProxy(implementation, initializeCalldata);
        // The only implementation with a constructor argument, and the only one whose
        // record therefore needs `args` of its own.
        string[] memory implementationArgs = new string[](1);
        implementationArgs[0] = vm.toString(config.timeLockMinDelay);
        _recordProxyDeployment(
            "MultiSig", multiSig, implementation, initializeCalldata, implementationArgs
        );
        DeployLog.a("MultiSig: deployed", multiSig);
    }

    /// @dev deploy/01: Manager, initially owned by the deployer so it can be wired up.
    function _deployManager() private {
        manager = _reused(manager, "Manager");
        if (manager != address(0)) {
            return;
        }
        address implementation = address(new Manager());
        bytes memory initializeCalldata =
            abi.encodeWithSelector(Manager.initialize.selector, CANONICAL_REGISTRY, deployer);
        manager = _deployProxy(implementation, initializeCalldata);
        _recordProxyDeployment("Manager", manager, implementation, initializeCalldata);
        DeployLog.a("Manager: deployed", manager);
    }

    /// @dev deploy/02: Account. Its initializer registers the proxy as a Celo account.
    function _deployAccount() private {
        account = _reused(account, "Account");
        if (account != address(0)) {
            return;
        }
        address implementation = address(new Account());
        bytes memory initializeCalldata = abi.encodeWithSelector(
            Account.initialize.selector, CANONICAL_REGISTRY, manager, deployer
        );
        account = _deployProxy(implementation, initializeCalldata);
        _recordProxyDeployment("Account", account, implementation, initializeCalldata);
        DeployLog.a("Account: deployed", account);
    }

    /// @dev deploy/03: StakedCelo.
    function _deployStakedCelo() private {
        stakedCelo = _reused(stakedCelo, "StakedCelo");
        if (stakedCelo != address(0)) {
            return;
        }
        address implementation = address(new StakedCelo());
        bytes memory initializeCalldata =
            abi.encodeWithSelector(StakedCelo.initialize.selector, manager, deployer);
        stakedCelo = _deployProxy(implementation, initializeCalldata);
        _recordProxyDeployment("StakedCelo", stakedCelo, implementation, initializeCalldata);
        DeployLog.a("StakedCelo: deployed", stakedCelo);
    }

    /// @dev deploy/04: Vote.
    function _deployVote() private {
        vote = _reused(vote, "Vote");
        if (vote != address(0)) {
            return;
        }
        address implementation = address(new Vote());
        bytes memory initializeCalldata =
            abi.encodeWithSelector(Vote.initialize.selector, CANONICAL_REGISTRY, deployer, manager);
        vote = _deployProxy(implementation, initializeCalldata);
        _recordProxyDeployment("Vote", vote, implementation, initializeCalldata);
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
        bytes memory initializeCalldata =
            abi.encodeWithSelector(GroupHealth.initialize.selector, CANONICAL_REGISTRY, multiSig);
        groupHealth = _deployProxy(implementation, initializeCalldata);
        _recordProxyDeployment("GroupHealth", groupHealth, implementation, initializeCalldata);
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
        bytes memory initializeCalldata =
            abi.encodeWithSelector(SpecificGroupStrategy.initialize.selector, deployer, manager);
        specificGroupStrategy = _deployProxy(implementation, initializeCalldata);
        _recordProxyDeployment(
            "SpecificGroupStrategy", specificGroupStrategy, implementation, initializeCalldata
        );
        DeployLog.a("SpecificGroupStrategy: deployed", specificGroupStrategy);
    }

    /// @dev deploy/07: DefaultStrategy. Forge deploys and links AddressSortedLinkedList.
    function _deployDefaultStrategy() private {
        defaultStrategy = _reused(defaultStrategy, "DefaultStrategy");
        if (defaultStrategy != address(0)) {
            return;
        }
        address implementation = address(new DefaultStrategy());
        bytes memory initializeCalldata =
            abi.encodeWithSelector(DefaultStrategy.initialize.selector, deployer, manager);
        defaultStrategy = _deployProxy(implementation, initializeCalldata);
        _recordProxyDeployment(
            "DefaultStrategy", defaultStrategy, implementation, initializeCalldata
        );
        // The library Forge linked is a contract of its own on chain and has to be
        // verified separately, so record where it ended up.
        _recordImplementationDeployment("AddressSortedLinkedList", address(AddressSortedLinkedList));
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
        bytes memory initializeCalldata = abi.encodeWithSelector(
            RebasedStakedCelo.initialize.selector, stakedCelo, account, multiSig
        );
        rebasedStakedCelo = _deployProxy(implementation, initializeCalldata);
        _recordProxyDeployment(
            "RebasedStakedCelo", rebasedStakedCelo, implementation, initializeCalldata
        );
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
        Manager(manager)
            .setDependencies(
                stakedCelo, account, vote, groupHealth, specificGroupStrategy, defaultStrategy
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
        SpecificGroupStrategy(specificGroupStrategy)
            .setDependencies(account, groupHealth, defaultStrategy);
        DeployLog.s("SpecificGroupStrategy: dependencies set");
    }

    /// @dev deploy/11: DefaultStrategy.setDependencies.
    function _setDefaultStrategyDependencies() private {
        if (_ownedByMultiSig(defaultStrategy, "DefaultStrategy")) {
            return;
        }
        DefaultStrategy(defaultStrategy)
            .setDependencies(account, groupHealth, specificGroupStrategy);
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
        (address tail,) = strategy.getGroupsTail();
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
                    name, ": owned by MultiSig, propose setDependencies through the MultiSig"
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
