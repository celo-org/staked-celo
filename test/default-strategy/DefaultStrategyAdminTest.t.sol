// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./DefaultStrategyTestBase.sol";

/**
 * @title DefaultStrategyAdminTest
 * @notice Ports the owner / pauser related describe blocks of
 *         `test-ts/default-strategy.test.ts`: `#setDependencies()`, `#setSortingParams`,
 *         `#setMinCountOfActiveGroups`, `#renounceOwnership`, `#setPauser`, `#pause`,
 *         `#unpause` and `when paused`.
 */
contract DefaultStrategyAdminTest is DefaultStrategyTestBase {
    function setUp() public {
        _deployDefaultStrategyFixture();
    }

    // =========================================================================
    //                          #setDependencies()
    // =========================================================================

    function test_setDependencies_RevertsWithZeroAccountAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        vm.prank(owner);
        mockDefaultStrategy.setDependencies(ADDRESS_ZERO, nonVote, nonVote);
    }

    function test_setDependencies_RevertsWithZeroGroupHealthAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        vm.prank(owner);
        mockDefaultStrategy.setDependencies(nonVote, ADDRESS_ZERO, nonVote);
    }

    function test_setDependencies_RevertsWithZeroSpecificGroupStrategyAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        vm.prank(owner);
        mockDefaultStrategy.setDependencies(nonVote, nonVote, ADDRESS_ZERO);
    }

    function test_setDependencies_SetsTheVoteContract() public {
        vm.prank(owner);
        mockDefaultStrategy.setDependencies(nonAccount, nonStakedCelo, nonVote);

        assertEq(address(defaultStrategy.account()), nonAccount);
        assertEq(address(defaultStrategy.groupHealth()), nonStakedCelo);
        assertEq(address(defaultStrategy.specificGroupStrategy()), nonVote);
    }

    function test_setDependencies_CannotBeCalledByANonOwnerAccount() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonOwner);
        mockDefaultStrategy.setDependencies(nonStakedCelo, nonAccount, nonVote);
    }

    function test_setDependencies_EmitsDependenciesSetEvent() public {
        _expectEmitFrom(address(mockDefaultStrategy));
        emit DependenciesSet(nonAccount, nonStakedCelo, nonVote);
        vm.prank(owner);
        mockDefaultStrategy.setDependencies(nonAccount, nonStakedCelo, nonVote);
    }

    // =========================================================================
    //                          #setSortingParams
    // =========================================================================

    function test_setSortingParams_EmitsSortingParamsSetEvent() public {
        uint256 distributeTo = 5;
        uint256 withdrawFrom = 3;
        uint256 loopLimit = 10;

        _expectEmitFrom(address(mockDefaultStrategy));
        emit SortingParamsSet(distributeTo, withdrawFrom, loopLimit);
        vm.prank(owner);
        mockDefaultStrategy.setSortingParams(distributeTo, withdrawFrom, loopLimit);
    }

    // =========================================================================
    //                     #setMinCountOfActiveGroups
    // =========================================================================

    function test_setMinCountOfActiveGroups_ShouldSetMinimumCountOfActiveGroups() public {
        vm.prank(owner);
        mockDefaultStrategy.setMinCountOfActiveGroups(5);
        assertEq(defaultStrategy.minCountOfActiveGroups(), 5);
    }

    function test_setMinCountOfActiveGroups_EmitsMinCountOfActiveGroupsSetEvent() public {
        _expectEmitFrom(address(mockDefaultStrategy));
        emit MinCountOfActiveGroupsSet(5);
        vm.prank(owner);
        mockDefaultStrategy.setMinCountOfActiveGroups(5);
    }

    // =========================================================================
    //                         #renounceOwnership
    // =========================================================================

    function test_renounceOwnership_RevertsWithRenounceOwnershipDisabled() public {
        vm.expectRevert(abi.encodeWithSelector(Managed.RenounceOwnershipDisabled.selector));
        vm.prank(owner);
        mockDefaultStrategy.renounceOwnership();
    }

    function test_renounceOwnership_RevertsForAnyCaller() public {
        vm.expectRevert(abi.encodeWithSelector(Managed.RenounceOwnershipDisabled.selector));
        vm.prank(nonOwner);
        mockDefaultStrategy.renounceOwnership();
    }

    // =========================================================================
    //                             #setPauser
    // =========================================================================

    function test_setPauser_SetsThePauserAddressToTheOwnerOfTheContract() public {
        vm.prank(owner);
        mockDefaultStrategy.setPauser();
        assertEq(defaultStrategy.pauser(), owner);
    }

    function test_setPauser_EmitsAPauserSetEvent() public {
        _expectEmitFrom(address(mockDefaultStrategy));
        emit PauserSet(owner);
        vm.prank(owner);
        mockDefaultStrategy.setPauser();
    }

    function test_setPauser_CannotBeCalledByANonOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonManager);
        mockDefaultStrategy.setPauser();
    }

    /// @dev `describe("when the owner is changed")` beforeEach.
    function _setUpOwnerChanged() private {
        vm.prank(owner);
        mockDefaultStrategy.transferOwnership(nonManager);
    }

    function test_setPauser_WhenTheOwnerIsChanged_SetsThePauserToTheNewOwner() public {
        _setUpOwnerChanged();

        vm.prank(nonManager);
        mockDefaultStrategy.setPauser();
        assertEq(defaultStrategy.pauser(), nonManager);
    }

    // =========================================================================
    //                               #pause
    // =========================================================================

    function test_pause_CanBeCalledByThePauser() public {
        vm.prank(pauser);
        mockDefaultStrategy.pause();
        assertTrue(defaultStrategy.isPaused());
    }

    function test_pause_EmitsAContractPausedEvent() public {
        _expectEmitFrom(address(mockDefaultStrategy));
        emit ContractPaused();
        vm.prank(pauser);
        mockDefaultStrategy.pause();
    }

    function test_pause_CannotBeCalledByARandomAccount() public {
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonOwner);
        mockDefaultStrategy.pause();

        assertFalse(defaultStrategy.isPaused());
    }

    // =========================================================================
    //                              #unpause
    // =========================================================================

    /// @dev `describe("#unpause")` beforeEach.
    function _setUpPaused() private {
        vm.prank(pauser);
        mockDefaultStrategy.pause();
    }

    function test_unpause_CanBeCalledByThePauser() public {
        _setUpPaused();

        vm.prank(pauser);
        mockDefaultStrategy.unpause();
        assertFalse(defaultStrategy.isPaused());
    }

    function test_unpause_EmitsAContractUnpausedEvent() public {
        _setUpPaused();

        _expectEmitFrom(address(mockDefaultStrategy));
        emit ContractUnpaused();
        vm.prank(pauser);
        mockDefaultStrategy.unpause();
    }

    function test_unpause_CannotBeCalledByARandomAccount() public {
        _setUpPaused();

        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonOwner);
        mockDefaultStrategy.unpause();

        assertTrue(defaultStrategy.isPaused());
    }

    // =========================================================================
    //                             when paused
    // =========================================================================

    function test_whenPaused_CantCallUpdateActiveGroupOrder() public {
        _setUpPaused();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        mockDefaultStrategy.updateActiveGroupOrder(ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_whenPaused_CantCallRebalance() public {
        _setUpPaused();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        mockDefaultStrategy.rebalance(ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_whenPaused_CantCallDeactivateUnhealthyGroup() public {
        _setUpPaused();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        mockDefaultStrategy.deactivateUnhealthyGroup(ADDRESS_ZERO);
    }
}
