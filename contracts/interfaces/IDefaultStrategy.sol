// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IDefaultStrategy {
    function generateGroupVotesToDistributeTo(uint256 votes, uint256 stCeloAmount)
        external
        returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function calculateAndUpdateForWithdrawal(uint256 withdrawal)
        external
        returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function activateGroup(address group) external;

    function groupsContain(address group) external view returns (bool);

    function getGroupsLength() external view returns (uint256);

    function getDeprecatedGroupsLength() external view returns (uint256);

    function getTotalStCeloVotesForStrategy(address strategy) external view returns (uint256);

    function getTotalStCeloInDefaultStrategy() external view returns (uint256);
}
