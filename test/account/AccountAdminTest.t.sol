// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/**
 * @notice Port of the `describe("Account")` cases that are not scoped to one Account entry
 *         point: the top-level account creation check plus `#setPauser`, `#renounceOwnership`,
 *         `#pause`, `#unpause` and the `when paused` block.
 */
contract AccountAdminTest is AccountTestBase {
    // =========================================================================
    //                            TOP-LEVEL CASE
    // =========================================================================

    function test_ShouldCreateAnAccountOnTheCoreAccountsContract() public view {
        assertTrue(celoAccounts.isAccount(address(account)));
    }

    // =========================================================================
    //                              #setPauser
    // =========================================================================

    function test_setPauser_SetsThePauserAddressToTheOwnerOfTheContract() public {
        vm.prank(owner);
        account.setPauser();
        assertEq(account.pauser(), owner);
    }

    function test_setPauser_EmitsAPauserSetEvent() public {
        vm.expectEmit(true, true, true, true);
        emit PauserSet(owner);
        vm.prank(owner);
        account.setPauser();
    }

    function test_setPauser_CannotBeCalledByANonOwner() public {
        vm.prank(nonManager);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        account.setPauser();
    }

    function test_setPauser_WhenTheOwnerIsChanged_SetsThePauserToTheNewOwner() public {
        vm.prank(owner);
        account.transferOwnership(nonManager);

        vm.prank(nonManager);
        account.setPauser();
        assertEq(account.pauser(), nonManager);
    }

    // =========================================================================
    //                          #renounceOwnership
    // =========================================================================

    function test_renounceOwnership_RevertsWithRenounceOwnershipDisabled() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Managed.RenounceOwnershipDisabled.selector));
        account.renounceOwnership();
    }

    function test_renounceOwnership_RevertsForAnyCaller() public {
        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Managed.RenounceOwnershipDisabled.selector));
        account.renounceOwnership();
    }

    // =========================================================================
    //                               #pause
    // =========================================================================

    function test_pause_CanBeCalledByThePauser() public {
        vm.prank(pauser);
        account.pause();
        assertTrue(account.isPaused());
    }

    function test_pause_EmitsAContractPausedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ContractPaused();
        vm.prank(pauser);
        account.pause();
    }

    function test_pause_CannotBeCalledByARandomAccount() public {
        vm.prank(beneficiary);
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        account.pause();
        assertFalse(account.isPaused());
    }

    // =========================================================================
    //                              #unpause
    // =========================================================================

    function _pause() private {
        vm.prank(pauser);
        account.pause();
    }

    function test_unpause_CanBeCalledByThePauser() public {
        _pause();
        vm.prank(pauser);
        account.unpause();
        assertFalse(account.isPaused());
    }

    function test_unpause_EmitsAContractUnpausedEvent() public {
        _pause();
        vm.expectEmit(true, true, true, true);
        emit ContractUnpaused();
        vm.prank(pauser);
        account.unpause();
    }

    function test_unpause_CannotBeCalledByARandomAccount() public {
        _pause();
        vm.prank(beneficiary);
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        account.unpause();
        assertTrue(account.isPaused());
    }

    // =========================================================================
    //                             when paused
    // =========================================================================

    function _expectPaused() private {
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
    }

    function test_WhenPaused_CantCallScheduleVotes() public {
        _pause();
        address[] memory groups = _addrs(groupAddresses[0]);
        uint256[] memory votes = _amounts(100);
        vm.prank(managerSigner);
        _expectPaused();
        account.scheduleVotes{value: 100}(groups, votes);
    }

    function test_WhenPaused_CantCallScheduleTransfer() public {
        _pause();
        vm.prank(managerSigner);
        _expectPaused();
        account.scheduleTransfer(
            _addrs(groupAddresses[0]),
            _amounts(1),
            _addrs(groupAddresses[1]),
            _amounts(1)
        );
    }

    function test_WhenPaused_CantCallScheduleWithdrawals() public {
        _pause();
        vm.prank(managerSigner);
        _expectPaused();
        account.scheduleWithdrawals(beneficiary, _addrs(groupAddresses[0]), _amounts(260));
    }

    function test_WhenPaused_CantCallWithdraw() public {
        _pause();
        vm.prank(managerSigner);
        _expectPaused();
        account.withdraw(
            beneficiary,
            groupAddresses[0],
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            0
        );
    }

    function test_WhenPaused_CantCallActivateAndVote() public {
        _pause();
        _expectPaused();
        account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
    }

    function test_WhenPaused_CantCallFinishPendingWithdrawal() public {
        _pause();
        _expectPaused();
        account.finishPendingWithdrawal(beneficiary, 0, 0);
    }

    function test_WhenPaused_CantCallVotePartially() public {
        _pause();
        vm.prank(managerSigner);
        _expectPaused();
        account.votePartially(0, 0, 1, 1, 1);
    }

    function test_WhenPaused_CantCallRevokeVotes() public {
        _pause();
        _expectPaused();
        account.revokeVotes(
            groupAddresses[0],
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            0
        );
    }
}
