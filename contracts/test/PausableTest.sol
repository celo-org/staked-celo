//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../Pausable.sol";

contract PausableTest is Pausable {
    PausedRecord paused;
    uint256 public numberCalls;

    function callPausable() external onlyWhenNotPaused(paused) {
        numberCalls++;
    }

    function callAlways() external {
        numberCalls++;
    }

    function pause() external {
        _pause(paused);
    }

    function unpause() external {
        _unpause(paused);
    }

    function isPaused() external view returns (bool) {
        return _isPaused(paused);
    }
}
