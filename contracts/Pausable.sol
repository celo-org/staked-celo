//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./interfaces/IPausable.sol";

/**
 * @title A helper contract to add pasuing functionality to a contract.
 * @notice Used to prevent/mitigate damage in case an exploit is found in the
 * extending contract.
 */
abstract contract Pausable is IPausable {
    /**
     * @notice Struct wrapping a bool that determines whether the contract
     * should be paused.
     * @dev We can't store the flag in this contract itself, since that would
     * mangle storage of inheriting contracts. Instead, we provide a
     * struct-wrapped bool type, to leverage the typechecker to help ensure the
     * correct value is used.
     */
    struct PausedRecord {
        bool paused;
    }

    /**
     * @notice Used when an `onlyWhenNotPaused` function is called while the
     * contract is paused.
     */
    error Paused();

    /**
     * @notice Reverts if the contract is paused.
     * @param paused The `PausedRecord` struct containing the flag.
     */
    modifier onlyWhenNotPaused(PausedRecord storage paused) {
        if (paused.paused) {
            revert Paused();
        }

        _;
    }

    /**
     * @notice Pauses the contract by setting the wrapped bool to `true`.
     * @param paused The PausedRecord to modify.
     * @dev The implementing contract should likely wrap this function in a
     * permissioned (e.g. `onlyOwner`) `pause()` function.
     */
    function _pause(PausedRecord storage paused) internal {
        paused.paused = true;
    }

    /**
     * @notice Unpauses the contract by setting the wrapped bool to `false`.
     * @param paused The PausedRecord to modify.
     * @dev The implementing contract should likely wrap this function in a
     * permissioned (e.g. `onlyOwner`) `unpause()` function.
     */
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
