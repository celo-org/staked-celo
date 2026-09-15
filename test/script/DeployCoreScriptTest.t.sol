// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";
import {DeployCore} from "../../script/deploy/DeployCore.s.sol";
import {IOwnable} from "../../script/deploy/DeployBase.s.sol";

/// @dev Cheatcodes used only by this test, cast onto the usual cheatcode address.
interface ScriptTestVm {
    function getDeployedCode(string calldata what) external view returns (bytes memory);

    function setEnv(string calldata name, string calldata value) external;
}

/// @dev Vote keeps its dependencies in internal storage; getVoteWeight is the cheapest
///      public function that reads through both of them.
interface IVoteWeight {
    function getVoteWeight(address beneficiary) external view returns (uint256);
}

/// @dev The subset of Manager's public dependency getters.
interface IManagerDependencies {
    function voteContract() external view returns (address);

    function groupHealth() external view returns (address);

    function specificGroupStrategy() external view returns (address);

    function defaultStrategy() external view returns (address);
}

/// @dev Public dependency getters shared by both strategy contracts.
interface IStrategyDependencies {
    function account() external view returns (address);

    function groupHealth() external view returns (address);

    function defaultStrategy() external view returns (address);

    function specificGroupStrategy() external view returns (address);
}

/**
 * @title DeployCoreScriptTest
 * @notice Runs script/deploy/DeployCore.s.sol in-process against the Celo devchain and
 *         checks the result matches what deploy/00 .. deploy/13 used to produce.
 * @dev The script sequence is invoked through `runInProcess`, which pranks the deployer
 *      instead of broadcasting and skips the deployment records, so the test never
 *      touches `deployments/`.
 */
