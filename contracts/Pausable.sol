//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

contract Pausable {
    struct PausedRecord {
        bool paused;
    }

    error Paused();

    modifier onlyWhenNotPaused(PausedRecord storage paused) {
        if (paused.paused) {
            revert Paused();
        }

        _;
    }

    function _pause(PausedRecord storage paused) internal {
        paused.paused = true;
    }

    function _unpause(PausedRecord storage paused) internal {
        paused.paused = false;
    }

    /**
     * @notice Returns whether or not the contract is paused.
     * @param paused The PauseRecord to check.
     * @return `true` if the contract is paused, `false` otherwise.
     */
    function _isPaused(PausedRecord storage paused) internal view returns (bool) {
        return paused.paused;
    }
}
