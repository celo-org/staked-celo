// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskVm.sol";
import "./TaskInterfaces.sol";

/**
 * @title TaskBase
 * @notice Shared plumbing for the StakedCelo operational task scripts: cheatcode access,
 *         deployment address lookup and Celo core contract resolution.
 * @dev Ports the parts of lib/helpers/interfaceHelper.ts that survive the move to Foundry.
 *      Signer selection (useLedger / useNodeAccount / DEPLOYER_PRIVATE_KEY) is handled by
 *      `forge script --ledger | --private-key | --unlocked --sender` instead.
 *
 *      Environment variables read here:
 *        NETWORK  optional, one of celo | sepolia | alfajores | staging. Defaults to the
 *                 network matching the chain id (42220 -> celo, 11142220 -> sepolia,
 *                 44787 -> alfajores).
 */
abstract contract TaskBase {
    /// @dev Foundry cheatcode address (same one forge-std uses).
    TaskVm internal constant vm = TaskVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice The canonical Celo Registry address.
    address internal constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;

    /// @notice Zero address constant (mirrors ADDRESS_ZERO in the Hardhat tasks).
    address internal constant ADDRESS_ZERO = address(0);

    /// @notice Celo mainnet chain id.
    uint256 internal constant CELO_CHAIN_ID = 42220;

    /// @notice Celo Sepolia testnet chain id. The current testnet.
    uint256 internal constant SEPOLIA_CHAIN_ID = 11142220;

    /// @notice Alfajores testnet chain id. The testnet Celo Sepolia replaces.
    uint256 internal constant ALFAJORES_CHAIN_ID = 44787;

    /**
     * @notice Name of the deployments directory to read contract addresses from.
     * @return The value of the NETWORK env var, or the network matching the chain id.
     */
    function networkName() internal view returns (string memory) {
        string memory fromEnv = vm.envOr("NETWORK", string(""));
        if (bytes(fromEnv).length > 0) {
            return fromEnv;
        }
        if (block.chainid == CELO_CHAIN_ID) {
            return "celo";
        }
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            return "sepolia";
        }
        if (block.chainid == ALFAJORES_CHAIN_ID) {
            return "alfajores";
        }
        revert("set NETWORK: chain id has no default deployments directory");
    }

    /**
     * @notice Reads a deployed contract address from deployments/<network>/<name>.json.
     * @param name The hardhat-deploy deployment name, for example "Manager".
     * @return The `address` field of the deployment file.
     */
    function deploymentAddress(string memory name) internal view returns (address) {
        string memory path =
            string(abi.encodePacked("deployments/", networkName(), "/", name, ".json"));
        return vm.parseJsonAddress(vm.readFile(path), ".address");
    }

    /**
     * @notice Resolves a Celo core contract through the Registry.
     * @param identifier The registry identifier, for example "Election".
     * @return The address the Registry holds for `identifier`.
     */
    function coreAddress(string memory identifier) internal view returns (address) {
        return IRegistryLookup(REGISTRY_ADDRESS).getAddressForStringOrDie(identifier);
    }

    /// @notice The Celo Election contract of the connected chain.
    function election() internal view returns (IElectionLookup) {
        return IElectionLookup(coreAddress("Election"));
    }

    /// @notice The Celo LockedGold contract of the connected chain.
    function lockedGold() internal view returns (ILockedGoldLookup) {
        return ILockedGoldLookup(coreAddress("LockedGold"));
    }

    /// @notice The Celo Governance contract of the connected chain.
    function governance() internal view returns (IGovernanceLookup) {
        return IGovernanceLookup(coreAddress("Governance"));
    }

    /// @notice The deployed MultiSig proxy.
    function multiSig() internal view returns (IMultiSigTask) {
        return IMultiSigTask(deploymentAddress("MultiSig"));
    }

    /// @notice The deployed Account proxy.
    function accountContract() internal view returns (IAccountTask) {
        return IAccountTask(deploymentAddress("Account"));
    }

    /// @notice The deployed Manager proxy.
    function managerContract() internal view returns (IManagerTask) {
        return IManagerTask(deploymentAddress("Manager"));
    }

    /// @notice The deployed DefaultStrategy proxy.
    function defaultStrategyContract() internal view returns (IDefaultStrategyTask) {
        return IDefaultStrategyTask(deploymentAddress("DefaultStrategy"));
    }

    /// @notice The deployed SpecificGroupStrategy proxy.
    function specificGroupStrategyContract() internal view returns (ISpecificGroupStrategyTask) {
        return ISpecificGroupStrategyTask(deploymentAddress("SpecificGroupStrategy"));
    }

    /// @notice The deployed GroupHealth proxy.
    function groupHealthContract() internal view returns (IGroupHealthTask) {
        return IGroupHealthTask(deploymentAddress("GroupHealth"));
    }
}
