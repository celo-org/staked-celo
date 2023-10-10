//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./common/UUPSOwnableUpgradeable.sol";
import "./interfaces/IPausable.sol";

/**
 * @title The contract that is permissioned to pause StakedCelo protocol
 * contracts.
 * @notice Used to prevent/mitigate damage in case an exploit is found in the
 * StakedCelo protocol.
 * @dev This contract should be owned by the StakedCelo MultiSig, and it should
 * be set as the `pauser` of other protocol contracts inheriting from
 * Pausable.sol, permissioned to call the `pause` and `unpause` functions.
 */
contract Pauser is UUPSOwnableUpgradeable {
    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /**
     * @param _owner The address of the contract owner.
     */
    function initialize(address _owner) external initializer {
        _transferOwnership(_owner);
    }

    function pause(address contr) external onlyOwner {
        IPausable(contr).pause();
    }
}
