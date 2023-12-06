// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title A contract that links UUPSUUpgradeable with OwanbleUpgradeable to gate upgrades.
 */
abstract contract UUPSOwnableUpgradeable is UUPSUpgradeable, OwnableUpgradeable {
    /**
     * @notice Guard method for UUPS (Universal Upgradable Proxy Standard)
     * See: https://docs.openzeppelin.com/contracts/4.x/api/proxy#transparent-vs-uups
     * @dev This methods overrides the virtual one in UUPSUpgradeable and
     * adds the onlyOwner modifer.
     */
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
