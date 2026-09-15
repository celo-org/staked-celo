// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @dev Foundry cheatcodes used by the deployment scripts.
 *      forge-std cannot be imported because it requires pragma >=0.8.13 while the
 *      production profile is locked to 0.8.11, so only the needed cheatcodes are
 *      declared here. Mirrors the approach taken by test/helpers/CeloTestHelper.sol.
 */
interface DeployVm {
    function envUint(string calldata name) external view returns (uint256);

    function envString(string calldata name) external view returns (string memory);

    function envAddress(string calldata name, string calldata delim)
        external
        view
        returns (address[] memory);

    function envOr(string calldata name, string calldata defaultValue)
        external
        view
        returns (string memory);

    function envOr(string calldata name, string calldata delim, address[] calldata defaultValue)
        external
        view
        returns (address[] memory);

    function exists(string calldata path) external view returns (bool);

    function readFile(string calldata path) external view returns (string memory);

    function parseJsonAddress(string calldata json, string calldata key)
        external
        pure
        returns (address);

    function parseAddress(string calldata value) external pure returns (address);

    function serializeAddress(string calldata objectKey, string calldata valueKey, address value)
        external
        returns (string memory);

    function serializeString(
        string calldata objectKey,
        string calldata valueKey,
        string calldata value
    ) external returns (string memory);

    function serializeString(
        string calldata objectKey,
        string calldata valueKey,
        string[] calldata values
    ) external returns (string memory);

    function serializeUint(string calldata objectKey, string calldata valueKey, uint256 value)
        external
        returns (string memory);

    function writeJson(string calldata json, string calldata path) external;

    function createDir(string calldata path, bool recursive) external;

    function startBroadcast() external;

    function stopBroadcast() external;

    function startPrank(address msgSender, address txOrigin) external;

    function stopPrank() external;

    function load(address target, bytes32 slot) external view returns (bytes32);

    function toString(address value) external pure returns (string memory);

    function toString(bytes calldata value) external pure returns (string memory);

    function toString(uint256 value) external pure returns (string memory);
}

/// @dev Ownership surface shared by every upgradeable protocol contract.
interface IOwnable {
    function owner() external view returns (address);

    function transferOwnership(address newOwner) external;
}

/**
 * @dev Minimal console logger. `console.log` is implemented by the Foundry runtime as a
 *      staticcall to a well known address, so no library import is required.
 */
library DeployLog {
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    /// @notice Log a plain message.
    function s(string memory message) internal view {
        (bool ok,) = CONSOLE.staticcall(abi.encodeWithSignature("log(string)", message));
        ok;
    }

    /// @notice Log a labelled address.
    function a(string memory label, address value) internal view {
        (bool ok,) =
            CONSOLE.staticcall(abi.encodeWithSignature("log(string,address)", label, value));
        ok;
    }

    /// @notice Log a labelled number.
    function u(string memory label, uint256 value) internal view {
        (bool ok,) =
            CONSOLE.staticcall(abi.encodeWithSignature("log(string,uint256)", label, value));
        ok;
    }
}

/**
 * @title DeployBase
 * @notice Shared plumbing for the Foundry deployment scripts: network resolution,
 *         hardhat-deploy compatible deployment records and proxy deployment.
 * @dev The deployment records keep the layout written by hardhat-deploy so that the
 *      existing tooling (and the ported CLI scripts) can keep reading
 *      `deployments/<network>/<Name>.json` and pick up `.address`:
 *
 *        <Name>.json                -> address = proxy, implementation = logic
 *        <Name>_Proxy.json          -> address = proxy, implementation = logic
 *        <Name>_Implementation.json -> address = logic
 *
 *      Each record also carries the `args` array hardhat-deploy wrote, so that
 *      `scripts/verify-contracts.sh` can ABI-encode the constructor arguments of the
 *      proxy and of an implementation that takes some instead of guessing them from the
 *      creation code on chain.
 *
 *      The `abi` field written by hardhat-deploy is not reproduced; consumers read the
 *      ABI from the Foundry artifacts in `out/` instead.
 */
