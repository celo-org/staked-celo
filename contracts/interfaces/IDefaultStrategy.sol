// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IDefaultStrategy {
    function generateDepositVoteDistribution(uint256 celoAmount, address depositGroupToIgnore)
        external
        returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function generateWithdrawalVoteDistribution(uint256 celoAmount)
        external
        returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function activateGroup(address group) external;

    function isActive(address group) external view returns (bool);

    function getNumberOfGroups() external view returns (uint256);

    function stCeloInGroup(address group) external view returns (uint256);
}
