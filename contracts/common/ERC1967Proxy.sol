// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.11;

/**
 * Hardhat only compiles contracts referenced from the contracts folder.
 * We need this Proxy's arttifacts in the deployment scripts.
 * There two ways of achieving this: the empty import (what's happening in
 * this file), or a plugin. The plugin feels a bit overkill.
 */

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
