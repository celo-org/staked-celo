//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../interfaces/IVote.sol";

/**
 * @notice This is a simple mock exposing the Manager-facing Vote API as
 * simple functions that
 * 1. Return currently locked stCelo.
 */
contract MockVote is IVote {
    address public accountVoter;
    uint256 public proposalId;
    uint256 public stakedCeloBalance;
    uint256 public totalYesVotes;
    uint256 public totalNoVotes;
    uint256 public totalAbstainVotes;

    function updateHistoryAndReturnLockedStCeloInVoting(address)
        external
        pure
        override
        returns (uint256)
    {
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

        return (stakedCeloBalance, totalYesVotes, totalNoVotes, totalAbstainVotes);
    }

    function revokeVotes(address _accountVoter, uint256 _proposalId)
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
        return (stakedCeloBalance, totalYesVotes, totalNoVotes, totalAbstainVotes);
    }
}
