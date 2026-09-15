// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./MultiSigTestBase.sol";

/**
 * @notice Port of the view-function blocks of `describe("MultiSig")`: `#getOwners()`,
 *         `#getConfirmations()`, `#isFullyConfirmed()`, `#isConfirmedBy()` and
 *         `#isProposalTimelockReached()`.
 */
contract MultiSigGettersTest is MultiSigTestBase {
    // =========================================================================
    //                       #getOwners (1)
    // =========================================================================

    function test_GetOwners_ReturnsOwners() public {
        address[] memory currentOwners = msig.getOwners();
        assertEq(currentOwners.length, owners.length);
        assertEq(currentOwners[0], owners[0]);
        assertEq(currentOwners[1], owners[1]);
    }

    // =========================================================================
    //                    #getConfirmations (1)
    // =========================================================================

    function test_GetConfirmations_ReturnsConfirmations() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(
            owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData)
        );

        address[] memory confirmations = msig.getConfirmations(pid);
        assertEq(confirmations.length, 1);
        assertEq(confirmations[0], owner1);
    }

    // =========================================================================
    //                   #isFullyConfirmed (2)
    // =========================================================================

    function test_IsFullyConfirmed_ReturnsTrueWhenFullyConfirmed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(
            owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData)
        );

        vm.prank(owner2);
        msig.confirmProposal(pid);
        assertTrue(msig.isFullyConfirmed(pid));
    }

    function test_IsFullyConfirmed_ReturnsFalseWhenNotFullyConfirmed() public {
        // proposalId 0 doesn't exist yet, isFullyConfirmed returns false
        assertFalse(msig.isFullyConfirmed(0));
    }

    // =========================================================================
    //                    #isConfirmedBy (2)
    // =========================================================================

    function test_IsConfirmedBy_ReturnsTrueWhenConfirmed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(
            owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData)
        );
        assertTrue(msig.isConfirmedBy(pid, owner1));
    }

    function test_IsConfirmedBy_ReturnsFalseWhenNotConfirmed() public {
        // proposalId 0, owner1 - no proposals submitted yet
        assertFalse(msig.isConfirmedBy(0, owner1));
    }

    // =========================================================================
    //              #isProposalTimelockReached (4)
    // =========================================================================

    function test_IsProposalTimelockReached_ReturnsTrueWhenReached() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(
            owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData)
        );

        vm.prank(owner2);
        msig.confirmProposal(pid);
        vm.warp(block.timestamp + delay + 1);
        assertTrue(msig.isProposalTimelockReached(pid));
    }

    function test_IsProposalTimelockReached_ReturnsFalseForUnscheduled() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(
            owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData)
        );
        assertFalse(msig.isProposalTimelockReached(pid));
    }

    function test_IsProposalTimelockReached_ReturnsFalseForUnscheduledAfterDelay() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(
            owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData)
        );

        vm.warp(block.timestamp + delay + 1);
        assertFalse(msig.isProposalTimelockReached(pid));
    }

    function test_IsProposalTimelockReached_ReturnsFalseWhenTimelockNotElapsed() public {
        bytes memory txData = _addOwnerPayload(nonOwner);
        uint256 pid = _submitProposal(
            owner1, _singleAddress(address(multiSig)), _singleUint(0), _singleBytes(txData)
        );

        vm.prank(owner2);
        msig.confirmProposal(pid);
        // Don't warp - timelock not elapsed
        assertFalse(msig.isProposalTimelockReached(pid));
    }
}
