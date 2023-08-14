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
     * @param group The group's address.
     * @param healthy Whether or not group is healthy.
     */
    event GroupHealthUpdated(address group, bool healthy);

    /**
     * @notice Used when checking elected validator group members
     * but there is member length and indexes length mismatch.
     */
    error MembersLengthMismatch();

    /**
     * @notice Used when calling `markGroupHealthy` on already healthy group.
     * @param group The group's address.
     */
    error GroupHealthy(address group);

    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

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
        return (1, 1, 0, 1);
    }

    /**
     * @notice Updates validator group health.
     * @param group The group address.
     */
    function updateGroupHealth(address group) public {
        IValidators validators = getValidators();

        (bool valid, address[] memory members) = _isGroupPartiallyValid(validators, group);
        if (valid) {
            valid = areGroupMembersElected(members);
        }

        if (isGroupValid[group] != valid) {
            isGroupValid[group] = valid;
            emit GroupHealthUpdated(group, valid);
        }
    }

    /**
     * @notice Updates validator group to healthy if eligible.
     * @param group The group's address.
     * @param membersElectedIndex The indexes of elected members.
     * This array needs to have same length as all (even not elected) members of validator group.
     * Index of not elected member can be any uint256 number.
     */
    function markGroupHealthy(address group, uint256[] calldata membersElectedIndex) public {
        if (isGroupValid[group] == true) {
            revert GroupHealthy(group);
        }

        IValidators validators = getValidators();

        (bool valid, address[] memory members) = _isGroupPartiallyValid(validators, group);

        if (!valid) {
            return;
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
                isGroupValid[group] = true;
                emit GroupHealthUpdated(group, true);
                return;
            }
        }
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
            delete membersMappingHelper[members[j]];
        }
        return result;
    }

    /**
     * Checks group validator status, members and slashing multiplier.
     * @param validators Validators contract.
     * @param group The group to check.
     * @return Whether the group passed checks.
     * @return members The members of the validator group.
     */
    function _isGroupPartiallyValid(IValidators validators, address group)
        private
        view
        returns (bool, address[] memory members)
    {
        if (!validators.isValidatorGroup(group)) {
            return (false, members);
        }

        uint256 slashMultiplier;
        address[] memory originalMembers;
        (originalMembers, , , , , slashMultiplier, ) = validators.getValidatorGroup(group);

        members = new address[](originalMembers.length);

        IAccounts accounts = getAccounts();

        for (uint256 i = 0; i < originalMembers.length; i++) {
            members[i] = accounts.getValidatorSigner(originalMembers[i]);
        }

        // check if group has no members
        if (members.length == 0) {
            return (false, members);
        }
        // check for recent slash
        if (slashMultiplier < 10**24) {
            return (false, members);
        }

        return (true, members);
    }
}
