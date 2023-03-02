//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../interfaces/IManager.sol";

/**
 * @notice This is a simple mock exposing the stCelo-facing Manager API as
 * simple functions that
 * 1. Return currently locked stCELO.
 */
contract MockManager is IManager {
    struct MockTransfer {
        address from;
        address to;
        uint256 amount;
    }

    uint256 private lockedStCelo = 0;
    MockTransfer[] public transfers;

    receive() external payable {
        // solhint-disable-previous-line no-empty-blocks
    }

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external {
        transfers.push(MockTransfer(from, to, amount));
    }

    function scheduleTransferWithinStrategy(
        address[] calldata fromGroups,
        address[] calldata toGroups,
        uint256[] calldata fromVotes,
        uint256[] calldata toVotes
    ) external {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getReceivableVotesForGroup(address group) external view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function updateHistoryAndReturnLockedStCeloInVoting(address)
        external
        view
        override
        returns (uint256)
    {
        return lockedStCelo;
    }

    function toCelo(uint256 stCeloAmount) external view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function setLockedStCelo(uint256 _lockedStCelo) public {
        lockedStCelo = _lockedStCelo;
    }

    function transferLength() public view returns (uint256) {
        return transfers.length;
    }

    function getTransfer(uint256 index)
        public
        view
        returns (
            address,
            address,
            uint256
        )
    {
        return (transfers[index].from, transfers[index].to, transfers[index].amount);
    }

    function toStakedCelo(uint256 celoAmount) public view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
