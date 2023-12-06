//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IVote {
    function updateHistoryAndReturnLockedStCeloInVoting(address beneficiary)
        external
        returns (uint256);

    function voteProposal(
        address accountVoter,
        uint256 proposalId,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    )
        external
        returns (
            uint256 stCeloUsedForVoting,
            uint256 totalYesVotes,
            uint256 totalNoVotes,
            uint256 totalAbstainVotes
        );

    function revokeVotes(address accountVoter, uint256 proposalId)
        external
        returns (
            uint256 totalYesVotes,
            uint256 totalNoVotes,
            uint256 totalAbstainVotes
        );
}
