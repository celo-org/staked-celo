// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/UpgradeProposalLib.sol";

/**
 * @title EncodeManagerSetDependenciesScript
 * @notice Encodes the Manager.setDependencies proposal payload. Replaces
 *         `yarn hardhat stakedCelo:multisig:encode:managerSetDependencies`.
 * @dev The Hardhat task also repaired the deployment ABI file when hardhat-deploy had only
 *      refreshed `Manager_Implementation.json`. Foundry reads addresses, never ABIs, from
 *      the deployment files, so that step has no counterpart here.
 *
 * Environment variables:
 *   NETWORK  optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   forge script script/tasks/multisig/EncodeManagerSetDependencies.s.sol --rpc-url celo
 */
contract EncodeManagerSetDependenciesScript is TaskBase {
    /// @notice Reads the deployed addresses and prints the submitProposal inputs.
    function run() external view {
        execute();
    }

    /**
     * @notice Builds the Manager.setDependencies payload from the deployment addresses.
     * @return destination The Manager proxy address.
     * @return value The CELO value of the operation, always zero.
     * @return payload The encoded setDependencies calldata.
     */
    function execute()
        internal
        view
        returns (
            address destination,
            uint256 value,
            bytes memory payload
        )
    {
        destination = deploymentAddress("Manager");
        value = 0;
        payload = UpgradeProposalLib.managerSetDependenciesPayload(
            deploymentAddress("StakedCelo"),
            deploymentAddress("Account"),
            deploymentAddress("Vote"),
            deploymentAddress("GroupHealth"),
            deploymentAddress("SpecificGroupStrategy"),
            deploymentAddress("DefaultStrategy")
        );

        TaskConsole.log("DESTINATIONS", destination);
        TaskConsole.log("VALUES", value);
        TaskConsole.log("PAYLOADS", vm.toString(payload));
        TaskConsole.log("Use these values with script/tasks/multisig/SubmitProposal.s.sol");
    }
}
