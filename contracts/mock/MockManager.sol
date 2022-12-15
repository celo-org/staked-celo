//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../interfaces/IManager.sol";

/**
 * @notice This is a simple mock exposing the StCelo-facing Manager API as
 * simple functions that
 * 1. Return currently locked stCelo.
 */
contract MockManager is IManager {
    struct MockTransfer {
        address from;
        address to;
        uint256 amount;
    }

    uint256 private lockedStCelo = 0;
    MockTransfer[] public transfers;

    function setLockedStCelo(uint256 _lockedStCelo) public {
        lockedStCelo = _lockedStCelo;
    }

    function updateHistoryAndReturnLockedStCeloInVoting(address)
        external
        view
        override
        returns (uint256)
    {
        return lockedStCelo;
    }

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external {
        transfers.push(MockTransfer(from, to, amount));
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

    receive() external payable {
        // solhint-disable-previous-line no-empty-blocks
    }
}