contract DeployCoreScriptTest is DevchainHelper {
    ScriptTestVm internal constant svm =
        ScriptTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant REQUIRED_CONFIRMATIONS = 3;

    DeployCore internal deployScript;

    function setUp() public {
        loadDevchain();
        _initNamedAccounts();
        vm.deal(deployer, 10_000 ether);

        deployScript = new DeployCore();
        deployScript.runInProcess(deployer, _config());
    }

    /// @dev MultiSig parameters, standing in for the TIME_LOCK_* environment variables.
    function _config() private view returns (DeployCore.CoreConfig memory config) {
        config.timeLockMinDelay = DAY;
        config.timeLockDelay = 3 * DAY;
        config.requiredConfirmations = REQUIRED_CONFIRMATIONS;

        address[] memory owners = new address[](5);
        owners[0] = multisigOwner0;
        owners[1] = multisigOwner1;
        owners[2] = multisigOwner2;
        owners[3] = multisigOwner3;
        owners[4] = multisigOwner4;
        config.multiSigOwners = owners;
    }

    // =========================================================================
    //                              PROXIES
    // =========================================================================

    function test_everyProxyPointsAtItsImplementation() public {
        _assertProxy(deployScript.multiSig());
        _assertProxy(deployScript.manager());
        _assertProxy(deployScript.account());
        _assertProxy(deployScript.stakedCelo());
        _assertProxy(deployScript.vote());
        _assertProxy(deployScript.groupHealth());
        _assertProxy(deployScript.specificGroupStrategy());
        _assertProxy(deployScript.defaultStrategy());
        _assertProxy(deployScript.rebasedStakedCelo());
    }

    /// @dev A proxy must be a distinct address holding code, pointing at a distinct
    ///      implementation that also holds code.
    function _assertProxy(address proxy) private {
        assertNotEq(proxy, ADDRESS_ZERO);
        assertTrue(proxy.code.length > 0);

        address implementation = deployScript.implementationOf(proxy);
        assertNotEq(implementation, ADDRESS_ZERO);
        assertNotEq(implementation, proxy);
        assertTrue(implementation.code.length > 0);
    }

    // =========================================================================
    //                       PRODUCTION BYTECODE
    // =========================================================================

    function test_implementationsAreTheCompiledArtifacts() public {
        _assertArtifactCode("MultiSig.sol:MultiSig", deployScript.multiSig());
        _assertArtifactCode("Manager.sol:Manager", deployScript.manager());
        _assertArtifactCode("Account.sol:Account", deployScript.account());
        _assertArtifactCode("StakedCelo.sol:StakedCelo", deployScript.stakedCelo());
        _assertArtifactCode("Vote.sol:Vote", deployScript.vote());
        _assertArtifactCode("GroupHealth.sol:GroupHealth", deployScript.groupHealth());
    }

    function test_strategyImplementationsAreTheCompiledArtifacts() public {
        _assertArtifactCode(
            "SpecificGroupStrategy.sol:SpecificGroupStrategy", deployScript.specificGroupStrategy()
        );
        _assertArtifactCode("DefaultStrategy.sol:DefaultStrategy", deployScript.defaultStrategy());
        _assertArtifactCode(
            "RebasedStakedCelo.sol:RebasedStakedCelo", deployScript.rebasedStakedCelo()
        );
    }

    /// @dev The implementation behind `proxy` must be the compiler artifact for
    ///      `artifact`. Bytes may only differ where the artifact holds an immutable
    ///      placeholder: every protocol contract is UUPS, and OpenZeppelin's
    ///      UUPSUpgradeable stores `address(this)` in an immutable, which the artifact
    ///      leaves zeroed. MultiSig has a second one for `minDelay`.
    function _assertArtifactCode(string memory artifact, address proxy) private {
        bytes memory onChain = deployScript.implementationOf(proxy).code;
        bytes memory artifactCode = svm.getDeployedCode(artifact);
        assertEq(onChain.length, artifactCode.length);

        uint256 placeholderBytes = 0;
        for (uint256 i = 0; i < artifactCode.length; i++) {
            if (onChain[i] == artifactCode[i]) {
                continue;
            }
            require(artifactCode[i] == 0, "bytecode differs outside immutable placeholders");
            placeholderBytes++;
        }
        // Two immutable slots at most, each 32 bytes, each referenced a handful of times.
        assertTrue(placeholderBytes <= 10 * 32);
    }

    // =========================================================================
    //                            WIRING
    // =========================================================================

    function test_managerDependenciesAreWired() public {
        IManagerDependencies manager = IManagerDependencies(deployScript.manager());
        assertEq(manager.voteContract(), deployScript.vote());
        assertEq(manager.groupHealth(), deployScript.groupHealth());
        assertEq(manager.specificGroupStrategy(), deployScript.specificGroupStrategy());
        assertEq(manager.defaultStrategy(), deployScript.defaultStrategy());
    }

    function test_strategyDependenciesAreWired() public {
        IStrategyDependencies specific = IStrategyDependencies(deployScript.specificGroupStrategy());
        assertEq(specific.account(), deployScript.account());
        assertEq(specific.groupHealth(), deployScript.groupHealth());
        assertEq(specific.defaultStrategy(), deployScript.defaultStrategy());

        IStrategyDependencies byDefault = IStrategyDependencies(deployScript.defaultStrategy());
        assertEq(byDefault.account(), deployScript.account());
        assertEq(byDefault.groupHealth(), deployScript.groupHealth());
        assertEq(byDefault.specificGroupStrategy(), deployScript.specificGroupStrategy());
    }

    function test_voteDependenciesAreWired() public {
        // Reverts on decoding an empty return value if StakedCelo or Account is unset.
        assertEq(IVoteWeight(deployScript.vote()).getVoteWeight(randomAddress()), 0);
    }

    // =========================================================================
    //                           OWNERSHIP
    // =========================================================================

    function test_allContractsAreOwnedByTheMultiSig() public {
        _assertOwnedByMultiSig(deployScript.manager());
        _assertOwnedByMultiSig(deployScript.account());
        _assertOwnedByMultiSig(deployScript.stakedCelo());
        _assertOwnedByMultiSig(deployScript.vote());
        _assertOwnedByMultiSig(deployScript.specificGroupStrategy());
        _assertOwnedByMultiSig(deployScript.defaultStrategy());
        _assertOwnedByMultiSig(deployScript.groupHealth());
        _assertOwnedByMultiSig(deployScript.rebasedStakedCelo());
    }

    function _assertOwnedByMultiSig(address target) private {
        assertEq(IOwnable(target).owner(), deployScript.multiSig());
    }

    function test_multiSigIsInitialized() public {
        IMultiSig multiSigProxy = IMultiSig(deployScript.multiSig());
        assertEq(multiSigProxy.getOwners().length, 5);
        assertTrue(multiSigProxy.isOwner(multisigOwner0));
        assertTrue(multiSigProxy.isOwner(multisigOwner4));
        assertEq(multiSigProxy.required(), REQUIRED_CONFIRMATIONS);
        assertEq(multiSigProxy.delay(), 3 * DAY);
    }

    // =========================================================================
    //                            REGISTRY
    // =========================================================================

    function test_registryAwareContractsUseTheCanonicalRegistry() public {
        // Passing address(0) to the initializer makes UsingRegistryUpgradeable fall back
        // to 0x0...ce10, which is what the Hardhat deploy scripts relied on.
        assertEq(_registryOf(deployScript.manager()), REGISTRY_ADDRESS);
        assertEq(_registryOf(deployScript.account()), REGISTRY_ADDRESS);
        assertEq(_registryOf(deployScript.vote()), REGISTRY_ADDRESS);
        assertEq(_registryOf(deployScript.groupHealth()), REGISTRY_ADDRESS);
    }

    function _registryOf(address target) private returns (address) {
        (bool ok, bytes memory data) = target.call(abi.encodeWithSignature("registry()"));
        assertTrue(ok);
        return abi.decode(data, (address));
    }
}

