// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Used via inheritance to grant special access control to the Manager
 * contract.
 */
abstract contract Managed is Initializable, OwnableUpgradeable {
    address public manager;

    /**
     * @notice Emitted when the manager is initially set or later modified.
     * @param manager The new managing account address.
     */
    event ManagerSet(address indexed manager);

    /**
     *  @notice Used when an `onlyManager` function is called by a non-manager.
     *  @param caller `msg.sender` that called the function.
     */
    error CallerNotManager(address caller);

    /**
     * @notice Used when a passed address is address(0).
     */
    error NullAddress();

    /**
     * @dev Throws if called by any account other than the manager.
     */
    modifier onlyManager() {
        if (manager != msg.sender) {
            revert CallerNotManager(msg.sender);
        }
        _;
    }

    /**
     * @notice Sets the manager address.
     * @param _manager The new manager address.
     */
    function setManager(address _manager) external onlyOwner {
        _setManager(_manager);
    }

    /**
     * @dev Initializes the contract in an upgradable context.
     * @param _manager The initial managing address.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __Managed_init(address _manager) internal onlyInitializing {
        _setManager(_manager);
    }

    /**
     * @notice Sets the manager address.
     * @param _manager The new manager address.
     */
    function _setManager(address _manager) internal {
        if (_manager == address(0)) {
            revert NullAddress();
        }
        manager = _manager;
        emit ManagerSet(_manager);
    }
}
