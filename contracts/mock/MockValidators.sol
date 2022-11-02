//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title Holds a list of addresses of validators
 */
contract MockValidators {
    using SafeMath for uint256;

    uint256 private constant FIXED1_UINT = 1000000000000000000000000;

    mapping(address => bool) public isValidator;
    mapping(address => bool) public isValidatorGroup;
    mapping(address => uint256) private numGroupMembers;
    mapping(address => uint256) private lockedGoldRequirements;
    mapping(address => bool) private doesNotMeetAccountLockedGoldRequirements;
    mapping(address => address[]) private members;
    mapping(address => address) private affiliations;
    uint256 private numRegisteredValidators;

    function updateEcdsaPublicKey(
        address,
        address,
        bytes calldata
    ) external returns (bool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function updatePublicKeys(
        address,
        address,
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) external returns (bool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function setValidator(address account) external {
        isValidator[account] = true;
    }

    function setValidatorGroup(address group) external {
        isValidatorGroup[group] = true;
    }

    function deregisterValidator(uint256 index) external returns (bool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function affiliate(address group) external returns (bool) {
        affiliations[msg.sender] = group;
        return true;
    }

    function deregisterValidatorGroup(uint256 index) external returns (bool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function setDoesNotMeetAccountLockedGoldRequirements(address account) external {
        doesNotMeetAccountLockedGoldRequirements[account] = true;
    }

    function meetsAccountLockedGoldRequirements(address account) external view returns (bool) {
        return !doesNotMeetAccountLockedGoldRequirements[account];
    }

    function getGroupNumMembers(address group) public view returns (uint256) {
        return members[group].length;
    }

    function setNumRegisteredValidators(uint256 value) external {
        numRegisteredValidators = value;
    }

    function getNumRegisteredValidators() external view returns (uint256) {
        return numRegisteredValidators;
    }

    function setMembers(address group, address[] calldata _members) external {
        members[group] = _members;
    }

    function setAccountLockedGoldRequirement(address account, uint256 value) external {
        lockedGoldRequirements[account] = value;
    }

    function getAccountLockedGoldRequirement(address account) external view returns (uint256) {
        return lockedGoldRequirements[account];
    }

    function calculateGroupEpochScore(uint256[] calldata uptimes) external view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getTopGroupValidators(address group, uint256 n)
        external
        view
        returns (address[] memory)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getGroupsNumMembers(address[] calldata groups)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory numMembers = new uint256[](groups.length);
        for (uint256 i = 0; i < groups.length; i = i.add(1)) {
            numMembers[i] = getGroupNumMembers(groups[i]);
        }
        return numMembers;
    }

    function groupMembershipInEpoch(
        address addr,
        uint256,
        uint256
    ) external view returns (address) {
        return affiliations[addr];
    }

    function halveSlashingMultiplier(address account) external {
        // solhint-disable-previous-line no-empty-blocks
    }

    function forceDeaffiliateIfValidator(address validator) external {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getValidatorGroupSlashingMultiplier(address) external view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
