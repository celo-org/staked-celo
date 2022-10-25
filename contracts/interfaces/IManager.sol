//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./IGovernance.sol";

interface IManager {
    function getLockedStCeloInVoting(address accountAddress) external returns (uint256);

    function voteProposal(
        uint256 proposalId,
        IGovernance.VoteValue[] memory voteValues,
        uint256[] memory weights
    )
        external
        returns (
            uint256,
            IGovernance.VoteValue[] memory,
            uint256[] memory
        );

    function revokeVotes(uint256 proposalId, uint256 index) external;
}
