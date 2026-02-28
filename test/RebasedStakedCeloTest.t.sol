// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/deploy/TestAccountDeployHelper.sol";
import "../contracts/RebasedStakedCelo.sol";
import "../contracts/Pausable.sol";
import "../contracts/common/Errors.sol";

contract RebasedStakedCeloTest is TestAccountDeployHelper {
    address alice;
    address bob;
    address someone;
    address pauser;

    function setUp() public {
        deployTestRebasedStakedCelo();

        alice = randomAddress();
        bob = randomAddress();
        someone = randomAddress();
        pauser = owner;

        vm.prank(owner);
        rebasedStakedCelo.setPauser();
    }

    // =========================================================================
    //                          #initialize() tests
    // =========================================================================

    function test_initialize_shouldBeNamedRebasedStakedCelo() public {
        string memory tokenName = rebasedStakedCelo.name();
        assertTrue(keccak256(bytes(tokenName)) == keccak256(bytes("Rebased Staked CELO")));
    }

    function test_initialize_shouldHaveRstCeloAsSymbol() public {
        string memory tokenSymbol = rebasedStakedCelo.symbol();
        assertTrue(keccak256(bytes(tokenSymbol)) == keccak256(bytes("rstCELO")));
    }

    function test_initialize_shouldHaveAnOwnerAddressSet() public {
        address actualOwner = rebasedStakedCelo.owner();
        assertEq(actualOwner, owner);
    }

    // =========================================================================
    //                          #deposit() tests
    // =========================================================================

    // -- Deposit helpers --

    function _depositSetup() internal {
        mockAccount.setTotalCelo(200);
        mockStakedCelo.mint(someone, 200);
        vm.prank(someone);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
    }

    function test_deposit_shouldRevertWhenAllowanceTooLow() public {
        _depositSetup();
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        vm.prank(someone);
        rebasedStakedCelo.deposit(150);
    }

    function test_deposit_shouldRevertWhenDepositZero() public {
        _depositSetup();
        vm.expectRevert(abi.encodeWithSelector(RebasedStakedCelo.ZeroAmount.selector));
        vm.prank(someone);
        rebasedStakedCelo.deposit(0);
    }

    function test_deposit_shouldIncreaseTotalStCeloDeposits() public {
        _depositSetup();
        vm.prank(someone);
        rebasedStakedCelo.deposit(100);
        uint256 totalDeposit = rebasedStakedCelo.totalDeposit();
        assertEq(totalDeposit, 100);
    }

    function test_deposit_shouldUpdateAccountingOfEachUserDeposit() public {
        _depositSetup();
        vm.prank(someone);
        rebasedStakedCelo.deposit(100);
        uint256 someoneDeposited = rebasedStakedCelo.stakedCeloBalance(someone);
        assertEq(someoneDeposited, 100);
    }

    function test_deposit_shouldEmitDepositedEvent() public {
        _depositSetup();
        vm.expectEmit(true, true, true, true);
        emit StakedCeloDeposited(someone, 100);
        vm.prank(someone);
        rebasedStakedCelo.deposit(100);
    }

    function test_deposit_shouldIncreaseTotalSupplyOfRstCelo() public {
        _depositSetup();
        uint256 initialSupply = rebasedStakedCelo.totalSupply();
        vm.prank(someone);
        rebasedStakedCelo.deposit(100);
        assertTrue(rebasedStakedCelo.totalSupply() > initialSupply);
    }

    // -- Deposit: less CELO than stCELO --

    function _depositLessCeloSetup() internal {
        _depositSetup();
        mockAccount.setTotalCelo(200);
        mockStakedCelo.mint(alice, 100);
        mockStakedCelo.mint(bob, 100);
        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(bob);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
    }

    function test_deposit_lessCelo_shouldComputeLessRstCeloThanDeposited() public {
        _depositLessCeloSetup();
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(bob);
        rebasedStakedCelo.deposit(100);

        uint256 aliceBalance = rebasedStakedCelo.balanceOf(alice);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(aliceBalance, 50);
        assertEq(bobBalance, 50);
    }

    // -- Deposit: equal CELO and stCELO --

    function _depositEqualCeloSetup() internal {
        _depositSetup();
        mockAccount.setTotalCelo(400);
        mockStakedCelo.mint(alice, 100);
        mockStakedCelo.mint(bob, 100);
        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(bob);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
    }

    function test_deposit_equalCelo_shouldComputeRstCeloOneToOne() public {
        _depositEqualCeloSetup();
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(bob);
        rebasedStakedCelo.deposit(100);

        uint256 aliceBalance = rebasedStakedCelo.balanceOf(alice);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(aliceBalance, 100);
        assertEq(bobBalance, 100);
    }

    // -- Deposit: more CELO than stCELO --

    function _depositMoreCeloSetup() internal {
        _depositSetup();
        mockAccount.setTotalCelo(800);
        mockStakedCelo.mint(alice, 100);
        mockStakedCelo.mint(bob, 100);
        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(bob);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
    }

    function test_deposit_moreCelo_shouldComputeMoreRstCeloThanDeposited() public {
        _depositMoreCeloSetup();
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(bob);
        rebasedStakedCelo.deposit(100);

        uint256 aliceBalance = rebasedStakedCelo.balanceOf(alice);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(aliceBalance, 200);
        assertEq(bobBalance, 200);
    }

    // =========================================================================
    //                          #withdraw() tests
    // =========================================================================

    // -- Withdraw base setup --

    function _withdrawSetup() internal {
        mockAccount.setTotalCelo(400);
        mockStakedCelo.mint(alice, 100);
        mockStakedCelo.mint(bob, 100);
        mockStakedCelo.mint(someone, 200);

        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(bob);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(bob);
        rebasedStakedCelo.deposit(100);
    }

    function test_withdraw_shouldNotAllowWithdrawMoreThanBalance() public {
        _withdrawSetup();
        vm.expectRevert(abi.encodeWithSelector(RebasedStakedCelo.InsufficientBalance.selector, 200));
        vm.prank(bob);
        rebasedStakedCelo.withdraw(200);
    }

    function test_withdraw_shouldEmitWithdrawnEvent() public {
        _withdrawSetup();
        vm.expectEmit(true, true, true, true);
        emit StakedCeloWithdrawn(alice, 50);
        vm.prank(alice);
        rebasedStakedCelo.withdraw(50);
    }

    function test_withdraw_shouldDecreaseTotalDepositedStCelo() public {
        _withdrawSetup();
        vm.prank(alice);
        rebasedStakedCelo.withdraw(50);
        assertEq(rebasedStakedCelo.totalDeposit(), 150);
    }

    function test_withdraw_shouldDecreaseUserRstCeloBalance() public {
        _withdrawSetup();
        vm.prank(alice);
        rebasedStakedCelo.withdraw(50);
        assertEq(rebasedStakedCelo.balanceOf(alice), 50);
    }

    function test_withdraw_shouldDecreaseTotalSupply() public {
        _withdrawSetup();
        uint256 initialSupply = rebasedStakedCelo.totalSupply();
        vm.prank(alice);
        rebasedStakedCelo.withdraw(50);
        assertTrue(rebasedStakedCelo.totalSupply() < initialSupply);
    }

    function test_withdraw_shouldTransferWithdrawnStCeloToAlice() public {
        _withdrawSetup();
        uint256 initialBalance = mockStakedCelo.balanceOf(alice);
        vm.prank(alice);
        rebasedStakedCelo.withdraw(50);
        assertEq(mockStakedCelo.balanceOf(alice), initialBalance + 50);
    }

    // -- Withdraw: less CELO than stCELO --

    function test_withdraw_lessCelo_shouldRebaseLeftOverBalance() public {
        _withdrawSetup();
        mockAccount.setTotalCelo(200);
        vm.prank(bob);
        rebasedStakedCelo.withdraw(50);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(bobBalance, 25);
    }

    function test_withdraw_lessCelo_shouldTransferExactWithdrawnStCeloToBob() public {
        _withdrawSetup();
        mockAccount.setTotalCelo(200);
        uint256 initialBalance = mockStakedCelo.balanceOf(bob);
        vm.prank(bob);
        rebasedStakedCelo.withdraw(50);
        assertEq(mockStakedCelo.balanceOf(bob), initialBalance + 50);
    }

    // -- Withdraw: equal CELO and stCELO --

    function test_withdraw_equalCelo_shouldBurnOneToOne() public {
        _withdrawSetup();
        mockAccount.setTotalCelo(400);
        vm.prank(bob);
        rebasedStakedCelo.withdraw(50);
        uint256 bobBalance = mockStakedCelo.balanceOf(bob);
        assertEq(bobBalance, 50);
    }

    // -- Withdraw: more CELO than stCELO --

    function test_withdraw_moreCelo_shouldBurnMoreRstCeloThanWithdrawnStCelo() public {
        _withdrawSetup();
        mockAccount.setTotalCelo(800);
        vm.prank(bob);
        rebasedStakedCelo.withdraw(50);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(bobBalance, 100);
    }

    function test_withdraw_moreCelo_shouldTransferExactWithdrawnStCeloToBob() public {
        _withdrawSetup();
        mockAccount.setTotalCelo(800);
        uint256 initialBalance = mockStakedCelo.balanceOf(bob);
        vm.prank(bob);
        rebasedStakedCelo.withdraw(50);
        assertEq(mockStakedCelo.balanceOf(bob), initialBalance + 50);
    }

    // =========================================================================
    //                          #transfer() tests
    // =========================================================================

    // -- Transfer base setup --

    function _transferSetup() internal {
        mockAccount.setTotalCelo(400);
        mockStakedCelo.mint(alice, 100);
        mockStakedCelo.mint(bob, 100);
        mockStakedCelo.mint(someone, 200);

        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(bob);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(bob);
        rebasedStakedCelo.deposit(100);
    }

    function test_transfer_shouldNotAllowTransferWhenBalanceTooLow() public {
        _transferSetup();
        vm.expectRevert(abi.encodeWithSelector(RebasedStakedCelo.InsufficientBalance.selector, 150));
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 150);
    }

    function test_transfer_shouldEmitTransferEvent() public {
        _transferSetup();
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 50);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
    }

    // -- Transfer: equal CELO and stCELO --

    function test_transfer_equalCelo_shouldDecreaseSenderStCeloDeposited() public {
        _transferSetup();
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 aliceStCelo = rebasedStakedCelo.stakedCeloBalance(alice);
        assertEq(aliceStCelo, 50);
    }

    function test_transfer_equalCelo_shouldDecreaseSenderRstCeloBalance() public {
        _transferSetup();
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 aliceBalance = rebasedStakedCelo.balanceOf(alice);
        assertEq(aliceBalance, 50);
    }

    function test_transfer_equalCelo_shouldIncreaseReceiverStCeloDeposited() public {
        _transferSetup();
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 bobStCelo = rebasedStakedCelo.stakedCeloBalance(bob);
        assertEq(bobStCelo, 150);
    }

    function test_transfer_equalCelo_shouldIncreaseReceiverRstCeloBalance() public {
        _transferSetup();
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(bobBalance, 150);
    }

    function test_transfer_equalCelo_shouldNotChangeTotalSupply() public {
        _transferSetup();
        uint256 initialSupply = rebasedStakedCelo.totalSupply();
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 currentSupply = rebasedStakedCelo.totalSupply();
        assertEq(currentSupply, initialSupply);
    }

    function test_transfer_equalCelo_shouldNotIncreaseTotalDeposited() public {
        _transferSetup();
        uint256 initialDeposits = rebasedStakedCelo.totalDeposit();
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 currentDeposits = rebasedStakedCelo.totalDeposit();
        assertEq(currentDeposits, initialDeposits);
    }

    // -- Transfer: less CELO than stCELO --

    function test_transfer_lessCelo_shouldDecreaseSenderStCeloDeposited() public {
        _transferSetup();
        mockAccount.setTotalCelo(200);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 aliceStCelo = rebasedStakedCelo.stakedCeloBalance(alice);
        assertEq(aliceStCelo, 0);
    }

    function test_transfer_lessCelo_shouldDecreaseSenderRstCeloBalance() public {
        _transferSetup();
        mockAccount.setTotalCelo(200);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 aliceBalance = rebasedStakedCelo.balanceOf(alice);
        assertEq(aliceBalance, 0);
    }

    function test_transfer_lessCelo_shouldIncreaseReceiverStCeloDeposited() public {
        _transferSetup();
        mockAccount.setTotalCelo(200);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 bobStCelo = rebasedStakedCelo.stakedCeloBalance(bob);
        assertEq(bobStCelo, 200);
    }

    function test_transfer_lessCelo_shouldIncreaseReceiverRstCeloBalance() public {
        _transferSetup();
        mockAccount.setTotalCelo(200);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(bobBalance, 100);
    }

    function test_transfer_lessCelo_shouldNotIncreaseTotalDeposited() public {
        _transferSetup();
        uint256 initialDeposits = rebasedStakedCelo.totalDeposit();
        mockAccount.setTotalCelo(200);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 currentDeposits = rebasedStakedCelo.totalDeposit();
        assertEq(currentDeposits, initialDeposits);
    }

    // -- Transfer: more CELO than stCELO --

    function test_transfer_moreCelo_shouldDecreaseSenderStCeloDeposited() public {
        _transferSetup();
        mockAccount.setTotalCelo(800);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 aliceStCelo = rebasedStakedCelo.stakedCeloBalance(alice);
        assertEq(aliceStCelo, 75);
    }

    function test_transfer_moreCelo_shouldDecreaseSenderRstCeloBalance() public {
        _transferSetup();
        mockAccount.setTotalCelo(800);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 aliceBalance = rebasedStakedCelo.balanceOf(alice);
        assertEq(aliceBalance, 150);
    }

    function test_transfer_moreCelo_shouldIncreaseReceiverStCeloDeposited() public {
        _transferSetup();
        mockAccount.setTotalCelo(800);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 bobStCelo = rebasedStakedCelo.stakedCeloBalance(bob);
        assertEq(bobStCelo, 125);
    }

    function test_transfer_moreCelo_shouldIncreaseReceiverRstCeloBalance() public {
        _transferSetup();
        mockAccount.setTotalCelo(800);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(bobBalance, 250);
    }

    function test_transfer_moreCelo_shouldNotIncreaseTotalDeposited() public {
        _transferSetup();
        uint256 initialDeposits = rebasedStakedCelo.totalDeposit();
        mockAccount.setTotalCelo(800);
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 50);
        uint256 currentDeposits = rebasedStakedCelo.totalDeposit();
        assertEq(currentDeposits, initialDeposits);
    }

    // =========================================================================
    //                          #transferFrom() tests
    // =========================================================================

    // -- TransferFrom base setup --

    function _transferFromSetup() internal {
        mockAccount.setTotalCelo(400);
        mockStakedCelo.mint(alice, 100);
        mockStakedCelo.mint(bob, 100);
        mockStakedCelo.mint(someone, 200);

        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(bob);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(bob);
        rebasedStakedCelo.deposit(100);

        vm.prank(alice);
        rebasedStakedCelo.approve(bob, 50);
    }

    function test_transferFrom_shouldPreventTransfersToZeroAddress() public {
        _transferFromSetup();
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 50);
        vm.prank(alice);
        rebasedStakedCelo.increaseAllowance(bob, 100);

        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, ADDRESS_ZERO, 50);
    }

    function test_transferFrom_shouldIncreaseReceiverRstCeloBalance() public {
        _transferFromSetup();
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 50);
        uint256 someoneBalance = rebasedStakedCelo.balanceOf(someone);
        assertEq(someoneBalance, 50);
    }

    function test_transferFrom_shouldDecreaseSenderRstCeloBalance() public {
        _transferFromSetup();
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 50);
        uint256 aliceBalance = rebasedStakedCelo.balanceOf(alice);
        assertEq(aliceBalance, 50);
    }

    function test_transferFrom_shouldNotChangeAuthorizedSignerStCeloDeposited() public {
        _transferFromSetup();
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 50);
        uint256 bobDeposit = rebasedStakedCelo.stakedCeloBalance(bob);
        assertEq(bobDeposit, 100);
    }

    function test_transferFrom_shouldIncreaseReceiverStCeloDeposited() public {
        _transferFromSetup();
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 50);
        uint256 someoneDeposit = rebasedStakedCelo.stakedCeloBalance(someone);
        assertEq(someoneDeposit, 50);
    }

    function test_transferFrom_shouldDecreaseSenderStCeloDeposited() public {
        _transferFromSetup();
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 50);
        uint256 aliceDeposit = rebasedStakedCelo.stakedCeloBalance(alice);
        assertEq(aliceDeposit, 50);
    }

    function test_transferFrom_shouldPreventTransfersWhenSenderBalanceTooLow() public {
        _transferFromSetup();
        vm.prank(alice);
        rebasedStakedCelo.increaseAllowance(bob, 100);

        vm.expectRevert(abi.encodeWithSelector(RebasedStakedCelo.InsufficientBalance.selector, 150));
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 150);
    }

    function test_transferFrom_shouldDecreaseAllowanceAfterTransfer() public {
        _transferFromSetup();
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 50);
        assertEq(rebasedStakedCelo.allowance(alice, bob), 0);
    }

    function test_transferFrom_shouldPreventTransferFromUnapprovedAddress() public {
        _transferFromSetup();
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(someone);
        rebasedStakedCelo.transferFrom(alice, someone, 100);
    }

    function test_transferFrom_shouldEmitTransferEvent() public {
        _transferFromSetup();
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, someone, 50);
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, someone, 50);
    }

    // =========================================================================
    //                          #totalSupply() tests
    // =========================================================================

    // -- TotalSupply base setup --

    function _totalSupplySetup() internal {
        mockAccount.setTotalCelo(400);
        mockStakedCelo.mint(alice, 100);
        mockStakedCelo.mint(bob, 100);
        mockStakedCelo.mint(someone, 200);

        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(bob);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(bob);
        rebasedStakedCelo.deposit(100);
    }

    function test_totalSupply_lessCelo_shouldDecreaseTotalRstCeloSupply() public {
        _totalSupplySetup();
        uint256 initialSupply = rebasedStakedCelo.totalSupply();
        mockAccount.setTotalCelo(200);
        uint256 currentSupply = rebasedStakedCelo.totalSupply();
        assertTrue(currentSupply < initialSupply);
    }

    function test_totalSupply_equalCelo_shouldNotChangeTotalRstCeloSupply() public {
        _totalSupplySetup();
        uint256 initialSupply = rebasedStakedCelo.totalSupply();
        mockAccount.setTotalCelo(400);
        uint256 currentSupply = rebasedStakedCelo.totalSupply();
        assertEq(currentSupply, initialSupply);
    }

    function test_totalSupply_moreCelo_shouldIncreaseTotalRstCeloSupply() public {
        _totalSupplySetup();
        uint256 initialSupply = rebasedStakedCelo.totalSupply();
        mockAccount.setTotalCelo(800);
        uint256 currentSupply = rebasedStakedCelo.totalSupply();
        assertTrue(currentSupply > initialSupply);
    }

    // =========================================================================
    //                          #balanceOf() tests
    // =========================================================================

    function _balanceOfSetup() internal {
        mockAccount.setTotalCelo(400);
        mockStakedCelo.mint(alice, 100);
        mockStakedCelo.mint(bob, 100);
        mockStakedCelo.mint(someone, 200);

        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(bob);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(bob);
        rebasedStakedCelo.deposit(100);
    }

    function test_balanceOf_lessCelo_shouldDecreaseRstCeloBalance() public {
        _balanceOfSetup();
        uint256 initialBalance = rebasedStakedCelo.balanceOf(bob);
        mockAccount.setTotalCelo(200);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertTrue(bobBalance < initialBalance);
    }

    function test_balanceOf_equalCelo_shouldNotChangeRstCeloBalance() public {
        _balanceOfSetup();
        uint256 initialBalance = rebasedStakedCelo.balanceOf(bob);
        mockAccount.setTotalCelo(400);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertEq(bobBalance, initialBalance);
    }

    function test_balanceOf_moreCelo_shouldIncreaseRstCeloBalance() public {
        _balanceOfSetup();
        uint256 initialBalance = rebasedStakedCelo.balanceOf(bob);
        mockAccount.setTotalCelo(800);
        uint256 bobBalance = rebasedStakedCelo.balanceOf(bob);
        assertTrue(bobBalance > initialBalance);
    }

    // =========================================================================
    //                          #setPauser tests
    // =========================================================================

    function test_setPauser_setsPauserAddressToOwner() public {
        vm.prank(owner);
        rebasedStakedCelo.setPauser();
        address newPauser = rebasedStakedCelo.pauser();
        assertEq(newPauser, owner);
    }

    function test_setPauser_emitsPauserSetEvent() public {
        vm.expectEmit(true, true, true, true);
        emit PauserSet(owner);
        vm.prank(owner);
        rebasedStakedCelo.setPauser();
    }

    function test_setPauser_cannotBeCalledByNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(someone);
        rebasedStakedCelo.setPauser();
    }

    function test_setPauser_whenOwnerChanged_setsPauserToNewOwner() public {
        vm.prank(owner);
        rebasedStakedCelo.transferOwnership(someone);

        vm.prank(someone);
        rebasedStakedCelo.setPauser();
        address newPauser = rebasedStakedCelo.pauser();
        assertEq(newPauser, someone);
    }

    // =========================================================================
    //                          #pause tests
    // =========================================================================

    function test_pause_canBeCalledByPauser() public {
        vm.prank(pauser);
        rebasedStakedCelo.pause();
        assertTrue(rebasedStakedCelo.isPaused());
    }

    function test_pause_emitsContractPausedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ContractPaused();
        vm.prank(pauser);
        rebasedStakedCelo.pause();
    }

    function test_pause_cannotBeCalledByRandomAccount() public {
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(someone);
        rebasedStakedCelo.pause();
        assertFalse(rebasedStakedCelo.isPaused());
    }

    // =========================================================================
    //                          #unpause tests
    // =========================================================================

    function test_unpause_canBeCalledByPauser() public {
        vm.prank(pauser);
        rebasedStakedCelo.pause();

        vm.prank(pauser);
        rebasedStakedCelo.unpause();
        assertFalse(rebasedStakedCelo.isPaused());
    }

    function test_unpause_emitsContractUnpausedEvent() public {
        vm.prank(pauser);
        rebasedStakedCelo.pause();

        vm.expectEmit(true, true, true, true);
        emit ContractUnpaused();
        vm.prank(pauser);
        rebasedStakedCelo.unpause();
    }

    function test_unpause_cannotBeCalledByRandomAccount() public {
        vm.prank(pauser);
        rebasedStakedCelo.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(someone);
        rebasedStakedCelo.unpause();
        assertTrue(rebasedStakedCelo.isPaused());
    }

    // =========================================================================
    //                          when paused tests
    // =========================================================================

    function _pausedSetup() internal {
        mockStakedCelo.mint(alice, 100);
        vm.prank(alice);
        mockStakedCelo.approve(address(rebasedStakedCelo), 100);
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
        vm.prank(alice);
        rebasedStakedCelo.approve(bob, 1);

        vm.prank(pauser);
        rebasedStakedCelo.pause();
    }

    function test_whenPaused_cantCallDeposit() public {
        _pausedSetup();
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(alice);
        rebasedStakedCelo.deposit(100);
    }

    function test_whenPaused_cantCallWithdraw() public {
        _pausedSetup();
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(alice);
        rebasedStakedCelo.withdraw(100);
    }

    function test_whenPaused_cantCallTransfer() public {
        _pausedSetup();
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(alice);
        rebasedStakedCelo.transfer(bob, 1);
    }

    function test_whenPaused_cantCallApprove() public {
        _pausedSetup();
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(alice);
        rebasedStakedCelo.approve(bob, 1);
    }

    function test_whenPaused_cantCallTransferFrom() public {
        _pausedSetup();
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(bob);
        rebasedStakedCelo.transferFrom(alice, bob, 1);
    }

    function test_whenPaused_cantCallIncreaseAllowance() public {
        _pausedSetup();
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(alice);
        rebasedStakedCelo.increaseAllowance(bob, 1);
    }

    function test_whenPaused_cantCallDecreaseAllowance() public {
        _pausedSetup();
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(alice);
        rebasedStakedCelo.decreaseAllowance(bob, 1);
    }

    // =========================================================================
    //                          Events
    // =========================================================================

    event StakedCeloDeposited(address indexed depositor, uint256 amount);
    event StakedCeloWithdrawn(address indexed withdrawer, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event PauserSet(address pauser);
    event ContractPaused();
    event ContractUnpaused();
}
