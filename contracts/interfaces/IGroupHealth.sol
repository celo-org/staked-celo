// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IGroupHealth {
    function isGroupValid(address group) external view returns (bool);
}
