//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IAccount {
    function getTotalCelo() external view returns (uint256);

    function getCeloForGroup(address) external view returns (uint256);

    function scheduleVotes(address[] calldata group, uint256[] calldata votes) external payable;

    function scheduledVotes(address group) external returns (uint256);

    function scheduleWithdrawals(
        address[] calldata group,
        uint256[] calldata withdrawals,
        address beneficiary
    ) external;
}