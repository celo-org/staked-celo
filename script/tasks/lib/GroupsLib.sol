// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskInterfaces.sol";

/**
 * @title GroupsLib
 * @notice Reads the active and the specific strategy group lists and merges them for the
 *         account tasks.
 */
library GroupsLib {
    /**
     * @notice The active groups of DefaultStrategy, ordered from most to least votes.
     * @dev Starts at the list head and walks the `previous`
     *      links for as many elements as the list holds.
     * @param defaultStrategy The DefaultStrategy contract.
     * @return groups The active groups.
     */
    function defaultGroups(IDefaultStrategyTask defaultStrategy)
        internal
        view
        returns (address[] memory groups)
    {
        uint256 length = defaultStrategy.getNumberOfGroups();
        groups = new address[](length);
        (address key,) = defaultStrategy.getGroupsHead();
        for (uint256 i = 0; i < length; i++) {
            groups[i] = key;
            (key,) = defaultStrategy.getGroupPreviousAndNext(key);
        }
    }

    /**
     * @notice The groups SpecificGroupStrategy is voting for.
     * @param specificGroupStrategy The SpecificGroupStrategy contract.
     * @return groups The voted groups.
     */
    function specificGroups(ISpecificGroupStrategyTask specificGroupStrategy)
        internal
        view
        returns (address[] memory groups)
    {
        uint256 length = specificGroupStrategy.getNumberOfVotedGroups();
        groups = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            groups[i] = specificGroupStrategy.getVotedGroup(i);
        }
    }

    /**
     * @notice Active groups followed by the specific strategy groups, without duplicates.
     * @dev Keeps the order of first appearance.
     * @param defaultStrategy The DefaultStrategy contract.
     * @param specificGroupStrategy The SpecificGroupStrategy contract.
     * @return The merged group list.
     */
    function allGroups(
        IDefaultStrategyTask defaultStrategy,
        ISpecificGroupStrategyTask specificGroupStrategy
    ) internal view returns (address[] memory) {
        return _dedupe(defaultGroups(defaultStrategy), specificGroups(specificGroupStrategy));
    }

    /// @dev Concatenate two lists, dropping repeats while keeping first appearance order.
    function _dedupe(address[] memory first, address[] memory second)
        private
        pure
        returns (address[] memory merged)
    {
        address[] memory buffer = new address[](first.length + second.length);
        uint256 count = 0;
        for (uint256 i = 0; i < first.length + second.length; i++) {
            address candidate = i < first.length ? first[i] : second[i - first.length];
            if (!_contains(buffer, count, candidate)) {
                buffer[count] = candidate;
                count++;
            }
        }

        merged = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            merged[i] = buffer[i];
        }
    }

    /// @dev Whether the first `count` entries of `list` hold `value`.
    function _contains(address[] memory list, uint256 count, address value)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < count; i++) {
            if (list[i] == value) {
                return true;
            }
        }
        return false;
    }
}
