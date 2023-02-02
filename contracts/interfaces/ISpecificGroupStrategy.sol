// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface ISpecificGroupStrategy {
    function calculateAndUpdateForWithdrawal(
        address strategy,
        uint256 celoWitdrawalAmount,
        uint256 stCeloWithdrawalAmount
    ) external returns (address[] memory groups, uint256[] memory votes);

    function calculateAndUpdateForWithdrawalTransfer(
        address strategy,
        uint256 celoWitdrawalAmount,
        uint256 stCeloWithdrawalAmount
    ) external returns (address[] memory groups, uint256[] memory votes);

    function addToSpecificGroupStrategyTotalStCeloVotes(address strategy, uint256 value) external;

    function subtractFromSpecificGroupStrategyTotalStCeloVotes(address strategy, uint256 value)
        external;

    function allowStrategy(address group) external;

    function blockStrategy(address group) external returns (uint256);

    function generateGroupVotesToDistributeTo(
        address strategy,
        uint256 votes,
        uint256 stCeloAmount
    ) external returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function isSpecificGroupStrategy(address strategy) external view returns (bool);

    function isValidSpecificGroupStrategy(address strategy) external view returns (bool);

    function getStCeloInStrategy(address strategy)
        external
        view
        returns (uint256 total, uint256 overflow);

    function getTotalStCeloInSpecificGroupStrategies() external view returns (uint256);

    function getSpecificGroupStrategiesLength() external view returns (uint256);

    function totalStCeloLocked() external view returns (uint256);

    function totalStCeloOverflow() external view returns (uint256);
}
