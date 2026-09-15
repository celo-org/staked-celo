// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./MultiSigTestBase.sol";

/**
 * @notice Port of the wallet-configuration blocks of `describe("MultiSig")`:
 *         `#addOwner()`, `#removeOwner()`, `#replaceOwner()`, `#changeRequirement()`
 *         and `#changeDelay()`.
 */
contract MultiSigOwnerManagementTest is MultiSigTestBase {
    // =========================================================================
    //                       #addOwner (4)
    // =========================================================================

    function test_AddOwner_AllowsNewOwnerViaMultiSig() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertTrue(msig.isOwner(nonOwner));

        address[] memory currentOwners = msig.getOwners();
        assertEq(currentOwners.length, 3);
        assertEq(currentOwners[0], owner1);
        assertEq(currentOwners[1], owner2);
        assertEq(currentOwners[2], nonOwner);
    }

    function test_AddOwner_DoesNotAllowExternalAccountToAdd() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.addOwner(nonOwner);
    }

    function test_AddOwner_DoesNotAllowAddingNullAddress() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.addOwner.selector, ADDRESS_ZERO);

        // Submit, confirm, warp
        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_AddOwner_FailsWhenMaxOwnersReached() public {
        // Already 2 owners. MAX_OWNER_COUNT = 50. Need 48 more to reach 50.
        uint256 count = 48;
        address[] memory dests = new address[](count);
        uint256[] memory vals = new uint256[](count);
        bytes[] memory payloads = new bytes[](count);

        for (uint256 i = 0; i < count; i++) {
            (address newOwner,) = randomSigner(100 ether);
            dests[i] = address(multiSig);
            payloads[i] = _addOwnerPayload(newOwner);
        }

        _executeMultisigProposal(msig, dests, vals, payloads, delay, owner1, owner2);

        // Now try to add one more (51st owner)
        (address oneMore,) = randomSigner(100 ether);
        bytes memory payload = _addOwnerPayload(oneMore);

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(payload));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    // =========================================================================
    //                      #removeOwner (4)
    // =========================================================================

    function test_RemoveOwner_AllowsOwnerToBeRemoved() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.removeOwner.selector, owner2);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertFalse(msig.isOwner(owner2));
    }

    function test_RemoveOwner_ReducesRequiredIfEqualToOwners() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.removeOwner.selector, owner2);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.required(), 1);
    }

    function test_RemoveOwner_DoesNotAllowExternalAccountToRemove() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.removeOwner(owner2);
    }

    function test_RemoveOwner_CannotRemoveLastOwner() public {
        // First remove owner2
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.removeOwner.selector, owner2);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );

        // Now try to remove owner1 (last owner), required is now 1
        bytes memory txData2 = abi.encodeWithSelector(IMultiSigFull.removeOwner.selector, owner1);

        // With required=1, submitProposal auto-confirms and auto-schedules
        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData2));
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner1);
        msig.executeProposal(pid);
    }

    // =========================================================================
    //                     #replaceOwner (4)
    // =========================================================================

    function test_ReplaceOwner_AllowsOwnerToBeReplaced() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.replaceOwner.selector, owner2, nonOwner);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );

        assertTrue(msig.isOwner(nonOwner));
        assertFalse(msig.isOwner(owner2));

        address[] memory currentOwners = msig.getOwners();
        assertEq(currentOwners.length, 2);
        assertEq(currentOwners[0], owner1);
        assertEq(currentOwners[1], nonOwner);
    }

    function test_ReplaceOwner_DoesNotAllowExternalAccountToReplace() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.replaceOwner(owner2, nonOwner);
    }

    function test_ReplaceOwner_DoesNotAllowReplacingWithNullAddress() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.replaceOwner.selector, owner2, ADDRESS_ZERO);

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_ReplaceOwner_DoesNotAllowReplacingWithExistingOwner() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.replaceOwner.selector, owner1, owner2);

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    // =========================================================================
    //                   #changeRequirement (3)
    // =========================================================================

    function test_ChangeRequirement_AllowsChangeViaMultiSig() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.changeRequirement.selector, uint256(1));
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.required(), 1);
    }

    function test_ChangeRequirement_DoesNotAllowExternalAccountToChange() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.changeRequirement(3);
    }

    function test_ChangeRequirement_FailsIfRequiredMoreThanOwners() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.changeRequirement.selector, uint256(5));

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    // =========================================================================
    //                      #changeDelay (3)
    // =========================================================================

    function test_ChangeDelay_AllowsChangeViaMultiSig() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.changeDelay.selector, 4 * DAY);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.delay(), 4 * DAY);
    }

    function test_ChangeDelay_FailsToChangeBelowMinDelay() public {
        bytes memory txData = abi.encodeWithSelector(IMultiSigFull.changeDelay.selector, 1 * DAY);

        vm.prank(owner1);
        uint256 pid = msig.submitProposal(_singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData));
        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);

        vm.expectRevert(abi.encodeWithSelector(IExternalCallErrors.ExecutionFailed.selector));
        vm.prank(owner2);
        msig.executeProposal(pid);
    }

    function test_ChangeDelay_DoesNotAllowExternalAccountToChange() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner));
        vm.prank(nonOwner);
        msig.changeDelay(4 * DAY);
    }
}
