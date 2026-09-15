// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./MultiSigTestBase.sol";
import "../../contracts/test/ProposalTester.sol";

/// @notice Port of `describe("MultiSig") > describe("#governanceProposeAndExecute()")`.
contract MultiSigGovernanceTest is MultiSigTestBase {
    // =========================================================================
    //              #governanceProposeAndExecute (8)
    // =========================================================================

    function test_GovernanceProposeAndExecute_SucceedsForGovernance() public {
        address[] memory emptyDests = new address[](0);
        uint256[] memory emptyVals = new uint256[](0);
        bytes[] memory emptyPayloads = new bytes[](0);

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(emptyDests, emptyVals, emptyPayloads);
    }

    function test_GovernanceProposeAndExecute_AllowsGovernanceToCallContract() public {
        ProposalTester proposalTester = new ProposalTester();
        bytes memory txData = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(42));

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(
            _singleAddress(address(proposalTester)),
            _singleUint(0),
            _singleBytes(txData)
        );

        (address caller, uint256 value, uint256 arg) = proposalTester.getCall(0);
        assertEq(caller, address(multiSig));
        assertEq(value, 0);
        assertEq(arg, 42);
    }

    function test_GovernanceProposeAndExecute_AllowsGovernanceToSendValue() public {
        ProposalTester proposalTester = new ProposalTester();

        // Fund multiSig with 300 wei
        vm.deal(owner1, 300);
        vm.prank(owner1);
        (bool ok,) = address(multiSig).call{value: 300}("");
        assertTrue(ok);

        bytes memory txData = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(42));

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(
            _singleAddress(address(proposalTester)),
            _singleUint(100),
            _singleBytes(txData)
        );

        assertEq(address(multiSig).balance, 200);
        assertEq(address(proposalTester).balance, 100);

        (address caller, uint256 value, uint256 arg) = proposalTester.getCall(0);
        assertEq(caller, address(multiSig));
        assertEq(value, 100);
        assertEq(arg, 42);
    }

    function test_GovernanceProposeAndExecute_AllowsGovernanceToCallMultipleFunctions() public {
        ProposalTester proposalTester = new ProposalTester();
        bytes memory txData1 = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(42));
        bytes memory txData2 = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(1337));

        address[] memory dests = new address[](2);
        dests[0] = address(proposalTester);
        dests[1] = address(proposalTester);
        uint256[] memory vals = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = txData1;
        payloads[1] = txData2;

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(dests, vals, payloads);

        (address caller1, uint256 val1, uint256 arg1) = proposalTester.getCall(0);
        (address caller2, uint256 val2, uint256 arg2) = proposalTester.getCall(1);
        assertEq(caller1, address(multiSig));
        assertEq(val1, 0);
        assertEq(arg1, 42);
        assertEq(caller2, address(multiSig));
        assertEq(val2, 0);
        assertEq(arg2, 1337);
    }

    function test_GovernanceProposeAndExecute_AllowsGovernanceToExecuteMultiSigFunction() public {
        bytes memory txData = _addOwnerPayload(nonOwner);

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );

        assertTrue(msig.isOwner(nonOwner));
    }

    function test_GovernanceProposeAndExecute_EmitsGovernanceTransactionExecutedEvent() public {
        ProposalTester proposalTester = new ProposalTester();
        bytes memory txData = abi.encodeWithSelector(ProposalTester.testCall.selector, uint256(42));

        vm.expectEmit(false, false, false, true, address(multiSig));
        emit GovernanceTransactionExecuted(0, hex"");

        vm.prank(address(mockGovernance));
        msig.governanceProposeAndExecute(
            _singleAddress(address(proposalTester)),
            _singleUint(0),
            _singleBytes(txData)
        );
    }

    function test_GovernanceProposeAndExecute_RevertsForOwner() public {
        address[] memory emptyDests = new address[](0);
        uint256[] memory emptyVals = new uint256[](0);
        bytes[] memory emptyPayloads = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, owner1));
        vm.prank(owner1);
        msig.governanceProposeAndExecute(emptyDests, emptyVals, emptyPayloads);
    }

    function test_GovernanceProposeAndExecute_RevertsForRandomAddress() public {
        address[] memory emptyDests = new address[](0);
        uint256[] memory emptyVals = new uint256[](0);
        bytes[] memory emptyPayloads = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, nonOwner));
        vm.prank(nonOwner);
        msig.governanceProposeAndExecute(emptyDests, emptyVals, emptyPayloads);
    }
}
