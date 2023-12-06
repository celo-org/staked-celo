//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IManager {
    function updateHistoryAndReturnLockedStCeloInVoting(address beneficiary)
        external
        returns (uint256);

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external;

    function scheduleTransferWithinStrategy(
        address[] calldata fromGroups,
        address[] calldata toGroups,
        uint256[] calldata fromVotes,
        uint256[] calldata toVotes
    ) external;

    function toCelo(uint256 stCeloAmount) external view returns (uint256);

    function toStakedCelo(uint256 celoAmount) external view returns (uint256);

    function getReceivableVotesForGroup(address group) external view returns (uint256);
}
