//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IManager {
    function getLockedStCeloInVoting(address accountAddress) external returns (uint256);
}
