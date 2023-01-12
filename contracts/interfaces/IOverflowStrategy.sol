// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IOverflowStrategy {
    function isOverflowStrategy(address strategy) external view returns (bool);
}
