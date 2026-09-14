// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./SpecificGroupStrategyTestBase.sol";

/**
 * @title SpecificGroupStrategyAdminTest
 * @notice Port of the ownership / pausing describe blocks of
 *         test-ts/specific_group_strategy.test.ts:
 *         #setDependencies (6), #renounceOwnership (2), #setPauser (4), #pause (3),
 *         #unpause (3) and "when paused" (2).
 */
contract SpecificGroupStrategyAdminTest is SpecificGroupStrategyTestBase {
    function setUp() public {
        _setUpSpecificGroupStrategy();
    }

    // =========================================================================
    //                          #setDependencies()
    // =========================================================================

    function test_setDependencies_RevertsWithZeroAccountAddress() public {
        vm.prank(manager.owner());
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        specificGroupStrategy.setDependencies(ADDRESS_ZERO, nonVote, nonVote);
    }

    function test_setDependencies_RevertsWithZeroGroupHealthAddress() public {
        vm.prank(manager.owner());
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        specificGroupStrategy.setDependencies(nonVote, ADDRESS_ZERO, nonVote);
    }

    function test_setDependencies_RevertsWithZeroDefaultStrategyAddress() public {
        vm.prank(manager.owner());
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        specificGroupStrategy.setDependencies(nonVote, nonVote, ADDRESS_ZERO);
    }

    function test_setDependencies_SetsTheVoteContract() public {
        vm.prank(manager.owner());
        specificGroupStrategy.setDependencies(nonAccount, nonStakedCelo, nonOwner);

        assertEq(address(specificGroupStrategy.account()), nonAccount);
        assertEq(address(specificGroupStrategy.groupHealth()), nonStakedCelo);
        assertEq(address(specificGroupStrategy.defaultStrategy()), nonOwner);
    }

    function test_setDependencies_CannotBeCalledByANonOwnerAccount() public {
        vm.prank(nonOwner);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        specificGroupStrategy.setDependencies(nonStakedCelo, nonAccount, nonAccount);
    }

    function test_setDependencies_EmitsDependenciesSetEvent() public {
        vm.prank(manager.owner());
        _expectEmitFrom(address(specificGroupStrategy));
        emit DependenciesSet(nonAccount, nonStakedCelo, nonOwner);
        specificGroupStrategy.setDependencies(nonAccount, nonStakedCelo, nonOwner);
    }

    // =========================================================================
    //                          #renounceOwnership
    // =========================================================================

    function test_renounceOwnership_RevertsWithRenounceOwnershipDisabled() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Managed.RenounceOwnershipDisabled.selector));
        specificGroupStrategy.renounceOwnership();
    }

    function test_renounceOwnership_RevertsForAnyCaller() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Managed.RenounceOwnershipDisabled.selector));
        specificGroupStrategy.renounceOwnership();
    }

    // =========================================================================
    //                              #setPauser
    // =========================================================================

    function test_setPauser_SetsThePauserAddressToTheOwnerOfTheContract() public {
        vm.prank(owner);
        specificGroupStrategy.setPauser();
        assertEq(specificGroupStrategy.pauser(), owner);
    }

    function test_setPauser_EmitsAPauserSetEvent() public {
        vm.prank(owner);
        _expectEmitFrom(address(specificGroupStrategy));
        emit PauserSet(owner);
        specificGroupStrategy.setPauser();
    }

    function test_setPauser_CannotBeCalledByANonOwner() public {
        vm.prank(nonManager);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        specificGroupStrategy.setPauser();
    }

    function test_setPauser_WhenTheOwnerIsChanged_SetsThePauserToTheNewOwner() public {
        _whenTheOwnerIsChanged();

        vm.prank(nonManager);
        specificGroupStrategy.setPauser();
        assertEq(specificGroupStrategy.pauser(), nonManager);
    }

    /// @dev beforeEach of describe("when the owner is changed").
    function _whenTheOwnerIsChanged() private {
        vm.prank(owner);
        specificGroupStrategy.transferOwnership(nonManager);
    }

    // =========================================================================
    //                                #pause
    // =========================================================================

    function test_pause_CanBeCalledByThePauser() public {
        vm.prank(pauser);
        specificGroupStrategy.pause();
        assertTrue(specificGroupStrategy.isPaused());
    }

    function test_pause_EmitsAContractPausedEvent() public {
        vm.prank(pauser);
        _expectEmitFrom(address(specificGroupStrategy));
        emit ContractPaused();
        specificGroupStrategy.pause();
    }

    function test_pause_CannotBeCalledByARandomAccount() public {
        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        specificGroupStrategy.pause();

        assertFalse(specificGroupStrategy.isPaused());
    }

    // =========================================================================
    //                               #unpause
    // =========================================================================

    function test_unpause_CanBeCalledByThePauser() public {
        _pause();

        vm.prank(pauser);
        specificGroupStrategy.unpause();
        assertFalse(specificGroupStrategy.isPaused());
    }

    function test_unpause_EmitsAContractUnpausedEvent() public {
        _pause();

        vm.prank(pauser);
        _expectEmitFrom(address(specificGroupStrategy));
        emit ContractUnpaused();
        specificGroupStrategy.unpause();
    }

    function test_unpause_CannotBeCalledByARandomAccount() public {
        _pause();

        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        specificGroupStrategy.unpause();

        assertTrue(specificGroupStrategy.isPaused());
    }

    // =========================================================================
    //                             when paused
    // =========================================================================

    function test_WhenPaused_CantCallRebalanceWhenHealthChanged() public {
        _pause();

        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        specificGroupStrategy.rebalanceWhenHealthChanged(ADDRESS_ZERO);
    }

    function test_WhenPaused_CantCallRebalanceOverflowedGroup() public {
        _pause();

        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        specificGroupStrategy.rebalanceOverflowedGroup(ADDRESS_ZERO);
    }

    /// @dev beforeEach of describe("#unpause") and describe("when paused").
    function _pause() private {
        vm.prank(pauser);
        specificGroupStrategy.pause();
    }
}
