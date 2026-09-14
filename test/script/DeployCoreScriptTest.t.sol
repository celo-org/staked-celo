// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";
import {DeployCore} from "../../script/deploy/DeployCore.s.sol";
import {IOwnable} from "../../script/deploy/DeployBase.s.sol";

/// @dev Cheatcodes used only by this test, cast onto the usual cheatcode address.
interface ScriptTestVm {
    function getDeployedCode(string calldata what) external view returns (bytes memory);
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
            "SpecificGroupStrategy.sol:SpecificGroupStrategy",
            deployScript.specificGroupStrategy()
        );
        _assertArtifactCode("DefaultStrategy.sol:DefaultStrategy", deployScript.defaultStrategy());
        _assertArtifactCode(
            "RebasedStakedCelo.sol:RebasedStakedCelo",
            deployScript.rebasedStakedCelo()
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
        IStrategyDependencies specific = IStrategyDependencies(
            deployScript.specificGroupStrategy()
        );
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
