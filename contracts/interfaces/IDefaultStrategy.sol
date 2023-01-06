// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IDefaultStrategy {
    function generateGroupVotesToDistributeTo(uint256 votes)
        external
        returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function calculateAndUpdateForWithdrawal(uint256 withdrawal)
        external
        returns (address[] memory finalGroups, uint256[] memory finalVotes);

    function activateGroup(address group) external;
}