/**
 * @title DeployCoreValidatorGroupsTest
 * @notice Covers the `VALIDATOR_GROUPS` part of the sequence: deploy/05 records the health
 *         of every listed group and deploy/11 activates the healthy ones in the
 *         DefaultStrategy.
 * @dev GroupHealth considers a group healthy when one of its members' signers is in the
 *      elected set, which on the L2 devchain comes from EpochManager. The devchain's own
 *      validators are elected, but their groups are anvil development accounts that the
 *      test also uses elsewhere, so freshly registered groups are elected through a mock of
 *      the two EpochManager views Election reads the set from.
 */
contract DeployCoreValidatorGroupsTest is DevchainHelper {
    uint256 internal constant REQUIRED_CONFIRMATIONS = 3;

    DeployCore internal deployScript;

    /// @dev Three registered groups whose single member is elected.
    address[] internal healthyGroups;
    /// @dev A registered group whose member is not elected.
    address internal unelectedGroup;

    function setUp() public {
        loadDevchain();
        _initNamedAccounts();
        vm.deal(deployer, 10_000 ether);

        address[] memory electedSigners = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            (address group, address signer) = _registerGroupWithOneValidator();
            healthyGroups.push(group);
            electedSigners[i] = signer;
        }
        (unelectedGroup,) = _registerGroupWithOneValidator();
        _electSigners(electedSigners);

        deployScript = new DeployCore();
        deployScript.runInProcess(deployer, _config());
    }

    /// @dev Register a validator group with a single member and return the group together
    ///      with the signer of that member, which is what GroupHealth looks for in the
    ///      elected set.
    function _registerGroupWithOneValidator() private returns (address group, address signer) {
        group = createWallet();
        registerValidatorGroup(group);
        address validator = createWallet();
        registerValidatorAndAddToGroupMembers(group, validator);
        signer = celoAccounts.getValidatorSigner(validator);
    }

    /// @dev Make `signers` the elected set. Election reports the set of the current epoch
    ///      straight from EpochManager on the L2 devchain, and running the real epoch
    ///      process would need the oracles the devchain fixture does not have.
    function _electSigners(address[] memory signers) private {
        dvm.mockCall(
            address(celoEpochManager),
            abi.encodeWithSelector(ICeloEpochManager.numberOfElectedInCurrentSet.selector),
            abi.encode(signers.length)
        );
        for (uint256 i = 0; i < signers.length; i++) {
            dvm.mockCall(
                address(celoEpochManager),
                abi.encodeWithSelector(ICeloEpochManager.getElectedSignerByIndex.selector, i),
                abi.encode(signers[i])
            );
        }
    }

    /// @dev The unhealthy group and a repeated entry are listed on purpose: the script has
    ///      to skip both instead of reverting.
    function _config() private view returns (DeployCore.CoreConfig memory config) {
        config.timeLockMinDelay = DAY;
        config.timeLockDelay = 3 * DAY;
        config.requiredConfirmations = REQUIRED_CONFIRMATIONS;

        address[] memory owners = new address[](5);
        owners[0] = multisigOwner0;
        owners[1] = multisigOwner1;
        owners[2] = multisigOwner2;
        owners[3] = multisigOwner3;
        owners[4] = multisigOwner4;
        config.multiSigOwners = owners;

        address[] memory groups = new address[](5);
        groups[0] = healthyGroups[0];
        groups[1] = healthyGroups[1];
        groups[2] = unelectedGroup;
        groups[3] = healthyGroups[2];
        groups[4] = healthyGroups[0];
        config.validatorGroups = groups;
    }

    function _groupHealth() private view returns (GroupHealth) {
        return GroupHealth(deployScript.groupHealth());
    }

    function _defaultStrategy() private view returns (DefaultStrategy) {
        return DefaultStrategy(deployScript.defaultStrategy());
    }

    // =========================================================================
    //                            GROUP HEALTH
    // =========================================================================

    function test_healthIsRecordedForEveryListedGroup() public {
        assertTrue(_groupHealth().isGroupValid(healthyGroups[0]));
        assertTrue(_groupHealth().isGroupValid(healthyGroups[1]));
        assertTrue(_groupHealth().isGroupValid(healthyGroups[2]));
        assertFalse(_groupHealth().isGroupValid(unelectedGroup));
    }

    // =========================================================================
    //                            ACTIVATION
    // =========================================================================

    function test_healthyGroupsAreActiveInTheListedOrder() public {
        _assertActiveInListedOrder();
    }

    function test_unhealthyGroupIsNotActivated() public {
        assertFalse(_defaultStrategy().isActive(unelectedGroup));
    }

    function test_noGroupIsLeftActivatable() public {
        assertEq(_defaultStrategy().activatableGroupsCount(), 0);
    }

    /// @dev A second run finds the protocol deployed and the DefaultStrategy owned by the
    ///      MultiSig, so it touches neither the health records nor the active groups.
    function test_secondRunSkipsTheGroups() public {
        address strategyBefore = deployScript.defaultStrategy();

        deployScript.runInProcess(deployer, _config());

        assertEq(deployScript.defaultStrategy(), strategyBefore);
        assertEq(deployScript.groupHealth(), address(_groupHealth()));
        _assertActiveInListedOrder();
        assertEq(_defaultStrategy().activatableGroupsCount(), 0);
    }

    /// @dev The three healthy groups, most CELO first. They all hold none, so the order is
    ///      the one they were listed in.
    function _assertActiveInListedOrder() private {
        DefaultStrategy strategy = _defaultStrategy();
        assertEq(strategy.getNumberOfGroups(), 3);

        (address head,) = strategy.getGroupsHead();
        assertEq(head, healthyGroups[0]);

        // The list runs from the head towards the tail along the `previous` pointers.
        (address previous,) = strategy.getGroupPreviousAndNext(head);
        assertEq(previous, healthyGroups[1]);

        (address tail,) = strategy.getGroupsTail();
        assertEq(tail, healthyGroups[2]);
    }
}

