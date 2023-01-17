// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";

import "./interfaces/IManager.sol";
import "./interfaces/IStakedCelo.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/ISpecificGroupStrategy.sol";
import "./interfaces/IDefaultStrategy.sol";

/**
 * @title GroupHealth stores and updates info about validator group health.
 * Contract returns group validity and also possible need for rebalancing.
 */
contract GroupHealth is UUPSOwnableUpgradeable, UsingRegistryUpgradeable {
    /**
     * @notice Stores validity of group.
     */
    struct GroupValid {
        uint256 epochSetToHealthy;
        bool healthy;
    }

    /**
     * @notice An instance of the StakedCelo contract for the StakedCelo protocol.
     */
    IStakedCelo public stakedCelo;

    /**
     * @notice An instance of the Account contract for the StakedCelo protocol.
     */
    IAccount public account;

    /**
     * @notice An instance of the SpecificGroupStrategy contract for the StakedCelo protocol.
     */
    ISpecificGroupStrategy public specificGroupStrategy;

    /**
     * @notice An instance of the DefaultStrategy contract for the StakedCelo protocol.
     */
    IDefaultStrategy public defaultStrategy;

    /**
     * @notice An instance of the Manager contract for the StakedCelo protocol.
     */
    IManager public manager;

    /**
     * @notice Mapping that stores health state of groups.
     */
    mapping(address => GroupValid) public groupsHealth;

    /**
     * @notice Used when a group does not meet the validator group health requirements.
     * @param group The group's address.
     */
    error GroupNotEligible(address group);

    /**
     * @notice Used when rebalancing to not active nor allowed group.
     * @param group The group's address.
     */
    error InvalidToGroup(address group);

    /**
     * @notice Used when rebalancing from address(0) group.
     * @param group The group's address.
     */
    error InvalidFromGroup(address group);

    /**
     * @notice Used when rebalancing and fromGroup doesn't have any extra CELO.
     * @param group The group's address.
     * @param actualCelo The actual CELO value.
     * @param expectedCelo The expected CELO value.
     */
    error RebalanceNoExtraCelo(address group, uint256 actualCelo, uint256 expectedCelo);

    /**
     * @notice Used when rebalancing and toGroup has enough CELO.
     * @param group The group's address.
     * @param actualCelo The actual CELO value.
     * @param expectedCelo The expected CELO value.
     */
    error RebalanceEnoughCelo(address group, uint256 actualCelo, uint256 expectedCelo);

    /**
     * @notice Used when updating validator group health more than once in epoch.
     * @param group The group's address.
     */
    error ValidatorGroupAlreadyUpdatedInEpoch(address group);

    /**
     * @notice Used when checking elected validator group members
     * but there is member length and indexes length mismatch.
     */
    error MembersLengthMismatch();

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _registry The address of the CELO registry.
     * @param _owner The address of the contract owner.
     */
    function initialize(address _registry, address _owner) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @dev Manager, Account and StakedCelo all reference each other
     * so we need a way of setting these after all contracts are
     * deployed and initialized.
     * @param _stakedCelo the address of the StakedCelo contract.
     * @param _account The address of the Account contract.
     * @param _specificGroupStrategy The address of the SpecificGroupStrategy contract.
     * @param _defaultStrategy The address of the DefaultStrategy contract.
     * @param _manager The address of the Manager contract.
     */
    function setDependencies(
        address _stakedCelo,
        address _account,
        address _specificGroupStrategy,
        address _defaultStrategy,
        address _manager
    ) external onlyOwner {
        require(_stakedCelo != address(0), "StakedCelo null");
        require(_account != address(0), "Account null");
        require(_specificGroupStrategy != address(0), "SpecificGroupStrategy null");
        require(_defaultStrategy != address(0), "DefaultStrategy null");
        require(_manager != address(0), "Manager null");

        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
        specificGroupStrategy = ISpecificGroupStrategy(_specificGroupStrategy);
        defaultStrategy = IDefaultStrategy(_defaultStrategy);
        manager = IManager(_manager);
    }

    /**
     * @notice Returns the storage, major, minor, and patch version of the contract.
     * @return Storage version of the contract.
     * @return Major version of the contract.
     * @return Minor version of the contract.
     * @return Patch version of the contract.
     */
    function getVersionNumber()
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (1, 1, 0, 0);
    }

    /**
     * @notice Updates validator group health.
     * @param group The group to check for.
     * @param membersElectedIndex The indexes of elected members.
     * This array needs to have same length as all (even not elected) members of validator group.
     * Index of not elected member can be whatever uint256 number.
     * @return Whether or not the group is valid.
     */
    function updateGroupHealth(address group, uint256[] calldata membersElectedIndex)
        public
        returns (bool)
    {
        GroupValid storage groupHealth = groupsHealth[group];
        uint256 currentEpoch = getElection().getEpochNumber();
        if (groupHealth.epochSetToHealthy >= currentEpoch) {
            revert ValidatorGroupAlreadyUpdatedInEpoch(group);
        }

        IValidators validators = getValidators();

        if (!validators.isValidatorGroup(group)) {
            groupsHealth[group].healthy = false;
            return false;
        }

        (address[] memory members, , , , , uint256 slashMultiplier, ) = validators
            .getValidatorGroup(group);
        // check if group has no members
        if (members.length == 0) {
            groupsHealth[group].healthy = false;
            return false;
        }
        // check for recent slash
        if (slashMultiplier < 10**24) {
            groupsHealth[group].healthy = false;
            return false;
        }
        if (membersElectedIndex.length != members.length) {
            revert MembersLengthMismatch();
        }
        uint256 currentNumberOfElectedValidators = numberValidatorsInCurrentSet();
        // check that at least one member is elected.
        for (uint256 i = 0; i < members.length; i++) {
            if (
                isGroupMemberElected(
                    members[i],
                    membersElectedIndex[i],
                    currentNumberOfElectedValidators
                )
            ) {
                groupsHealth[group].healthy = true;
                groupsHealth[group].epochSetToHealthy = currentEpoch;
                return true;
            }
        }
        groupsHealth[group].healthy = false;
        return false;
    }

    /**
     * @notice Returns health state of validator group.
     * @param group The group to check for.
     * @return Whether or not the group is valid.
     */
    function isValidGroup(address group) public view returns (bool) {
        GroupValid memory groupValid = groupsHealth[group];
        return groupValid.healthy;
    }

    /**
     * @notice Returns expected CELO amount voted for by Account contract
     * vs actual amount voted for by Account contract.
     * @param group The group.
     * @return expectedCelo The CELO which group should have.
     * @return actualCelo The CELO which group has.
     */
    function getExpectedAndActualCeloForGroup(address group)
        public
        view
        returns (uint256 expectedCelo, uint256 actualCelo)
    {
        bool isSpecificGroupStrategy = specificGroupStrategy.isSpecificGroupStrategy(group);
        bool isActiveGroup = defaultStrategy.groupsContain(group);
        actualCelo = account.getCeloForGroup(group);

        if (!isSpecificGroupStrategy && !isActiveGroup) {
            expectedCelo = 0;
        } else if (isSpecificGroupStrategy && !isActiveGroup) {
            expectedCelo = manager.toCelo(
                specificGroupStrategy.getTotalStCeloVotesForStrategy(group)
            );
        } else if (!isSpecificGroupStrategy && isActiveGroup) {
            expectedCelo = manager.toCelo(defaultStrategy.getTotalStCeloVotesForStrategy(group));
        } else if (isSpecificGroupStrategy && isActiveGroup) {
            uint256 expectedStCeloInActiveGroup = defaultStrategy.getTotalStCeloVotesForStrategy(
                group
            );
            uint256 expectedStCeloInSpecificGroupStrategy = specificGroupStrategy
                .getTotalStCeloVotesForStrategy(group);
            expectedCelo = manager.toCelo(
                expectedStCeloInActiveGroup + expectedStCeloInSpecificGroupStrategy
            );
        }
    }

    /**
     * @notice Rebalances CELO between groups that have incorrect CELO-stCELO ratio.
     * fromGroup is required to have more CELO than it should and toGroup needs
     * to have less CELO than it should.
     * @param fromGroup The from group.
     * @param toGroup The to group.
     * @return fromGroups The origin groups for CELO during rebalance.
     * @return toGroups The destination groups for CELO during  rebalance.
     * @return fromVotes The origin CELO amounts during rebalance.
     * @return toVotes The destination CELO amounts during rebalance.
     */
    function rebalance(address fromGroup, address toGroup)
        public
        view
        returns (
            address[] memory fromGroups,
            address[] memory toGroups,
            uint256[] memory fromVotes,
            uint256[] memory toVotes
        )
    {
        uint256 expectedFromCelo;
        uint256 actualFromCelo;

        if (
            !defaultStrategy.groupsContain(toGroup) &&
            !specificGroupStrategy.isSpecificGroupStrategy(toGroup)
        ) {
            // rebalancing to deprecated/non-existent group is not allowed
            revert InvalidToGroup(toGroup);
        }

        if (fromGroup == address(0)) {
            revert InvalidFromGroup(fromGroup);
        }

        (expectedFromCelo, actualFromCelo) = getExpectedAndActualCeloForGroup(fromGroup);

        if (actualFromCelo <= expectedFromCelo) {
            // fromGroup needs to have more CELO than it should
            revert RebalanceNoExtraCelo(fromGroup, actualFromCelo, expectedFromCelo);
        }

        uint256 expectedToCelo;
        uint256 actualToCelo;

        (expectedToCelo, actualToCelo) = getExpectedAndActualCeloForGroup(toGroup);

        if (actualToCelo >= expectedToCelo) {
            // toGroup needs to have less CELO than it should
            revert RebalanceEnoughCelo(toGroup, actualToCelo, expectedToCelo);
        }

        fromGroups = new address[](1);
        toGroups = new address[](1);
        fromVotes = new uint256[](1);
        toVotes = new uint256[](1);

        fromGroups[0] = fromGroup;
        fromVotes[0] = Math.min(actualFromCelo - expectedFromCelo, expectedToCelo - actualToCelo);

        toGroups[0] = toGroup;
        toVotes[0] = fromVotes[0];
    }

    /**
     * @notice Checks if a group member is elected.
     * @param groupMember The member of the group to check election status for.
     * @param index The index of elected validator in current set.
     * @param currentNumberOfElectedValidators The count of currently elected validators.
     * @return Whether or not the group member is elected.
     */
    function isGroupMemberElected(
        address groupMember,
        uint256 index,
        uint256 currentNumberOfElectedValidators
    ) internal view returns (bool) {
        if (index > currentNumberOfElectedValidators) {
            return false;
        }
        return validatorSignerAddressFromCurrentSet(index) == groupMember;
    }

    /**
     * @notice Gets a validator address from the current validator set.
     * @param index Index of requested validator in the validator set.
     * @return Address of validator at the requested index.
     */
    function validatorSignerAddressFromCurrentSet(uint256 index)
        internal
        view
        virtual
        returns (address)
    {
        return getElection().validatorSignerAddressFromCurrentSet(index);
    }

    /**
     * @notice Gets the size of the current elected validator set.
     * @return Size of the current elected validator set.
     */
    function numberValidatorsInCurrentSet() internal view virtual returns (uint256) {
        return getElection().numberValidatorsInCurrentSet();
    }
}