abstract contract DeployBase {
    /// @notice Foundry cheatcode address (same one forge-std uses).
    DeployVm internal constant vm =
        DeployVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice EIP-1967 implementation slot.
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Registry argument that makes UsingRegistryUpgradeable fall back to the
    ///         canonical Celo Registry at 0x0...ce10. This is what the Hardhat deploy
    ///         scripts passed for every registry aware contract.
    address internal constant CANONICAL_REGISTRY = address(0);

    /// @notice Name of the deployments directory for the target network.
    string internal network;

    /// @notice Whether deployment records are read and written. Disabled by tests that
    ///         run the sequence in-process.
    bool internal useDeploymentRecords;

    /// @notice The address the deployment transactions originate from.
    address internal deployer;

    // =========================================================================
    //                              NETWORK
    // =========================================================================

    /// @notice Resolve the deployments directory name and enable record keeping.
    /// @dev `NETWORK` wins when set, otherwise the chain id is mapped to the same
    ///      network names the Hardhat config used.
    function _initNetwork() internal {
        network = vm.envOr("NETWORK", _networkFromChainId());
        useDeploymentRecords = true;
        DeployLog.s(string(abi.encodePacked("network: ", network)));
    }

    /// @dev Map the chain id of the connected node onto a deployments directory name.
    function _networkFromChainId() private view returns (string memory) {
        if (block.chainid == 42220) {
            return "celo";
        }
        // Celo Sepolia, the current testnet.
        if (block.chainid == 11142220) {
            return "sepolia";
        }
        // Alfajores, the testnet Celo Sepolia replaces.
        if (block.chainid == 44787) {
            return "alfajores";
        }
        return "local";
    }

    // =========================================================================
    //                         DEPLOYMENT RECORDS
    // =========================================================================

    /// @notice Path of a deployment record.
    /// @param name File name without the `.json` suffix, e.g. `Manager_Implementation`.
    function deploymentPath(string memory name) public view returns (string memory) {
        return string(abi.encodePacked("deployments/", network, "/", name, ".json"));
    }

    /// @notice Address recorded for a contract, or the zero address when not deployed yet.
    /// @param name The contract name, e.g. `Manager`.
    function readDeploymentAddress(string memory name) public view returns (address) {
        if (!useDeploymentRecords) {
            return address(0);
        }
        string memory path = deploymentPath(name);
        if (!vm.exists(path)) {
            return address(0);
        }
        return vm.parseJsonAddress(vm.readFile(path), ".address");
    }

    /// @notice Refresh the three records of a proxy that is already on chain, e.g. after
    ///         an upgrade.
    /// @dev The proxy was constructed by an earlier run, so its constructor arguments are
    ///      not known here and the records carry none; verification recovers them from
    ///      the creation code on chain instead.
    /// @param name The contract name, e.g. `Manager`.
    /// @param proxy The ERC1967 proxy address.
    /// @param implementation The logic contract address.
    function _recordProxyDeployment(string memory name, address proxy, address implementation)
        internal
    {
        string[] memory noArgs = new string[](0);
        _writeRecord(name, name, proxy, implementation, noArgs);
        _writeRecord(string(abi.encodePacked(name, "_Proxy")), name, proxy, implementation, noArgs);
        _recordImplementationDeployment(name, implementation);
    }

    /// @notice Write the three records hardhat-deploy produces for a proxied contract.
    /// @param name The contract name, e.g. `Manager`.
    /// @param proxy The ERC1967 proxy address.
    /// @param implementation The logic contract address.
    /// @param initializeCalldata The call the proxy runs on construction.
    function _recordProxyDeployment(
        string memory name,
        address proxy,
        address implementation,
        bytes memory initializeCalldata
    ) internal {
        _recordProxyDeployment(name, proxy, implementation, initializeCalldata, new string[](0));
    }

    /// @notice Write the three records for a proxied contract whose implementation takes
    ///         constructor arguments.
    /// @param name The contract name, e.g. `MultiSig`.
    /// @param proxy The ERC1967 proxy address.
    /// @param implementation The logic contract address.
    /// @param initializeCalldata The call the proxy runs on construction.
    /// @param implementationArgs The implementation constructor arguments.
    function _recordProxyDeployment(
        string memory name,
        address proxy,
        address implementation,
        bytes memory initializeCalldata,
        string[] memory implementationArgs
    ) internal {
        string[] memory proxyArgs = new string[](2);
        proxyArgs[0] = vm.toString(implementation);
        proxyArgs[1] = vm.toString(initializeCalldata);
        _writeRecord(name, name, proxy, implementation, proxyArgs);
        _writeRecord(
            string(abi.encodePacked(name, "_Proxy")), name, proxy, implementation, proxyArgs
        );
        _recordImplementationDeployment(name, implementation, implementationArgs);
    }

    /// @notice Write the `<Name>_Implementation.json` record.
    /// @param name The contract name, e.g. `Manager`.
    /// @param implementation The logic contract address.
    function _recordImplementationDeployment(string memory name, address implementation) internal {
        _recordImplementationDeployment(name, implementation, new string[](0));
    }

    /// @notice Write the `<Name>_Implementation.json` record of a contract that takes
    ///         constructor arguments.
    /// @param name The contract name, e.g. `MultiSig`.
    /// @param implementation The logic contract address.
    /// @param args The constructor arguments, decimal for numbers and `0x` prefixed for
    ///        addresses and byte strings.
    function _recordImplementationDeployment(
        string memory name,
        address implementation,
        string[] memory args
    ) internal {
        _writeRecord(
            string(abi.encodePacked(name, "_Implementation")),
            name,
            implementation,
            address(0),
            args
        );
    }

    /// @dev Serialize and write a single deployment record.
    function _writeRecord(
        string memory fileName,
        string memory contractName,
        address recorded,
        address implementation,
        string[] memory args
    ) private {
        if (!useDeploymentRecords) {
            return;
        }
        vm.createDir(string(abi.encodePacked("deployments/", network)), true);
        vm.serializeAddress(fileName, "address", recorded);
        vm.serializeString(fileName, "contract", contractName);
        vm.serializeUint(fileName, "chainId", block.chainid);
        vm.serializeAddress(fileName, "deployer", deployer);
        if (implementation != address(0)) {
            vm.serializeAddress(fileName, "implementation", implementation);
        }
        // `args` goes last: the serializer returns the object as it stands after the call.
        string memory json = vm.serializeString(fileName, "args", args);
        vm.writeJson(json, deploymentPath(fileName));
    }

    // =========================================================================
    //                              PROXIES
    // =========================================================================

    /// @notice Deploy an ERC1967 proxy in front of `implementation` and initialize it.
    /// @param implementation The logic contract.
    /// @param initializeCalldata Encoded call run through the proxy on construction.
    /// @return The proxy address.
    function _deployProxy(address implementation, bytes memory initializeCalldata)
        internal
        returns (address)
    {
        return address(new ERC1967Proxy(implementation, initializeCalldata));
    }

    /// @notice Read the implementation an ERC1967 proxy currently points at.
    /// @param proxy The proxy address.
    function implementationOf(address proxy) public view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}
