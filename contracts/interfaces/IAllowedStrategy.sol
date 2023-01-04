// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IAllowedStrategy {
    function withdrawFromAllowedStrategy(
        address strategy,
        uint256 withdrawal,
        uint256 stCeloWithdrawalAmount
    ) external returns (address[] memory groups, uint256[] memory votes);

    function isAllowedStrategy(address strategy) external view returns (bool);

    function getTotalStCeloVotesForStrategy(address strategy) external view returns (uint256);

    function getTotalStCeloInAllowedStrategies() external view returns (uint256);

    function getAllowedStrategiesLength() external view returns (uint256);

    function addToTotalStCeloInAllowedStrategies(uint256 value) external;

    function subtractFromTotalStCeloInAllowedStrategies(uint256 value) external;

    function addToAllowedStrategyTotalStCeloVotes(address strategy, uint256 value) external;

    function subtractFromAllowedStrategyTotalStCeloVotes(address strategy, uint256 value) external;

    function allowStrategy(address group) external;

    function blockStrategy(address group) external returns (uint256);
}
