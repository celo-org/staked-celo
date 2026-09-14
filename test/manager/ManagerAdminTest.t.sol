// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./ManagerTestBase.sol";

/**
 * @title ManagerAdminTest
 * @notice Ports `#setDependencies()`, `#setPauser`, `#pause`, `#unpause`, `when paused` and
 *         `#renounceOwnership` of test-ts/manager.test.ts.
 */
contract ManagerAdminTest is ManagerTestBase {
    // =========================================================================
    //                          #setDependencies()
    // =========================================================================

    function test_setDependencies_RevertsWithZeroStCeloAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        manager.setDependencies(ADDRESS_ZERO, nonAccount, nonVote, nonVote, nonVote, nonVote);
    }

    function test_setDependencies_RevertsWithZeroAccountAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        manager.setDependencies(nonStakedCelo, ADDRESS_ZERO, nonVote, nonVote, nonVote, nonVote);
    }

    function test_setDependencies_RevertsWithZeroVoteAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        manager.setDependencies(nonStakedCelo, nonAccount, ADDRESS_ZERO, nonVote, nonVote, nonVote);
    }

    function test_setDependencies_RevertsWithZeroGroupHealthAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        manager.setDependencies(nonStakedCelo, nonAccount, nonVote, ADDRESS_ZERO, nonVote, nonVote);
    }

    function test_setDependencies_RevertsWithZeroSpecificGroupStrategyAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        manager.setDependencies(nonStakedCelo, nonAccount, nonVote, nonVote, ADDRESS_ZERO, nonVote);
    }

    function test_setDependencies_RevertsWithZeroDefaultStrategyAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        manager.setDependencies(nonStakedCelo, nonAccount, nonVote, nonVote, nonVote, ADDRESS_ZERO);
    }

    function test_setDependencies_SetsTheVoteContract() public {
        vm.prank(owner);
        manager.setDependencies(nonStakedCelo, nonAccount, nonVote, nonVote, nonVote, nonVote);
        assertEq(manager.voteContract(), nonVote);
    }

    function test_setDependencies_EmitsAVoteContractSetEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit VoteContractSet(nonVote);
        manager.setDependencies(nonStakedCelo, nonAccount, nonVote, nonVote, nonVote, nonVote);
    }

    function test_setDependencies_CannotBeCalledByANonOwnerAccount() public {
        vm.prank(nonOwner);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        manager.setDependencies(nonStakedCelo, nonAccount, nonVote, nonVote, nonVote, nonVote);
    }

    // =========================================================================
    //                              #setPauser
    // =========================================================================

    function test_setPauser_SetsThePauserAddressToTheOwnerOfTheContract() public {
        vm.prank(owner);
        manager.setPauser();
        assertEq(manager.pauser(), owner);
    }

    function test_setPauser_EmitsAPauserSetEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit PauserSet(owner);
        manager.setPauser();
    }

    function test_setPauser_CannotBeCalledByANonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        manager.setPauser();
    }

    function test_setPauser_WhenTheOwnerIsChanged_SetsThePauserToTheNewOwner() public {
        vm.prank(owner);
        manager.transferOwnership(nonOwner);

        vm.prank(nonOwner);
        manager.setPauser();
        assertEq(manager.pauser(), nonOwner);
    }

    // =========================================================================
    //                                #pause
    // =========================================================================

    function test_pause_CanBeCalledByThePauser() public {
        vm.prank(pauser);
        manager.pause();
        assertTrue(manager.isPaused());
    }

    function test_pause_EmitsAContractPausedEvent() public {
        vm.prank(pauser);
        vm.expectEmit(true, true, true, true);
        emit ContractPaused();
        manager.pause();
    }

    function test_pause_CannotBeCalledByARandomAccount() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        manager.pause();
        assertFalse(manager.isPaused());
    }

    // =========================================================================
    //                               #unpause
    // =========================================================================

    function test_unpause_CanBeCalledByThePauser() public {
        pauseManager();
        vm.prank(pauser);
        manager.unpause();
        assertFalse(manager.isPaused());
    }

    function test_unpause_EmitsAContractUnpausedEvent() public {
        pauseManager();
        vm.prank(pauser);
        vm.expectEmit(true, true, true, true);
        emit ContractUnpaused();
        manager.unpause();
    }

    function test_unpause_CannotBeCalledByARandomAccount() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        manager.unpause();
        assertTrue(manager.isPaused());
    }

    // =========================================================================
    //                             when paused
    // =========================================================================

    function test_whenPaused_CantCallWithdraw() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        manager.withdraw(100);
    }

    function test_whenPaused_CantCallRevokeVotes() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        manager.revokeVotes(0, 0);
    }

    function test_whenPaused_CantCallUpdateHistoryAndReturnLockedStCeloInVoting() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        manager.updateHistoryAndReturnLockedStCeloInVoting(nonOwner);
    }

    function test_whenPaused_CantCallDeposit() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        manager.deposit{value: 100}();
    }

    function test_whenPaused_CantCallChangeStrategy() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        manager.changeStrategy(ADDRESS_ZERO);
    }

    function test_whenPaused_CantCallRebalance() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        manager.rebalance(ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_whenPaused_CantCallRebalanceOverflow() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        manager.rebalanceOverflow(ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_whenPaused_CantCallVoteProposal() public {
        pauseManager();
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        manager.voteProposal(0, 0, 0, 0, 0);
    }

    // =========================================================================
    //                          #renounceOwnership
    // =========================================================================

    function test_renounceOwnership_RevertsWithRenounceOwnershipDisabled() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Manager.RenounceOwnershipDisabled.selector));
        manager.renounceOwnership();
    }

    function test_renounceOwnership_RevertsForAnyCaller() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Manager.RenounceOwnershipDisabled.selector));
        manager.renounceOwnership();
    }

    // =========================================================================
    //                              HELPERS
    // =========================================================================

    /// @dev `beforeEach` of the `#unpause` / `when paused` blocks.
    function pauseManager() private {
        vm.prank(pauser);
        manager.pause();
    }
}