/// @dev Makes DeployCore's environment parsing callable from a test. Nothing is deployed
///      through this harness, so it needs no devchain.
contract DeployCoreEnvHarness is DeployCore {
    function configFromEnv() external view returns (CoreConfig memory) {
        return _configFromEnv();
    }
}

/**
 * @title DeployCoreEnvConfigTest
 * @notice Covers how DeployCore reads its configuration: the canonical `MULTISIG_OWNERS`
 *         and the Hardhat era `MULTISIG_SIGNER_0` .. `MULTISIG_SIGNER_4`, which the
 *         encrypted per-network env files (`yarn keys:decrypt`) still carry.
 * @dev Everything lives in one test on purpose. Environment variables belong to the
 *      process rather than to the EVM state forge snapshots after `setUp`, so a second
 *      test function would see whatever this one set last - and forge is free to run the
 *      two in either order, or at the same time.
 */
contract DeployCoreEnvConfigTest is CeloTestHelper {
    ScriptTestVm internal constant svm =
        ScriptTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant SIGNER_0 = 0x0a692a271DfAf2d36E46f50269c932511B55e871;
    address internal constant SIGNER_1 = 0x2B73d814BA2231606f9d856C7C20423915F96711;
    address internal constant SIGNER_2 = 0x5bC1C4C1D67C5E4384189302BC653A611568a788;
    address internal constant OWNER_0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant OWNER_1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    uint256 internal constant REQUIRED_CONFIRMATIONS = 3;

    function test_ownersComeFromEitherSpellingOfTheOwnerSet() public {
        DeployCoreEnvHarness harness = new DeployCoreEnvHarness();
        _setCommonEnv();
        _clearOwnerEnv();

        // Neither spelling set: the run has to stop with a message naming both.
        vm.expectRevert(bytes("set MULTISIG_OWNERS, or MULTISIG_SIGNER_0, MULTISIG_SIGNER_1, ..."));
        harness.configFromEnv();

        // The Hardhat era variables, read consecutively from zero.
        svm.setEnv(_signerName(0), vm.toString(SIGNER_0));
        svm.setEnv(_signerName(1), vm.toString(SIGNER_1));
        svm.setEnv(_signerName(2), vm.toString(SIGNER_2));

        DeployCore.CoreConfig memory config = harness.configFromEnv();
        assertEq(config.multiSigOwners.length, 3);
        assertEq(config.multiSigOwners[0], SIGNER_0);
        assertEq(config.multiSigOwners[1], SIGNER_1);
        assertEq(config.multiSigOwners[2], SIGNER_2);
        // The rest of the configuration is read exactly as before.
        assertEq(config.timeLockMinDelay, DAY);
        assertEq(config.timeLockDelay, 3 * DAY);
        assertEq(config.requiredConfirmations, REQUIRED_CONFIRMATIONS);

        // A hole in the numbering ends the owner set rather than skipping an entry.
        svm.setEnv(_signerName(1), "");
        address[] memory upToTheGap = harness.configFromEnv().multiSigOwners;
        assertEq(upToTheGap.length, 1);
        assertEq(upToTheGap[0], SIGNER_0);
        svm.setEnv(_signerName(1), vm.toString(SIGNER_1));

        // MULTISIG_OWNERS wins whenever it is set.
        svm.setEnv(
            "MULTISIG_OWNERS",
            string(abi.encodePacked(vm.toString(OWNER_0), ",", vm.toString(OWNER_1)))
        );
        address[] memory owners = harness.configFromEnv().multiSigOwners;
        assertEq(owners.length, 2);
        assertEq(owners[0], OWNER_0);
        assertEq(owners[1], OWNER_1);

        _clearOwnerEnv();
    }

    /// @dev The variables that are not about the owner set.
    function _setCommonEnv() private {
        svm.setEnv("TIME_LOCK_MIN_DELAY", vm.toString(DAY));
        svm.setEnv("TIME_LOCK_DELAY", vm.toString(3 * DAY));
        svm.setEnv("MULTISIG_REQUIRED_CONFIRMATIONS", vm.toString(REQUIRED_CONFIRMATIONS));
    }

    /// @dev Empty out both spellings, so that the test does not depend on what the
    ///      surrounding shell or a local `.env` happens to hold.
    function _clearOwnerEnv() private {
        svm.setEnv("MULTISIG_OWNERS", "");
        for (uint256 i = 0; i < 5; i++) {
            svm.setEnv(_signerName(i), "");
        }
    }

    function _signerName(uint256 index) private pure returns (string memory) {
        return string(abi.encodePacked("MULTISIG_SIGNER_", vm.toString(index)));
    }
}
