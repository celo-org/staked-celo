//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IGovernance {
    enum VoteValue {
        None,
        Abstain,
        No,
        Yes
    }

    enum Stage {
        None,
        Queued,
        Approval,
        Referendum,
        Execution,
        Expiration
    }

    function concurrentProposals() external returns (uint256);

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

    function getProposalStage(uint256 proposalId) external view returns (IGovernance.Stage);

    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            string memory
        );
}
