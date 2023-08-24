//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

contract ProposalTester {
    struct Call {
        address caller;
        uint256 value;
        uint256 argument;
    }

    Call[] calls;

    error CallDoesNotExist(uint256 i);

    function testCall(uint256 x) public payable {
        Call memory newCall = Call(msg.sender, msg.value, x);
        calls.push(newCall);
    }

    function numberCalls() external view returns (uint256) {
        return calls.length;
    }

    function getCall(uint256 i)
        external
        view
        returns (
            address,
            uint256,
            uint256
        )
    {
        if (i >= calls.length) {
            revert CallDoesNotExist(i);
        }

        Call memory call = calls[i];
        return (call.caller, call.value, call.argument);
    }
}
