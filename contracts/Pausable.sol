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
     * @notice The storage slot under which we store a boolean representing
     * whether or not the contract is currently paused.
     */
    bytes32 public constant PAUSED_POSITION =
        bytes32(uint256(keccak256("staked-celo.pausable.paused")) - 1);
    /**
     * @notice The storage slot under which we store an address representing the
     * address permissioned to pause/unpause this contract.
     */
    bytes32 public constant PAUSER_POSITION =
        bytes32(uint256(keccak256("staked-celo.pausable.pauser")) - 1);

    /**
     * Emitted when this contract is paused.
     */
    event ContractPaused();

    /**
     * Emitted when this contract is unpaused.
     */
    event ContractUnpaused();

    /**
     * @notice Emitted when the address authorized to pause/unpause the contract is
     * changed.
     * @param pauser THe new pauser.
     */
    event PauserSet(address pauser);

    /**
     * @notice Used when an `onlyWhenNotPaused` function is called while the
     * contract is paused.
     */
    error Paused();

    /**
     * @notice Used when an `onlyPauser` function is called with a different
     * address.
     */
    error OnlyPauser();

    /**
     * @notice Reverts if the contract is paused.
     */
    modifier onlyWhenNotPaused() {
        if (isPaused()) {
            revert Paused();
        }

        _;
    }

    /**
     * @notice Reverts if the caller is not the pauser.
     */
    modifier onlyPauser() {
        if (msg.sender != pauser()) {
            revert OnlyPauser();
        }

        _;
    }

    /**
     * @notice Pauses the contract.
     */
    function pause() public onlyPauser {
        _setPaused(true);
        emit ContractPaused();
    }

    /**
     * @notice Unpauses the contract.
     */
    function unpause() public onlyPauser {
        _setPaused(false);
        emit ContractUnpaused();
    }

    /**
     * @notice Returns whether or not the contract is paused.
     * @return `true` if the contract is paused, `false` otherwise.
     */
    function isPaused() public view returns (bool) {
        bool paused;
        bytes32 pausedPosition = PAUSED_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            paused := sload(pausedPosition)
        }
        return paused;
    }

    /**
     * @notice Returns the address permissioned to pause/unpause this contract.
     */
    function pauser() public view returns (address) {
        address pauserAddress;
        bytes32 pauserPosition = PAUSER_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            pauserAddress := sload(pauserPosition)
        }
        return pauserAddress;
    }

    /**
     * @notice Sets the contract's paused state.
     * @param paused `true` for paused, `false` for unpaused.
     */
    function _setPaused(bool paused) internal {
        bytes32 pausedPosition = PAUSED_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(pausedPosition, paused)
        }
    }

    /**
     * @notice Sets the address permissioned to pause this contract.
     * @param _pauser The new pauser.
     * @dev This should be wrapped by the inheriting contract, likely in a
     * permissioned function like `onlyOwner`.
     */
    function _setPauser(address _pauser) internal {
        bytes32 pauserPosition = PAUSER_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(pauserPosition, _pauser)
        }
        emit PauserSet(_pauser);
    }
}
