//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../interfaces/IElection.sol";

/**
 * @notice A mock Election contract that abides by the IElection interface.
 * This is purely intended for tests and allows the return values of some functions
 * to be set for testing purposes.
 */
contract MockElection is IElection {
    // ---- settable return values for interface functions ----
    bool private activateReturnValue;
    bool private voteReturnValue;
    bool private hasActivatablePendingVotesReturnValue;

    uint256 public maxNumGroupsVotedFor;
    mapping(address => bool) public allowedToVoteOverMaxNumberOfGroupsMapping;

    constructor() {
        // Set the return values to a benign default value
        activateReturnValue = true;
        voteReturnValue = true;
        hasActivatablePendingVotesReturnValue = false;
    }

    // ---- setters for return values ----

    function setActivateReturnValue(bool value) external {
        activateReturnValue = value;
    }

    function setVoteReturnValue(bool value) external {
        voteReturnValue = value;
    }

    function setHasActivatablePendingVotesReturnValue(bool value) external {
        hasActivatablePendingVotesReturnValue = value;
    }

    // ---- interface functions ----

    function vote(
        address,
        uint256,
        address,
        address
    ) external returns (bool) {
        // silence complier error that this function can be view
        voteReturnValue = voteReturnValue;

        return voteReturnValue;
    }

    function activate(address) external returns (bool) {
        // silence complier error that this function can be view
        activateReturnValue = activateReturnValue;

        return activateReturnValue;
    }

    function activateForAccount(address, address) external returns (bool) {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;

        return true;
    }

    function revokeActive(
        address,
        uint256,
        address,
        address,
        uint256
    ) external returns (bool) {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;

        return true;
    }

    function revokeAllActive(
        address,
        address,
        address,
        uint256
    ) external returns (bool) {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;

        return true;
    }

    function revokePending(
        address,
        uint256,
        address,
        address,
        uint256
    ) external returns (bool) {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;

        return true;
    }

    function markGroupIneligible(address) external {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;
    }

    function markGroupEligible(
        address,
        address,
        address
    ) external {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;
    }

    function forceDecrementVotes(
        address,
        uint256,
        address[] calldata,
        address[] calldata,
        uint256[] calldata
    ) external returns (uint256) {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;

        return 0;
    }

    // only owner
    function setElectableValidators(uint256, uint256) external returns (bool) {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;

        return true;
    }

    function setMaxNumGroupsVotedFor(uint256) external returns (bool) {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;

        return true;
    }

    function setElectabilityThreshold(uint256) external returns (bool) {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;

        return true;
    }

    function setAllowedToVoteOverMaxNumberOfGroups(bool flag) external {
        allowedToVoteOverMaxNumberOfGroupsMapping[msg.sender] = flag;
    }

    // only VM
    function distributeEpochRewards(
        address,
        uint256,
        address,
        address
    ) external {
        // silence complier error that this function can be view / pure
        activateReturnValue = activateReturnValue;
    }

    // view functions
    function electValidatorSigners() external view returns (address[] memory) {
        // silence complier error that this function can be pure
        activateReturnValue;

        address[] memory arr;
        return arr;
    }

    function electNValidatorSigners(uint256, uint256) external view returns (address[] memory) {
        // silence complier error that this function can be pure
        activateReturnValue;

        address[] memory arr;
        return arr;
    }

    function getElectableValidators() external view returns (uint256, uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return (0, 0);
    }

    function getElectabilityThreshold() external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getNumVotesReceivable(address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getTotalVotes() external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getActiveVotes() external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getTotalVotesByAccount(address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getPendingVotesForGroupByAccount(address, address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getActiveVotesForGroupByAccount(address, address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getTotalVotesForGroupByAccount(address, address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getActiveVoteUnitsForGroupByAccount(address, address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getTotalVotesForGroup(address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getActiveVotesForGroup(address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getPendingVotesForGroup(address) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getGroupEligibility(address) external view returns (bool) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return true;
    }

    function getGroupEpochRewards(
        address,
        uint256,
        uint256[] calldata
    ) external view returns (uint256) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return 0;
    }

    function getGroupsVotedForByAccount(address) external view returns (address[] memory) {
        // silence complier error that this function can be pure
        activateReturnValue;

        address[] memory arr;
        return arr;
    }

    function getEligibleValidatorGroups() external view returns (address[] memory) {
        // silence complier error that this function can be pure
        activateReturnValue;

        address[] memory arr;
        return arr;
    }

    function getTotalVotesForEligibleValidatorGroups()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        // silence complier error that this function can be pure
        activateReturnValue;

        address[] memory addressArr;
        uint256[] memory uint256Arr;
        return (addressArr, uint256Arr);
    }

    function getCurrentValidatorSigners() external view returns (address[] memory) {
        // silence complier error that this function can be pure
        activateReturnValue;

        address[] memory arr;
        return arr;
    }

    function canReceiveVotes(address, uint256) external view returns (bool) {
        // silence complier error that this function can be pure
        activateReturnValue;

        return true;
    }

    function hasActivatablePendingVotes(address, address) external view returns (bool) {
        return hasActivatablePendingVotesReturnValue;
    }

    function allowedToVoteOverMaxNumberOfGroups(address) external view returns (bool) {
        return allowedToVoteOverMaxNumberOfGroupsMapping[msg.sender];
    }

    function validatorSignerAddressFromCurrentSet(uint256 index) external view returns (address) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function numberValidatorsInCurrentSet() external view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getEpochNumber() external view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
