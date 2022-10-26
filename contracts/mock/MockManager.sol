//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../interfaces/IManager.sol";

/**
 * @notice This is a simple mock exposing the StCelo-facing Manager API as
 * simple functions that
 * 1. Return currently locked stCelo.
 */
contract MockManager is IManager {
    uint256 private lockedStCelo = 0;

    function setLockedStCelo(uint256 _lockedStCelo) public {
        lockedStCelo = _lockedStCelo;
    }

    function getLockedStCeloInVotingAndUpdateHistory(address)
        external
        view
        override
        returns (uint256)
    {
        return lockedStCelo;
    }

    receive() external payable {
        // solhint-disable-previous-line no-empty-blocks
    }
}
