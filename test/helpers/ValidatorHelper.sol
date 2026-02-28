// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./interfaces/IMultiSig.sol";
import "./MultiSigHelper.sol";

// Minimal interface for MockRegistry methods used in this helper.
// Avoids importing MockRegistry.sol directly to prevent Initializable
// name collision between OZ contracts and OZ contracts-upgradeable.
interface IMockRegistryForValidator {
    function owner() external view returns (address);
    function setAddressFor(string calldata identifier, address addr) external;
}

/**
 * @title ValidatorHelper
 * @notice Provides validator registration and election test utilities.
 * @dev Ports all functions from test-ts/utils-validators.ts to Solidity.
 *      Uses mock contracts for simplified testing without real Celo core contracts.
 *      Group members are tracked internally via _groupMembers since MockValidators
 *      has no public member getter. Always use addValidatorToGroupMembers() from
 *      this helper rather than calling mockValidators.setMembers() directly.
 */
abstract contract ValidatorHelper is MultiSigHelper {
    /// @dev BLS public key test fixture (hardcoded, not real crypto)
    bytes internal constant BLS_PUBLIC_KEY =
        hex"4fa3f67fc913878b068d1fa1cdddc54913d3bf988dbe5a36a20fa888f20d4894c408a6773f3d7bde11154f2a3076b700d345a42fd25a0e5e83f4db5586ac7979ac2053cd95d8f2efd3e959571ceccaa743e02cf4be3f5d7aaddb0b06fc9aff00";

    /// @dev BLS proof-of-possession test fixture (hardcoded, not real crypto)
    bytes internal constant BLS_POP =
        hex"cdb77255037eb68897cd487fdd85388cbda448f617f874449d4b11588b0b7ad8ddc20d9bb450b513bb35664ea3923900";

    /// @dev Internal tracking of group members (MockValidators.members is private)
    mapping(address => address[]) internal _groupMembers;

    // =========================================================================
    // Registration helpers
    // =========================================================================

    /**
     * @notice Registers an address as a validator group with locked CELO.
     * @dev Ports registerValidatorGroup (utils-validators.ts lines 26-48).
     * @param mockValidators The MockValidators contract.
     * @param mockLockedGold The MockLockedGold contract.
     * @param group The address to register as a validator group.
     * @param numMembers Number of expected members (determines locked CELO requirement).
     */
    function registerValidatorGroup(
        MockValidators mockValidators,
        MockLockedGold mockLockedGold,
        address group,
        uint256 numMembers
    ) internal {
        mockValidators.setValidatorGroup(group);
        mockLockedGold.setAccountTotalLockedGold(group, MIN_VALIDATOR_LOCKED_CELO * numMembers);
    }

    /**
     * @notice Registers a validator, affiliates to group, and adds as group member.
     * @dev Ports registerValidatorAndAddToGroupMembers (utils-validators.ts lines 51-58).
     * @param mockValidators The MockValidators contract.
     * @param mockLockedGold The MockLockedGold contract.
     * @param group The group address to join.
     * @param validator The validator address to register.
     */
    function registerValidatorAndAddToGroupMembers(
        MockValidators mockValidators,
        MockLockedGold mockLockedGold,
        address group,
        address validator
    ) internal {
        registerValidatorAndOnlyAffiliateToGroup(mockValidators, mockLockedGold, group, validator);
        addValidatorToGroupMembers(mockValidators, group, validator);
    }

    /**
     * @notice Registers a validator and affiliates to a group without adding as member.
     * @dev Ports registerValidatorAndOnlyAffiliateToGroup (utils-validators.ts lines 60-99).
     *      BLS keys use hardcoded test constants (BLS_PUBLIC_KEY, BLS_POP).
     * @param mockValidators The MockValidators contract.
     * @param mockLockedGold The MockLockedGold contract.
     * @param group The group address to affiliate with.
     * @param validator The validator address to register.
     */
    function registerValidatorAndOnlyAffiliateToGroup(
        MockValidators mockValidators,
        MockLockedGold mockLockedGold,
        address group,
        address validator
    ) internal {
        // Register as validator
        mockValidators.setValidator(validator);
        // Lock minimum CELO
        mockLockedGold.setAccountTotalLockedGold(validator, MIN_VALIDATOR_LOCKED_CELO);
        // Affiliate with group (must be called by validator)
        vm.prank(validator);
        mockValidators.affiliate(group);
    }

    // =========================================================================
    // Group membership helpers
    // =========================================================================

    /**
     * @notice Adds a validator to a group's member list.
     * @dev Ports addValidatorToGroupMembers (utils-validators.ts lines 101-110).
     *      Tracks members internally and syncs with MockValidators.setMembers.
     * @param mockValidators The MockValidators contract.
     * @param group The group to add the validator to.
     * @param validator The validator to add as a member.
     */
    function addValidatorToGroupMembers(
        MockValidators mockValidators,
        address group,
        address validator
    ) internal {
        _groupMembers[group].push(validator);
        // Copy storage to memory for external call
        uint256 len = _groupMembers[group].length;
        address[] memory members = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            members[i] = _groupMembers[group][i];
        }
        mockValidators.setMembers(group, members);
    }

    /**
     * @notice Removes all members from a validator group.
     * @dev Ports removeMembersFromGroup (utils-validators.ts lines 112-127).
     * @param mockValidators The MockValidators contract.
     * @param group The group to remove all members from.
     */
    function removeMembersFromGroup(MockValidators mockValidators, address group) internal {
        delete _groupMembers[group];
        address[] memory empty = new address[](0);
        mockValidators.setMembers(group, empty);
    }

    /**
     * @notice Deregisters a validator group after removing members and time-traveling.
     * @dev Ports deregisterValidatorGroup (utils-validators.ts lines 129-139).
     * @param mockValidators The MockValidators contract.
     * @param group The group to deregister.
     */
    function deregisterValidatorGroup(MockValidators mockValidators, address group) internal {
        removeMembersFromGroup(mockValidators, group);
        // Time travel past group locked gold requirement duration (3 days + margin)
        vm.warp(block.timestamp + 5 * DAY);
        vm.prank(group);
        mockValidators.deregisterValidatorGroup(0);
    }

    // =========================================================================
    // DefaultStrategy activation helpers
    // =========================================================================

    /**
     * @notice Activates validator groups in DefaultStrategy via MultiSig proposals.
     * @dev Ports activateValidators (utils-validators.ts lines 141-177).
     *      For each group: validates health, submits addActivatableGroup proposal,
     *      then submits activateGroup proposal via MultiSig.
     * @param defaultStrategy The DefaultStrategy contract address.
     * @param groupHealth The GroupHealth contract address (for isGroupValid check).
     * @param multiSig The MultiSig contract address.
     * @param multisigSigner The signer for MultiSig proposals.
     * @param groupAddresses The group addresses to activate.
     */
    function activateValidators(
        address defaultStrategy,
        address groupHealth,
        address multiSig,
        address multisigSigner,
        address[] memory groupAddresses
    ) internal {
        DefaultStrategy ds = DefaultStrategy(defaultStrategy);
        MockGroupHealth gh = MockGroupHealth(groupHealth);
        IMultiSig ms = IMultiSig(multiSig);

        (address nextGroup, ) = ds.getGroupsTail();

        for (uint256 i = 0; i < groupAddresses.length; i++) {
            require(gh.isGroupValid(groupAddresses[i]), "ValidatorHelper: group is not valid");

            // Reusable single-element arrays
            address[] memory destinations = new address[](1);
            destinations[0] = defaultStrategy;
            uint256[] memory values = new uint256[](1);
            bytes[] memory payloads = new bytes[](1);

            // Submit + execute addActivatableGroup
            payloads[0] = abi.encodeWithSignature(
                "addActivatableGroup(address)",
                groupAddresses[i]
            );
            submitAndExecuteMultiSigProposal(ms, destinations, values, payloads, multisigSigner);

            // Submit + execute activateGroup
            payloads[0] = abi.encodeWithSignature(
                "activateGroup(address,address,address)",
                groupAddresses[i],
                address(0),
                nextGroup
            );
            submitAndExecuteMultiSigProposal(ms, destinations, values, payloads, multisigSigner);

            nextGroup = groupAddresses[i];
        }
    }

    // =========================================================================
    // Election helpers
    // =========================================================================

    /**
     * @notice Simulates locking CELO and voting for a group.
     * @dev Ports voteForGroup (utils-validators.ts lines 179-189).
     *      Uses setAccountTotalLockedGold instead of actual lock() for simplicity.
     * @param mockLockedGold The MockLockedGold contract.
     * @param mockElection The MockElection contract.
     * @param group The group to vote for.
     * @param voter The voter address.
     */
    function voteForGroup(
        MockLockedGold mockLockedGold,
        MockElection mockElection,
        address group,
        address voter
    ) internal {
        // Simulate locking 1 CELO
        uint256 currentLocked = mockLockedGold.accountTotalLockedGold(voter);
        mockLockedGold.setAccountTotalLockedGold(voter, currentLocked + 1 ether);
        // Cast vote
        vm.prank(voter);
        mockElection.vote(group, 1 ether, address(0), address(0));
    }

    /**
     * @notice Activates pending votes for a voter.
     * @dev Ports activateVotesForGroup (utils-validators.ts lines 191-200).
     * @param mockElection The MockElection contract.
     * @param voter The voter address.
     */
    function activateVotesForGroup(MockElection mockElection, address voter) internal {
        vm.prank(voter);
        mockElection.activate(voter);
    }

    /**
     * @notice Votes for a group and activates after simulated epoch change.
     * @dev Ports electGroup (utils-validators.ts lines 202-206).
     *      Uses time warp instead of mineToNextEpoch since mocks don't enforce epochs.
     * @param mockLockedGold The MockLockedGold contract.
     * @param mockElection The MockElection contract.
     * @param group The group to elect.
     * @param voter The voter address.
     */
    function electGroup(
        MockLockedGold mockLockedGold,
        MockElection mockElection,
        address group,
        address voter
    ) internal {
        voteForGroup(mockLockedGold, mockElection, group, voter);
        // Simulate epoch change
        vm.warp(block.timestamp + DAY);
        activateVotesForGroup(mockElection, voter);
    }

    // =========================================================================
    // Slashing helpers
    // =========================================================================

    /**
     * @notice Registers a mock slasher and halves a group's slashing multiplier.
     * @dev Ports updateGroupSlashingMultiplier (utils-validators.ts lines 208-228).
     * @param mockRegistry The MockRegistry contract address.
     * @param mockLockedGold The MockLockedGold contract.
     * @param mockValidators The MockValidators contract.
     * @param group The group whose slashing multiplier to halve.
     * @param mockSlasher The address to register as mock slasher.
     */
    function updateGroupSlashingMultiplier(
        address mockRegistry,
        MockLockedGold mockLockedGold,
        MockValidators mockValidators,
        address group,
        address mockSlasher
    ) internal {
        IMockRegistryForValidator registry = IMockRegistryForValidator(mockRegistry);
        address coreContractsOwner = registry.owner();

        vm.prank(coreContractsOwner);
        registry.setAddressFor("MockSlasher", mockSlasher);

        vm.prank(coreContractsOwner);
        mockLockedGold.addSlasher("MockSlasher");

        vm.prank(mockSlasher);
        mockValidators.halveSlashingMultiplier(group);

        // Simulate epoch change
        vm.warp(block.timestamp + DAY);
    }

    // =========================================================================
    // Mock election helpers
    // =========================================================================

    /**
     * @notice Sets validators as elected in MockGroupHealth and optionally updates health.
     * @dev Ports electMockValidatorGroupsAndUpdate (utils-validators.ts lines 230-264).
     *      The makeOneValidatorGroupUseSigner logic is omitted since mock contracts
     *      don't require validator signer authorization.
     * @param mockValidators The MockValidators contract.
     * @param mockGroupHealth The MockGroupHealth contract address.
     * @param validatorGroups The groups whose members should be set as elected.
     * @param revoke If true, sets elected validators to address(0).
     * @param update If true, calls updateGroupHealth for each group.
     * @return mockedIndexes The indices used for setElectedValidator.
     */
    function electMockValidatorGroupsAndUpdate(
        MockValidators mockValidators,
        address mockGroupHealth,
        address[] memory validatorGroups,
        bool revoke,
        bool update
    ) internal returns (uint256[] memory) {
        MockGroupHealth gh = MockGroupHealth(mockGroupHealth);
        uint256 validatorsProcessed = 0;

        // Count total members for array sizing
        uint256 totalMembers = 0;
        for (uint256 j = 0; j < validatorGroups.length; j++) {
            if (mockValidators.isValidatorGroup(validatorGroups[j])) {
                totalMembers += _groupMembers[validatorGroups[j]].length;
            }
        }

        uint256[] memory mockedIndexes = new uint256[](totalMembers);
        uint256 indexCount = 0;

        for (uint256 j = 0; j < validatorGroups.length; j++) {
            address validatorGroup = validatorGroups[j];

            if (mockValidators.isValidatorGroup(validatorGroup)) {
                address[] storage members = _groupMembers[validatorGroup];
                for (uint256 i = 0; i < members.length; i++) {
                    uint256 mockIndex = validatorsProcessed++;
                    gh.setElectedValidator(
                        mockIndex,
                        revoke ? address(0) : members[i]
                    );
                    mockedIndexes[indexCount++] = mockIndex;
                }
            }

            if (update) {
                gh.updateGroupHealth(validatorGroup);
            }
        }

        return mockedIndexes;
    }

    // =========================================================================
    // Internal view helpers
    // =========================================================================

    /**
     * @notice Returns the tracked members of a group.
     * @param group The group address.
     * @return The array of member addresses.
     */
    function getGroupMembers(address group) internal view returns (address[] memory) {
        return _groupMembers[group];
    }
}
