// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/FormatLib.sol";
import "../lib/UpgradeProposalLib.sol";

/**
 * @title UpdateV3ToV4Script
 * @notice Prepares the proposal for the update from V3 to V4. Replaces
 *         `yarn hardhat stakedCelo:multiSig:update:v3:v4`.
 *
 * Environment variables:
 *   NETWORK  optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   forge script script/tasks/multisig/UpdateV3ToV4.s.sol --rpc-url celo
 */
contract UpdateV3ToV4Script is TaskBase {
    /// @notice Prints the DESTINATIONS / VALUES / PAYLOADS of the V3 to V4 proposal.
    function run() external view {
        execute();
    }

    /// @notice Builds and prints the upgrade proposal for Manager, both strategies and Account.
    function execute() internal view {
        string[] memory contracts = new string[](4);
        contracts[0] = "Manager";
        contracts[1] = "SpecificGroupStrategy";
        contracts[2] = "DefaultStrategy";
        contracts[3] = "Account";

        (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        ) = _upgrades(contracts);

        TaskConsole.log("DESTINATIONS", FormatLib.join(destinations));
        TaskConsole.log("VALUES", FormatLib.join(values));
        TaskConsole.log("PAYLOADS", FormatLib.join(payloads));
        TaskConsole.log("Use these values with script/tasks/multisig/SubmitProposal.s.sol");
    }

    /// @dev One upgradeTo operation per named deployment.
    function _upgrades(string[] memory contracts)
        private
        view
        returns (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        )
    {
        destinations = new address[](contracts.length);
        values = new uint256[](contracts.length);
        payloads = new bytes[](contracts.length);

        for (uint256 i = 0; i < contracts.length; i++) {
            destinations[i] = deploymentAddress(contracts[i]);
            values[i] = 0;
            payloads[i] = UpgradeProposalLib.upgradeToPayload(
                deploymentAddress(string(abi.encodePacked(contracts[i], "_Implementation")))
            );
        }
    }
}
