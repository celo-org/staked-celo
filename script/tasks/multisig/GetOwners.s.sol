// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";

/**
 * @title GetOwnersScript
 * @notice Get multiSig owners. Replaces `yarn hardhat stakedCelo:multiSig:getOwners`.
 *
 * Environment variables:
 *   NETWORK  optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   forge script script/tasks/multisig/GetOwners.s.sol --rpc-url celo
 */
contract GetOwnersScript is TaskBase {
    /// @notice Reads the MultiSig address from the deployments and prints its owners.
    function run() external view {
        execute(multiSig());
    }

    /// @notice Prints the owners of `multiSigContract`.
    /// @param multiSigContract The MultiSig contract to read from.
    function execute(IMultiSigTask multiSigContract) internal view {
        address[] memory owners = multiSigContract.getOwners();
        TaskConsole.log("Current multiSig owners:", owners.length);
        for (uint256 i = 0; i < owners.length; i++) {
            TaskConsole.log("owner", owners[i]);
        }
    }
}
