// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IGroupHealth {
    function rebalance(address fromGroup, address toGroup)
        external
        returns (
            address[] memory fromGroups,
            address[] memory toGroups,
            uint256[] memory fromVotes,
            uint256[] memory toVotes
        );

    function isValidGroup(address group) external view returns (bool);

    function getExpectedAndActualCeloForGroup(address group)
        external
        view
        returns (uint256, uint256);
}
