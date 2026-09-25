// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/deploy/TestAccountDeployHelper.sol";
import "../contracts/test/PausableTest.sol";
import "../contracts/Pausable.sol";
import "../contracts/common/Errors.sol";

contract PausableTestTest is TestAccountDeployHelper {
    address pauser;
    address nonPauser;

    function setUp() public {
        deployTestPausable();
        pauser = randomAddress();
        nonPauser = randomAddress();
        pausableTest.setPauser(pauser);
    }

    // =========================================================================
    //                          #pause tests
    // =========================================================================

    function test_pause_setsContractToPaused() public {
        vm.prank(pauser);
        pausableTest.pause();
        assertTrue(pausableTest.isPaused());
    }

    function test_pause_emitsContractPausedEvent() public {
        vm.expectEmit(true, true, true, true, address(pausableTest));
        emit ContractPaused();
        vm.prank(pauser);
        pausableTest.pause();
    }

    function test_pause_cannotBeCalledByNonPauser() public {
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonPauser);
        pausableTest.pause();
        assertFalse(pausableTest.isPaused());
    }

    function test_pause_whenPaused_blocksCallPausable() public {
        vm.prank(pauser);
        pausableTest.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        pausableTest.callPausable();
    }

    function test_pause_whenPaused_allowsCallAlways() public {
        vm.prank(pauser);
        pausableTest.pause();

        uint256 numberBefore = pausableTest.numberCalls();
        assertEq(numberBefore, 0);
        pausableTest.callAlways();
        uint256 numberAfter = pausableTest.numberCalls();
        assertEq(numberAfter, 1);
    }

    // =========================================================================
    //                          #unpause tests
    // =========================================================================

    function test_unpause_setsContractToUnpaused() public {
        vm.prank(pauser);
        pausableTest.pause();

        vm.prank(pauser);
        pausableTest.unpause();
        assertFalse(pausableTest.isPaused());
    }

    function test_unpause_emitsContractUnpausedEvent() public {
        vm.prank(pauser);
        pausableTest.pause();

        vm.expectEmit(true, true, true, true, address(pausableTest));
        emit ContractUnpaused();
        vm.prank(pauser);
        pausableTest.unpause();
    }

    function test_unpause_cannotBeCalledByNonPauser() public {
        vm.prank(pauser);
        pausableTest.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonPauser);
        pausableTest.unpause();
        assertTrue(pausableTest.isPaused());
    }

    function test_unpause_onceUnpaused_allowsCallPausable() public {
        vm.prank(pauser);
        pausableTest.pause();

        vm.prank(pauser);
        pausableTest.unpause();

        uint256 numberBefore = pausableTest.numberCalls();
        assertEq(numberBefore, 0);
        pausableTest.callPausable();
        uint256 numberAfter = pausableTest.numberCalls();
        assertEq(numberAfter, 1);
    }

    function test_unpause_onceUnpaused_allowsCallAlways() public {
        vm.prank(pauser);
        pausableTest.pause();

        vm.prank(pauser);
        pausableTest.unpause();

        uint256 numberBefore = pausableTest.numberCalls();
        assertEq(numberBefore, 0);
        pausableTest.callAlways();
        uint256 numberAfter = pausableTest.numberCalls();
        assertEq(numberAfter, 1);
    }

    // =========================================================================
    //                          #_setPauser tests
    // =========================================================================

    function test_setPauser_setsPauser() public {
        pausableTest.setPauser(nonPauser);
        assertEq(pausableTest.pauser(), nonPauser);
    }

    function test_setPauser_doesntAllowAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        pausableTest.setPauser(ADDRESS_ZERO);
    }

    function test_setPauser_emitsPauserSetEvent() public {
        vm.expectEmit(true, true, true, true, address(pausableTest));
        emit PauserSet(nonPauser);
        pausableTest.setPauser(nonPauser);
    }

    function test_setPauser_whenChanged_allowsNewPauserToPause() public {
        pausableTest.setPauser(nonPauser);

        vm.prank(nonPauser);
        pausableTest.pause();
        assertTrue(pausableTest.isPaused());
    }

    function test_setPauser_whenChanged_blocksOldPauser() public {
        pausableTest.setPauser(nonPauser);

        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(pauser);
        pausableTest.pause();
        assertFalse(pausableTest.isPaused());
    }

    // =========================================================================
    //                          Events (from Pausable.sol)
    // =========================================================================

    event ContractPaused();
    event ContractUnpaused();
    event PauserSet(address pauser);
}
