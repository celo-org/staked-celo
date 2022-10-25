//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./IGovernance.sol";

interface IAccount {
    function getTotalCelo() external view returns (uint256);

    function getCeloForGroup(address) external view returns (uint256);

    function scheduleVotes(address[] calldata group, uint256[] calldata votes) external payable;

    function scheduledVotesForGroup(address group) external returns (uint256);

    function scheduleWithdrawals(
        address beneficiary,
        address[] calldata group,
        uint256[] calldata withdrawals
    ) external;

    function voteProposal(
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) external;
}
