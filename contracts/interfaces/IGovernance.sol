//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IGovernance {
    enum VoteValue {
        None,
        Abstain,
        No,
        Yes
    }

    function votePartially(
        uint256 proposalId,
        uint256 index,
        VoteValue[] calldata voteValues,
        uint256[] calldata weights
    ) external returns (bool);

    function getAmountOfGoldUsedForVoting(address account) external view returns (uint256);

    function vote(
        uint256 proposalId,
        uint256 index,
        VoteValue value
    ) external;
}
