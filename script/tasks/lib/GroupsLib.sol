// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskInterfaces.sol";

/**
 * @title GroupsLib
 * @notice Solidity port of lib/task-utils.ts: reading the active and the specific strategy
 *         group lists and merging them the way the account task helpers did.
 */
library GroupsLib {
    /**
     * @notice The active groups of DefaultStrategy, ordered from most to least votes.
     * @dev Ports getDefaultGroupsHHTask: start at the list head and walk the `previous`
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
        (address key, ) = defaultStrategy.getGroupsHead();
        for (uint256 i = 0; i < length; i++) {
            groups[i] = key;
            (key, ) = defaultStrategy.getGroupPreviousAndNext(key);
        }
    }

    /**
     * @notice The groups SpecificGroupStrategy is voting for.
     * @dev Ports getSpecificGroupsHHTask.
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
     * @dev Ports `new Set(activeGroups.concat(specificStrategies))`, which keeps the order
     *      of first appearance.
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
    function _contains(
        address[] memory list,
        uint256 count,
        address value
    ) private pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (list[i] == value) {
                return true;
            }
        }
        return false;
    }
}
