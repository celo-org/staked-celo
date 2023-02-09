// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface ISpecificGroupStrategy {
    function calculateAndUpdateForWithdrawal(
        address strategy,
        uint256 withdrawal,
        uint256 stCeloWithdrawalAmount
    ) external returns (address[] memory groups, uint256[] memory votes);

    function calculateAndUpdateForWithdrawalTransfer(
        address strategy,
        uint256 withdrawal,
        uint256 stCeloWithdrawalAmount
    ) external returns (address[] memory groups, uint256[] memory votes);

    function blockStrategy(address group) external returns (uint256);

    function generateGroupVotesToDistributeTo(
        address strategy,
        uint256 votes,
        uint256 stCeloAmount
    ) external returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function isStrategy(address strategy) external view returns (bool);

    function isBlockedStrategy(address strategy) external view returns (bool);

    function stCeloInGroup(address strategy) external view returns (uint256);

    function getNumberOfStrategies() external view returns (uint256);
}
