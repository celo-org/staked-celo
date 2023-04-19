//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IAccount {
    function scheduleVotes(address[] calldata group, uint256[] calldata votes) external payable;

    function scheduleTransfer(
        address[] calldata fromGroups,
        uint256[] calldata fromVotes,
        address[] calldata toGroups,
        uint256[] calldata toVotess
    ) external;

    function scheduleWithdrawals(
        address beneficiary,
        address[] calldata group,
        uint256[] calldata withdrawals
    ) external;

    function votePartially(
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) external;

    function getTotalCelo() external view returns (uint256);

    function getCeloForGroup(address) external view returns (uint256);

    function scheduledVotesForGroup(address group) external view returns (uint256);

    function scheduledRevokeForGroup(address group) external view returns (uint256);

    function scheduledWithdrawalsForGroup(address group) external view returns (uint256);
}
