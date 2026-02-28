// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/deploy/TestAccountDeployHelper.sol";
import "../contracts/StakedCelo.sol";
import "../contracts/mock/MockManager.sol";
import "../contracts/Pausable.sol";
import "../contracts/Managed.sol";

contract StakedCeloTest is TestAccountDeployHelper {
    address nonManager;
    address anAccount;

    // =========================================================================
    //                          Events
    // =========================================================================

    event Transfer(address indexed from, address indexed to, uint256 value);
    event ManagerSet(address indexed manager);
    event LockedStCelo(address account, uint256 amount);
    event PauserSet(address pauser);
    event ContractPaused();
    event ContractUnpaused();

    // =========================================================================
    //                          setUp
    // =========================================================================

    function setUp() public {
        deployTestStakedCelo();

        nonManager = randomAddress();
        vm.deal(nonManager, 100 ether);
        anAccount = randomAddress();
        vm.deal(anAccount, 100 ether);

        vm.prank(owner);
        stakedCelo.setManager(address(mockManager));

        vm.deal(address(mockManager), 100 ether);

        vm.prank(owner);
        stakedCelo.setPauser();
    }

    // =========================================================================
    //                          #mint() tests (4)
    // =========================================================================

    function test_mint_mintsSpecifiedAmountToAddress() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);
        assertEq(stakedCelo.balanceOf(anAccount), 100);
    }

    function test_mint_incrementsTotalSupply() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);
        assertEq(stakedCelo.totalSupply(), 100);
    }

    function test_mint_cannotBeCalledByNonManager() public {
        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        vm.prank(nonManager);
        stakedCelo.mint(anAccount, 100);
    }

    function test_mint_emitsTransferEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(ADDRESS_ZERO, anAccount, 100);
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);
    }

    // =========================================================================
    //                          #burn() tests (5)
    // =========================================================================

    function test_burn_burnsSpecifiedAmountFromAddress() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);

        vm.prank(address(mockManager));
        stakedCelo.burn(anAccount, 50);
        assertEq(stakedCelo.balanceOf(anAccount), 50);
    }

    function test_burn_decrementsTotalSupply() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);

        vm.prank(address(mockManager));
        stakedCelo.burn(anAccount, 50);
        assertEq(stakedCelo.totalSupply(), 50);
    }

    function test_burn_cannotBeCalledByNonManager() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);

        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        vm.prank(nonManager);
        stakedCelo.burn(anAccount, 50);
    }

    function test_burn_cannotBurnMoreThanBalance() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        vm.prank(address(mockManager));
        stakedCelo.burn(anAccount, 101);
    }

    function test_burn_emitsTransferEvent() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);

        vm.expectEmit(true, true, true, true);
        emit Transfer(anAccount, ADDRESS_ZERO, 50);
        vm.prank(address(mockManager));
        stakedCelo.burn(anAccount, 50);
    }

    // =========================================================================
    //                      #setManager() tests (3)
    // =========================================================================

    function test_setManager_setsTheManager() public {
        vm.prank(owner);
        stakedCelo.setManager(nonManager);
        assertEq(stakedCelo.manager(), nonManager);
    }

    function test_setManager_emitsManagerSetEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ManagerSet(nonManager);
        vm.prank(owner);
        stakedCelo.setManager(nonManager);
    }

    function test_setManager_cannotBeCalledByNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(mockManager));
        stakedCelo.setManager(nonManager);
    }

    // =========================================================================
    //                   #lockVoteBalance tests (6)
    // =========================================================================

    function test_lockVoteBalance_revertsIfCalledByNonManager() public {
        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        vm.prank(nonManager);
        stakedCelo.lockVoteBalance(anAccount, 100);
    }

    function test_lockVoteBalance_revertsIfNotEnoughStCelo() public {
        vm.expectRevert(abi.encodeWithSelector(StakedCelo.NotEnoughStCeloToLock.selector, anAccount));
        vm.prank(address(mockManager));
        stakedCelo.lockVoteBalance(anAccount, 100);
    }

    function test_lockVoteBalance_emitsLockedStCeloEvent() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);

        vm.expectEmit(true, true, true, true);
        emit LockedStCelo(anAccount, 100);
        vm.prank(address(mockManager));
        stakedCelo.lockVoteBalance(anAccount, 100);
    }

    function test_lockVoteBalance_locksMaxAmount() public {
        uint256 stCeloOwned = 100;
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, stCeloOwned);

        // Lock 10
        vm.prank(address(mockManager));
        stakedCelo.lockVoteBalance(anAccount, 10);
        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), 10);
        assertEq(stakedCelo.balanceOf(anAccount), stCeloOwned - 10);

        // Lock 20 (increases locked amount)
        vm.prank(address(mockManager));
        stakedCelo.lockVoteBalance(anAccount, 20);
        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), 20);
        assertEq(stakedCelo.balanceOf(anAccount), stCeloOwned - 20);

        // Lock 5 (does not decrease — stays at max 20)
        vm.prank(address(mockManager));
        stakedCelo.lockVoteBalance(anAccount, 5);
        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), 20);
        assertEq(stakedCelo.balanceOf(anAccount), stCeloOwned - 20);
    }

    function test_lockVoteBalance_failsToTransferLockedPlusUnlockedBalance() public {
        uint256 stCeloOwned = 100;
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, stCeloOwned);

        vm.prank(address(mockManager));
        stakedCelo.lockVoteBalance(anAccount, stCeloOwned / 2);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(anAccount);
        stakedCelo.transfer(address(mockManager), stCeloOwned);
    }

    function test_lockVoteBalance_allowsTransferOfUnlockedBalance() public {
        uint256 stCeloOwned = 100;
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, stCeloOwned);

        vm.prank(address(mockManager));
        stakedCelo.lockVoteBalance(anAccount, stCeloOwned / 2);

        assertEq(stakedCelo.balanceOf(anAccount), stCeloOwned / 2);
        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), stCeloOwned / 2);

        vm.prank(anAccount);
        stakedCelo.transfer(address(mockManager), stCeloOwned / 2);

        assertEq(stakedCelo.balanceOf(anAccount), 0);
        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), stCeloOwned / 2);
    }

    // =========================================================================
    //                 #unlockVoteBalance tests (4)
    // =========================================================================

    function test_unlockVoteBalance_revertsWhenNoLockedStCelo() public {
        vm.expectRevert(abi.encodeWithSelector(StakedCelo.NoLockedStakedCelo.selector, anAccount));
        stakedCelo.unlockVoteBalance(anAccount);
    }

    function test_unlockVoteBalance_revertsWhenManagerReturnsFullLockedAmount() public {
        uint256 stCeloOwned = 100;
        vm.startPrank(address(mockManager));
        stakedCelo.mint(anAccount, stCeloOwned);
        stakedCelo.lockVoteBalance(anAccount, stCeloOwned);
        vm.stopPrank();

        assertEq(stakedCelo.balanceOf(anAccount), 0);
        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), stCeloOwned);
        assertEq(stakedCelo.totalSupply(), stCeloOwned);

        mockManager.setLockedStCelo(stCeloOwned);

        vm.expectRevert(abi.encodeWithSelector(StakedCelo.NothingToUnlock.selector, anAccount));
        vm.prank(address(mockManager));
        stakedCelo.unlockVoteBalance(anAccount);
    }

    function test_unlockVoteBalance_unlocksHalfWhenManagerReturnsHalf() public {
        uint256 stCeloOwned = 100;
        vm.startPrank(address(mockManager));
        stakedCelo.mint(anAccount, stCeloOwned);
        stakedCelo.lockVoteBalance(anAccount, stCeloOwned);
        vm.stopPrank();

        assertEq(stakedCelo.balanceOf(anAccount), 0);
        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), stCeloOwned);
        assertEq(stakedCelo.totalSupply(), stCeloOwned);

        mockManager.setLockedStCelo(stCeloOwned / 2);
        vm.prank(address(mockManager));
        stakedCelo.unlockVoteBalance(anAccount);

        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), stCeloOwned / 2);
        assertEq(stakedCelo.balanceOf(anAccount), stCeloOwned / 2);
        assertEq(stakedCelo.totalSupply(), stCeloOwned);
    }

    function test_unlockVoteBalance_unlocksAllWhenManagerReturnsZero() public {
        uint256 stCeloOwned = 100;
        vm.startPrank(address(mockManager));
        stakedCelo.mint(anAccount, stCeloOwned);
        stakedCelo.lockVoteBalance(anAccount, stCeloOwned);
        vm.stopPrank();

        assertEq(stakedCelo.balanceOf(anAccount), 0);
        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), stCeloOwned);
        assertEq(stakedCelo.totalSupply(), stCeloOwned);

        mockManager.setLockedStCelo(0);
        vm.prank(address(mockManager));
        stakedCelo.unlockVoteBalance(anAccount);

        assertEq(stakedCelo.lockedVoteBalanceOf(anAccount), 0);
        assertEq(stakedCelo.balanceOf(anAccount), stCeloOwned);
        assertEq(stakedCelo.totalSupply(), stCeloOwned);
    }

    // =========================================================================
    //                     #transfer() tests (1)
    // =========================================================================

    function test_transfer_callsManagerTransfer() public {
        vm.prank(address(mockManager));
        stakedCelo.mint(anAccount, 100);

        vm.prank(anAccount);
        stakedCelo.transfer(address(mockManager), 1);

        (address from, address to, uint256 amount) = mockManager.getTransfer(0);
        assertEq(from, anAccount);
        assertEq(to, address(mockManager));
        assertEq(amount, 1);
    }

    // =========================================================================
    //                     #setPauser tests (4)
    // =========================================================================

    function test_setPauser_setsPauserToOwner() public {
        vm.prank(owner);
        stakedCelo.setPauser();
        assertEq(stakedCelo.pauser(), owner);
    }

    function test_setPauser_emitsPauserSetEvent() public {
        vm.expectEmit(true, true, true, true);
        emit PauserSet(owner);
        vm.prank(owner);
        stakedCelo.setPauser();
    }

    function test_setPauser_cannotBeCalledByNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonManager);
        stakedCelo.setPauser();
    }

    function test_setPauser_newOwnerSetsPauser() public {
        vm.prank(owner);
        stakedCelo.transferOwnership(nonManager);

        vm.prank(nonManager);
        stakedCelo.setPauser();
        assertEq(stakedCelo.pauser(), nonManager);
    }

    // =========================================================================
    //                       #pause tests (3)
    // =========================================================================

    function test_pause_canBeCalledByPauser() public {
        vm.prank(owner);
        stakedCelo.pause();
        assertTrue(stakedCelo.isPaused());
    }

    function test_pause_emitsContractPausedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ContractPaused();
        vm.prank(owner);
        stakedCelo.pause();
    }

    function test_pause_cannotBeCalledByRandomAccount() public {
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonManager);
        stakedCelo.pause();
        assertFalse(stakedCelo.isPaused());
    }

    // =========================================================================
    //                     #unpause tests (3)
    // =========================================================================

    function test_unpause_canBeCalledByPauser() public {
        vm.prank(owner);
        stakedCelo.pause();

        vm.prank(owner);
        stakedCelo.unpause();
        assertFalse(stakedCelo.isPaused());
    }

    function test_unpause_emitsContractUnpausedEvent() public {
        vm.prank(owner);
        stakedCelo.pause();

        vm.expectEmit(true, true, true, true);
        emit ContractUnpaused();
        vm.prank(owner);
        stakedCelo.unpause();
    }

    function test_unpause_cannotBeCalledByRandomAccount() public {
        vm.prank(owner);
        stakedCelo.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonManager);
        stakedCelo.unpause();
        assertTrue(stakedCelo.isPaused());
    }

    // =========================================================================
    //                    when paused tests (6)
    // =========================================================================

    function test_whenPaused_cantCallUnlockVoteBalance() public {
        vm.prank(anAccount);
        stakedCelo.approve(nonManager, 1);
        vm.prank(owner);
        stakedCelo.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(anAccount);
        stakedCelo.unlockVoteBalance(anAccount);
    }

    function test_whenPaused_cantCallTransfer() public {
        vm.prank(anAccount);
        stakedCelo.approve(nonManager, 1);
        vm.prank(owner);
        stakedCelo.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(nonManager);
        stakedCelo.transfer(anAccount, 1);
    }

    function test_whenPaused_cantCallApprove() public {
        vm.prank(anAccount);
        stakedCelo.approve(nonManager, 1);
        vm.prank(owner);
        stakedCelo.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(nonManager);
        stakedCelo.approve(anAccount, 1);
    }

    function test_whenPaused_cantCallTransferFrom() public {
        vm.prank(anAccount);
        stakedCelo.approve(nonManager, 1);
        vm.prank(owner);
        stakedCelo.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(nonManager);
        stakedCelo.transferFrom(anAccount, nonManager, 1);
    }

    function test_whenPaused_cantCallIncreaseAllowance() public {
        vm.prank(anAccount);
        stakedCelo.approve(nonManager, 1);
        vm.prank(owner);
        stakedCelo.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(nonManager);
        stakedCelo.increaseAllowance(nonManager, 1);
    }

    function test_whenPaused_cantCallDecreaseAllowance() public {
        vm.prank(anAccount);
        stakedCelo.approve(nonManager, 1);
        vm.prank(owner);
        stakedCelo.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(anAccount);
        stakedCelo.decreaseAllowance(nonManager, 1);
    }
}
