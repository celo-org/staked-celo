//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../interfaces/IVote.sol";

/**
 * @notice This is a simple mock exposing the Manager-facing Vote API as
 * simple functions that
 * 1. Return currently locked stCELO.
 */
contract MockVote is IVote {
    address public accountVoter;
    uint256 public proposalId;
    uint256 public totalYesVotes;
    uint256 public totalNoVotes;
    uint256 public totalAbstainVotes;

    address public revokeAccountVoter;
    uint256 public revokeProposalId;

    address public updatedHistoryFor;

    function updateHistoryAndReturnLockedStCeloInVoting(address beneficiary)
        external
        override
        returns (uint256)
    {
        updatedHistoryFor = beneficiary;
        return 111;
    }

    function voteProposal(
        address _accountVoter,
        uint256 _proposalId,
        uint256 _yesVotes,
        uint256 _noVotes,
        uint256 _abstainVotes
    )
        external
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        accountVoter = _accountVoter;
        proposalId = _proposalId;
        totalYesVotes = _yesVotes;
        totalNoVotes = _noVotes;
        totalAbstainVotes = _abstainVotes;

        return (
            _yesVotes + _noVotes + _abstainVotes,
            totalYesVotes,
            totalNoVotes,
            totalAbstainVotes
        );
    }

    function revokeVotes(address _accountVoter, uint256 _proposalId)
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        revokeAccountVoter = _accountVoter;
        revokeProposalId = _proposalId;
        return (totalYesVotes, totalNoVotes, totalAbstainVotes);
    }

    function setVotes(
        uint256 yes,
        uint256 no,
        uint256 abstain
    ) public {
        totalYesVotes = yes;
        totalNoVotes = no;
        totalAbstainVotes = abstain;
    }
}
