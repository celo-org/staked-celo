// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IDefaultStrategy {
    function generateVoteDistribution(
        uint256 celoAmount,
        bool withdraw,
        address groupToIgnore
    ) external returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function activateGroup(address group) external;

    function addToStrategyTotalStCeloVotes(address strategy, uint256 stCeloAmount) external;

    function subtractFromStrategyTotalStCeloVotes(address strategy, uint256 stCeloAmount) external;

    function isActive(address group) external view returns (bool);

    function getNumberOfGroups() external view returns (uint256);

    function stCeloInGroup(address group) external view returns (uint256);
}
