//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../Pausable.sol";

contract PausableTest is Pausable {
    uint256 public numberCalls;

    function callPausable() external onlyWhenNotPaused {
        numberCalls++;
    }

    function callAlways() external {
        numberCalls++;
    }

    function setPauser(address _pauser) external {
        _setPauser(_pauser);
    }
}
