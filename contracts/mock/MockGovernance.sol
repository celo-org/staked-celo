//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../interfaces/IGovernance.sol";

/**
 * @notice This is a simple mock exposing the Account-facing Governance API as
 * simple functions that
 */
contract MockGovernance is IGovernance {
    uint256 public proposalId;
    uint256 public index;
    uint256 public yesVotes;
    uint256 public noVotes;
    uint256 public abstainVotes;

    function votePartially(
        uint256 _proposalId,
        uint256 _index,
        uint256 _yesVotes,
        uint256 _noVotes,
        uint256 _abstainVotes
    ) external override returns (bool) {
        proposalId = _proposalId;
        index = _index;
        yesVotes = _yesVotes;
        noVotes = _noVotes;
        abstainVotes = _abstainVotes;

        return true;
    }

    function getProposal(uint256 _proposalId)
        external
        view
        override
        returns (
            address,
            uint256,
            uint256,
            uint256,
            string memory
        )
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getReferendumStageDuration() external pure returns (uint256) {
        return 11;
    }
}
