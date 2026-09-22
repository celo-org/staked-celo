// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/FormatLib.sol";
import "../lib/ProposalBuilder.sol";
import "../lib/UpgradeProposalLib.sol";

/**
 * @title UpdateV2ToV3Script
 * @notice Prepares the proposal for the update from V2 to V3. Replaces
 *         `yarn hardhat stakedCelo:multiSig:update:v2:v3`.
 *
 * Environment variables:
 *   NETWORK             optional. Deployments directory: celo | sepolia | local.
 *   NEW_MULTISIG_OWNER  optional. Owner added by the proposal; defaults to the address the
 *                       Hardhat task hardcoded.
 *
 * Usage:
 *   forge script script/tasks/multisig/UpdateV2ToV3.s.sol --rpc-url celo
 */
contract UpdateV2ToV3Script is TaskBase {
    using ProposalBuilder for ProposalBuilder.Proposal;

    /// @dev The owner the Hardhat task added.
    address internal constant DEFAULT_NEW_OWNER = 0x01AAe13F65fB90B490E6614adE0bffFA57AC5bbc;

    /// @dev Minimum number of active groups the proposal sets on DefaultStrategy.
    uint256 internal constant MIN_COUNT_OF_ACTIVE_GROUPS = 3;

    /// @notice Prints the DESTINATIONS / VALUES / PAYLOADS of the V2 to V3 proposal.
    function run() external view {
        execute(vm.envOr("NEW_MULTISIG_OWNER", DEFAULT_NEW_OWNER));
    }

    /// @notice Builds and prints the V2 to V3 proposal.
    /// @param newOwner The owner to add to the MultiSig.
    function execute(address newOwner) internal view {
        ProposalBuilder.Proposal memory proposal = ProposalBuilder.init(20);

        _addUpgrades(proposal);
        _addPausers(proposal);

        proposal.add(
            deploymentAddress("DefaultStrategy"),
            UpgradeProposalLib.setMinCountOfActiveGroupsPayload(MIN_COUNT_OF_ACTIVE_GROUPS)
        );
        _addOwner(proposal, newOwner);

        (address[] memory destinations, uint256[] memory values, bytes[] memory payloads) =
            proposal.build();

        TaskConsole.log("DESTINATIONS", FormatLib.join(destinations));
        TaskConsole.log("VALUES", FormatLib.join(values));
        TaskConsole.log("PAYLOADS", FormatLib.join(payloads));
        TaskConsole.log("Use these values with script/tasks/multisig/SubmitProposal.s.sol");
    }

    /// @dev upgradeTo for every proxy of the deployment.
    function _addUpgrades(ProposalBuilder.Proposal memory proposal) private view {
        string[] memory names = _allContracts();
        for (uint256 i = 0; i < names.length; i++) {
            proposal.add(
                deploymentAddress(names[i]),
                UpgradeProposalLib.upgradeToPayload(
                    deploymentAddress(string(abi.encodePacked(names[i], "_Implementation")))
                )
            );
        }
    }

    /// @dev MultiSig.setPauser(multiSig) followed by setPauser() on the other contracts.
    function _addPausers(ProposalBuilder.Proposal memory proposal) private view {
        address multiSigAddress = deploymentAddress("MultiSig");
        proposal.add(multiSigAddress, UpgradeProposalLib.setPauserPayload(multiSigAddress));

        string[] memory names = _allContracts();
        for (uint256 i = 1; i < names.length; i++) {
            proposal.add(deploymentAddress(names[i]), UpgradeProposalLib.setPauserPayload());
        }
    }

    /// @dev MultiSig.addOwner for the new owner.
    function _addOwner(ProposalBuilder.Proposal memory proposal, address newOwner) private view {
        require(newOwner != ADDRESS_ZERO, "Invalid Owner address");
        proposal.add(deploymentAddress("MultiSig"), UpgradeProposalLib.addOwnerPayload(newOwner));
    }

    /// @dev The contracts of the deployment, MultiSig first, in the Hardhat task's order.
    function _allContracts() private pure returns (string[] memory names) {
        names = new string[](9);
        names[0] = "MultiSig";
        names[1] = "Manager";
        names[2] = "Account";
        names[3] = "StakedCelo";
        names[4] = "Vote";
        names[5] = "GroupHealth";
        names[6] = "SpecificGroupStrategy";
        names[7] = "DefaultStrategy";
        names[8] = "RebasedStakedCelo";
    }
}
