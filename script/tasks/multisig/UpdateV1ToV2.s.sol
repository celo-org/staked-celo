// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/FormatLib.sol";
import "../lib/ProposalBuilder.sol";
import "../lib/UpgradeProposalLib.sol";

/**
 * @title UpdateV1ToV2Script
 * @notice Prepares the proposal for the update from V1 to V2. Replaces
 *         `yarn hardhat stakedCelo:multiSig:update:v1:v2`.
 * @dev Like the Hardhat task this script is not purely read only: groups listed in
 *      VALIDATOR_GROUPS that GroupHealth does not consider valid get an `updateGroupHealth`
 *      transaction, and groups that stay unhealthy afterwards are left out of the proposal.
 *      Run with --broadcast to actually send those transactions.
 *
 * Environment variables:
 *   VALIDATOR_GROUPS  optional. Comma separated groups to activate in DefaultStrategy.
 *                     When unset, no activateGroup operation is added.
 *   NETWORK           optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   VALIDATOR_GROUPS=0xA,0xB forge script script/tasks/multisig/UpdateV1ToV2.s.sol \
 *     --rpc-url celo --broadcast --ledger --sender <ledger address>
 */
contract UpdateV1ToV2Script is TaskBase {
    using ProposalBuilder for ProposalBuilder.Proposal;

    /// @notice Reads VALIDATOR_GROUPS from the environment and prints the V1 to V2 proposal.
    function run() external {
        address[] memory validatorGroups = _validatorGroups();

        vm.startBroadcast();
        execute(validatorGroups);
        vm.stopBroadcast();
    }

    /// @notice Builds and prints the V1 to V2 proposal for `validatorGroups`.
    /// @param validatorGroups The groups to activate in DefaultStrategy; may be empty.
    function execute(address[] memory validatorGroups) internal {
        ProposalBuilder.Proposal memory proposal = ProposalBuilder.init(validatorGroups.length + 7);

        _addGroupActivations(proposal, validatorGroups);
        _addUpgrades(proposal);

        proposal.add(
            deploymentAddress("Account"),
            UpgradeProposalLib.setAllowedToVoteOverMaxNumberOfGroupsPayload(true)
        );
        _addManagerSetDependencies(proposal);

        (address[] memory destinations, uint256[] memory values, bytes[] memory payloads) =
            proposal.build();

        TaskConsole.log("DESTINATIONS", FormatLib.join(destinations));
        TaskConsole.log("VALUES", FormatLib.join(values));
        TaskConsole.log("PAYLOADS", FormatLib.join(payloads));
        TaskConsole.log("Use these values with script/tasks/multisig/SubmitProposal.s.sol");
    }

    /// @dev Groups are activated from most to least CELO, each pointing at the previous one.
    function _addGroupActivations(
        ProposalBuilder.Proposal memory proposal,
        address[] memory validatorGroups
    ) private {
        if (validatorGroups.length == 0) {
            return;
        }

        address[] memory sorted = _sortedByCeloDescending(validatorGroups);
        address defaultStrategyAddress = deploymentAddress("DefaultStrategy");
        address nextGroup = ADDRESS_ZERO;

        for (uint256 i = 0; i < sorted.length; i++) {
            if (!_ensureHealthy(sorted[i])) {
                continue;
            }
            proposal.add(
                defaultStrategyAddress,
                UpgradeProposalLib.activateGroupPayload(sorted[i], ADDRESS_ZERO, nextGroup)
            );
            nextGroup = sorted[i];
        }
    }

    /// @dev Updates the health of `group` when needed and reports whether it ends up valid.
    function _ensureHealthy(address group) private returns (bool) {
        IGroupHealthTask groupHealth = groupHealthContract();
        if (groupHealth.isGroupValid(group)) {
            return true;
        }

        TaskConsole.log("Updating group health", group);
        groupHealth.updateGroupHealth(group);

        bool healthy = groupHealth.isGroupValid(group);
        if (!healthy) {
            TaskConsole.log("Group is not healthy - it cannot be activated", group);
        }
        return healthy;
    }

    /// @dev Insertion sort of `groups` by the CELO the Account contract holds for them.
    function _sortedByCeloDescending(address[] memory groups)
        private
        view
        returns (address[] memory sorted)
    {
        IAccountTask account = accountContract();
        sorted = new address[](groups.length);
        uint256[] memory celo = new uint256[](groups.length);

        for (uint256 i = 0; i < groups.length; i++) {
            address group = groups[i];
            uint256 amount = account.getCeloForGroup(group);
            uint256 j = i;
            while (j > 0 && celo[j - 1] < amount) {
                celo[j] = celo[j - 1];
                sorted[j] = sorted[j - 1];
                j--;
            }
            celo[j] = amount;
            sorted[j] = group;
        }
    }

    /// @dev upgradeTo for the five proxies that existed in V1.
    function _addUpgrades(ProposalBuilder.Proposal memory proposal) private view {
        string[] memory names = new string[](5);
        names[0] = "MultiSig";
        names[1] = "Manager";
        names[2] = "Account";
        names[3] = "StakedCelo";
        names[4] = "RebasedStakedCelo";

        for (uint256 i = 0; i < names.length; i++) {
            proposal.add(
                deploymentAddress(names[i]),
                UpgradeProposalLib.upgradeToPayload(
                    deploymentAddress(string(abi.encodePacked(names[i], "_Implementation")))
                )
            );
        }
    }

    /// @dev The Manager.setDependencies operation the Hardhat task appended last.
    function _addManagerSetDependencies(ProposalBuilder.Proposal memory proposal) private view {
        proposal.add(
            deploymentAddress("Manager"),
            UpgradeProposalLib.managerSetDependenciesPayload(
                deploymentAddress("StakedCelo"),
                deploymentAddress("Account"),
                deploymentAddress("Vote"),
                deploymentAddress("GroupHealth"),
                deploymentAddress("SpecificGroupStrategy"),
                deploymentAddress("DefaultStrategy")
            )
        );
    }

    /// @dev VALIDATOR_GROUPS as an address list, empty when the variable is unset.
    function _validatorGroups() private view returns (address[] memory) {
        if (bytes(vm.envOr("VALIDATOR_GROUPS", string(""))).length == 0) {
            return new address[](0);
        }
        return vm.envAddress("VALIDATOR_GROUPS", ",");
    }
}
