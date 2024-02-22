//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

/**
 * @title Provides some common general errors.
 */
abstract contract Errors {
    /**
     * @notice Used when attempting to pass in address zero where not allowed.
     */
    error AddressZeroNotAllowed();
}
