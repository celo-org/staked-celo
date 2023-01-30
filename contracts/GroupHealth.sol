// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";

/**
 * @title GroupHealth stores and updates info about validator group health.
 */
contract GroupHealth is UUPSOwnableUpgradeable, UsingRegistryUpgradeable {
    /**
     * @notice Stores validity of group.
     */
    struct GroupValid {
        uint128 epochSetToHealthy;
        bool healthy;
    }

    /*¨
     * @notice Mapping that stores health state of groups.
     */
    mapping(address => GroupValid) public groupsHealth;

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
     * @notice Used when attempting to pass in address zero where not allowed.
     */
    error AddressZeroNotAllowed();

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _registry The address of the CELO Registry.
     * @param _owner The address of the contract owner.
     */
    function initialize(address _registry, address _owner) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
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
        uint128 currentEpoch = uint128(getElection().getEpochNumber());
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
     * @notice Returns the health state of a validator group.
     * @param group The group to check for.
     * @return Whether or not the group is valid.
     */
    function isValidGroup(address group) public view returns (bool) {
        GroupValid memory groupValid = groupsHealth[group];
        return groupValid.healthy;
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
