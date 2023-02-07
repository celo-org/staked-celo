// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";

/**
 * @title GroupHealth stores and updates info about validator group health.
 */
contract GroupHealth is UUPSOwnableUpgradeable, UsingRegistryUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Mapping that stores health state of groups.
     */
    mapping(address => bool) public isGroupValid;

    /**
     * @notice Used as helper varible during call to `areGroupMembersElected`.
     */
    mapping(address => bool) private membersMappingHelper;

    /**
     * @notice Emitted when `updateGroupHealth` called.
     * @param group The group that is being updated.
     * @param healthy Whether or not group is healthy.
     */
    event GroupHealthUpdated(address group, bool healthy);

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
     * @return Whether or not the group is valid.
     */
    function updateGroupHealth(address group) public returns (bool) {
        IValidators validators = getValidators();

        if (!validators.isValidatorGroup(group)) {
            isGroupValid[group] = false;
            emit GroupHealthUpdated(group, false);
            return false;
        }

        (address[] memory members, , , , , uint256 slashMultiplier, ) = validators
            .getValidatorGroup(group);
        // check if group has no members
        if (members.length == 0) {
            isGroupValid[group] = false;
            emit GroupHealthUpdated(group, false);
            return false;
        }
        // check for recent slash
        if (slashMultiplier < 10**24) {
            isGroupValid[group] = false;
            emit GroupHealthUpdated(group, false);
            return false;
        }

        // check that at least one member is elected.
        if (areGroupMembersElected(members)) {
            isGroupValid[group] = true;
            emit GroupHealthUpdated(group, true);
            return true;
        }

        isGroupValid[group] = false;
        emit GroupHealthUpdated(group, false);
        return false;
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

    /**
     * @notice Checks if any of group members are elected.
     * @param members All group members of checked validator group.
     * @return Whether or not any of the group members are elected.
     */
    function areGroupMembersElected(address[] memory members) private returns (bool) {
        for (uint256 j = 0; j < members.length; j++) {
            membersMappingHelper[members[j]] = true;
        }

        bool result;
        address validator;
        uint256 n = numberValidatorsInCurrentSet();
        for (uint256 i = 0; i < n; i++) {
            validator = validatorSignerAddressFromCurrentSet(i);
            if (membersMappingHelper[validator] == true) {
                result = true;
                break;
            }
        }

        for (uint256 j = 0; j < members.length; j++) {
            membersMappingHelper[members[j]] = false;
        }
        return result;
    }
}
