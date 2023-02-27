// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface ISpecificGroupStrategy {
    function generateWithdrawalVoteDistribution(
        address strategy,
        uint256 celoWithdrawalAmount,
        uint256 stCeloWithdrawalAmount
    ) external returns (address[] memory groups, uint256[] memory votes);

    function generateWithdrawalVoteDistributionTransfer(
        address strategy,
        uint256 celoWithdrawalAmount,
        uint256 stCeloWithdrawalAmount
    ) external returns (address[] memory groups, uint256[] memory votes);

    function blockStrategy(address group) external returns (uint256);

    function generateDepositVoteDistribution(
        address strategy,
        uint256 votes,
        uint256 stCeloAmount
    ) external returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function isStrategy(address strategy) external view returns (bool);

    function isBlockedStrategy(address strategy) external view returns (bool);

    function getStCeloInGroup(address strategy)
        external
        view
        returns (uint256 total, uint256 overflow);

    function totalStCeloLocked() external view returns (uint256);

    function totalStCeloOverflow() external view returns (uint256);

    function stCeloInGroup(address strategy) external view returns (uint256);

    function getNumberOfStrategies() external view returns (uint256);
}
