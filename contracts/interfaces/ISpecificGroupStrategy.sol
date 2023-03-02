// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface ISpecificGroupStrategy {
    function generateDepositVoteDistribution(
        address group,
        uint256 votes,
        uint256 stCeloAmount
    ) external returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function generateWithdrawalVoteDistribution(
        address group,
        uint256 celoWithdrawalAmount,
        uint256 stCeloWithdrawalAmount,
        bool isTransfer
    ) external returns (address[] memory groups, uint256[] memory votes);

    function isVotedGroup(address group) external view returns (bool);

    function isBlockedGroup(address group) external view returns (bool);

    function getStCeloInGroup(address group)
        external
        view
        returns (
            uint256 total,
            uint256 overflow,
            uint256 unhealthy
        );

    function totalStCeloLocked() external view returns (uint256);

    function totalStCeloOverflow() external view returns (uint256);

    function getNumberOfVotedGroups() external view returns (uint256);
}
