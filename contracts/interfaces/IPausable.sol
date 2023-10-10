//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IPausable {
    function pause() external;
    function unpause() external;
}
