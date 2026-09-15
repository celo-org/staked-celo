// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./MultiSigTestBase.sol";

/**
 * @notice Port of the proposal lifecycle blocks of `describe("MultiSig")`:
 *         `#submitProposal()`, `#confirmProposal()`, `#scheduleProposal()`,
 *         `#executeProposal()` and `#revokeConfirmation()`.
 */
contract MultiSigProposalTest is MultiSigTestBase {
    // =========================================================================
    //                    #submitProposal (8)
    // =========================================================================

    function test_SubmitProposal_AllowsOwnerToSubmit() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 proposalId = _submitProposal(
            owner1,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );

        (address[] memory destinations,,) = msig.getProposal(proposalId);
        assertEq(destinations.length, 1);
        assertEq(destinations[0], address(multiSig));
    }

    function test_SubmitProposal_SetsProposalAsConfirmedBySender() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 proposalId = _submitProposal(
            owner1,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );
        assertTrue(msig.isConfirmedBy(proposalId, owner1));
    }

    function test_SubmitProposal_UpdatesProposalCount() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        _submitProposal(
            owner1,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );
        assertEq(msig.proposalCount(), 1);
    }

    function test_SubmitProposal_DoesNotAllowSubmitToNullAddress() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        // The original submitted from the default (non-owner) signer; the revert is the same
        // either way because the `notNull` destination check runs before `ownerExists`.
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.AddressZeroNotAllowed.selector));
        vm.prank(owner1);
        msig.submitProposal(
            _singleAddress(ADDRESS_ZERO),
            _singleUint(0),
            _singleBytes(txData)
        );
    }

    function test_SubmitProposal_DoesNotAllowNonOwnerToSubmit() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.OwnerDoesNotExist.selector, nonOwner));
        vm.prank(nonOwner);
        msig.submitProposal(
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData)
        );
    }

    function test_SubmitProposal_FailsWhenDestinationsDoesNotMatchValues() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256[] memory vals = new uint256[](2);
        vals[0] = 0;
        vals[1] = 1;
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ParamLengthsMismatch.selector));
        vm.prank(owner1);
        msig.submitProposal(
            _singleAddress(address(multiSig)),
            vals,
            _singleBytes(txData)
        );
    }

    function test_SubmitProposal_FailsWhenDestinationsDoesNotMatchPayloads() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = txData;
        payloads[1] = txData;
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ParamLengthsMismatch.selector));
        vm.prank(owner1);
        msig.submitProposal(
            _singleAddress(address(multiSig)),
            _singleUint(0),
            payloads
        );
    }

    function test_SubmitProposal_AllowsMultipleTransactions() public {
        bytes memory txData1 = _addOwnerPayload(nonOwner);
        bytes memory txData2 = abi.encodeWithSelector(IMultiSigFull.changeDelay.selector, 9 * DAY);

        address[] memory dests = new address[](2);
        dests[0] = address(multiSig);
        dests[1] = address(multiSig);
        uint256[] memory vals = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = txData1;
        payloads[1] = txData2;

        uint256 proposalId = _submitProposal(owner1, dests, vals, payloads);

        (address[] memory retDests,,) = msig.getProposal(proposalId);
        assertEq(retDests.length, 2);
    }

    // =========================================================================
    //                    #confirmProposal (5)
    // =========================================================================

    function test_ConfirmProposal_AllowsOwnerToConfirm() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        assertTrue(msig.isConfirmedBy(pid, owner2));
    }

    function test_ConfirmProposal_SchedulesOnceEnoughConfirmations() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        assertTrue(msig.isScheduled(pid));
    }

    function test_ConfirmProposal_StoresCorrectTimestamp() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);

        uint256 expectedTimestamp = block.timestamp + msig.delay();
        assertEq(msig.getTimestamp(pid), expectedTimestamp);
    }

    function test_ConfirmProposal_DoesNotAllowOwnerToConfirmTwice() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalAlreadyConfirmed.selector, uint256(0), owner1));
        vm.prank(owner1);
        msig.confirmProposal(pid);
    }

    function test_ConfirmProposal_DoesNotAllowNonOwnerToConfirm() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.OwnerDoesNotExist.selector, nonOwner));
        vm.prank(nonOwner);
        msig.confirmProposal(pid);
    }

    // =========================================================================
    //                    #scheduleProposal (2)
    // =========================================================================

    function test_ScheduleProposal_CannotScheduleTwice() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid); // auto-schedules

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalAlreadyScheduled.selector, uint256(0)));
        vm.prank(owner1);
        msig.scheduleProposal(pid);
    }

    function test_ScheduleProposal_CannotScheduleNotFullyConfirmed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalNotFullyConfirmed.selector, uint256(0)));
        vm.prank(owner1);
        msig.scheduleProposal(pid);
    }

    // =========================================================================
    //                    #executeProposal (6)
    // =========================================================================

    function test_ExecuteProposal_OwnerCanExecuteAfterTimelock() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);
        vm.prank(owner2);
        msig.executeProposal(pid);
        assertEq(msig.getTimestamp(pid), 1);
    }

    function test_ExecuteProposal_AnyAccountCanExecuteAfterTimelock() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        (address randomAcc,) = randomSigner(100 ether);
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);
        vm.prank(randomAcc);
        msig.executeProposal(pid);
        assertEq(msig.getTimestamp(pid), 1);
    }

    function test_ExecuteProposal_FailsToExecuteTwice() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);
        vm.prank(owner2);
        msig.executeProposal(pid);

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalNotScheduled.selector, uint256(0)));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_ExecuteProposal_FailsWhenTimelockNotPassed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner2);
        msig.confirmProposal(pid);

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalTimelockNotReached.selector, uint256(0)));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_ExecuteProposal_FailsWhenNotScheduled() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.warp(block.timestamp + delay + 1);
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalNotScheduled.selector, uint256(0)));
        vm.prank(owner1);
        msig.executeProposal(pid);
    }

    function test_ExecuteProposal_ExecutesManyTransactions() public {
        bytes memory txData1 = _addOwnerPayload(nonOwner);
        bytes memory txData2 = abi.encodeWithSelector(IMultiSigFull.changeDelay.selector, 9 * DAY);

        address[] memory dests = new address[](2);
        dests[0] = address(multiSig);
        dests[1] = address(multiSig);
        uint256[] memory vals = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = txData1;
        payloads[1] = txData2;

        _executeMultisigProposal(msig, dests, vals, payloads, delay, owner1, owner2);

        assertEq(msig.delay(), 9 * DAY);
        assertTrue(msig.isOwner(nonOwner));
    }

    // =========================================================================
    //                    #revokeConfirmation (3)
    // =========================================================================

    function test_RevokeConfirmation_AllowsOwnerToRevoke() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.prank(owner1);
        msig.revokeConfirmation(pid);
        assertFalse(msig.isConfirmedBy(pid, owner1));
    }

    function test_RevokeConfirmation_DoesNotAllowNonOwnerToRevoke() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.OwnerDoesNotExist.selector, nonOwner));
        vm.prank(nonOwner);
        msig.revokeConfirmation(pid);
    }

    function test_RevokeConfirmation_DoesNotAllowOwnerToRevokeBeforeConfirming() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.ProposalNotConfirmed.selector, uint256(0), owner2));
        vm.prank(owner2);
        msig.revokeConfirmation(pid);
    }
}
