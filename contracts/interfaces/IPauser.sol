//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IPauser {
    function pause(address contr) external;

    function unpause(address contr) external;

    function owner() external returns (address);
}
