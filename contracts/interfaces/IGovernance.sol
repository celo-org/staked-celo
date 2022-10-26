//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IGovernance {
    function votePartially(
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) external returns (bool);

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
