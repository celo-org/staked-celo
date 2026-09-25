// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";

/**
 * @title IsOwnerScript
 * @notice Check if an address is a multiSig owner. Replaces
 *         `yarn hardhat stakedCelo:multiSig:isOwner --owner-address <address>`.
 *
 * Environment variables:
 *   OWNER_ADDRESS  required. The address of the multiSig contract owner.
 *   NETWORK        optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   OWNER_ADDRESS=0x... forge script script/tasks/multisig/IsOwner.s.sol --rpc-url celo
 */
contract IsOwnerScript is TaskBase {
    /// @notice Reads OWNER_ADDRESS from the environment and prints whether it is an owner.
    function run() external view {
        execute(multiSig(), vm.envAddress("OWNER_ADDRESS"));
    }

    /// @notice Prints whether `ownerAddress` is a MultiSig owner.
    /// @param multiSigContract The MultiSig contract to read from.
    /// @param ownerAddress The address to check.
    function execute(IMultiSigTask multiSigContract, address ownerAddress) internal view {
        TaskConsole.log("is multiSig owner:", multiSigContract.isOwner(ownerAddress));
    }
}
