// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./MultiSigTestBase.sol";

/**
 * @notice Port of the CELO-receiving and pause-related blocks of `describe("MultiSig")`:
 *         `#fallback function`, `#setPauser()`, `#pauseContracts()`, `#unpauseContracts()`
 *         and `when paused`.
 */
contract MultiSigFallbackAndPausableTest is MultiSigTestBase {
    /// @dev topics[0] of `CeloDeposited(address indexed sender, uint256 value)`.
    bytes32 internal constant CELO_DEPOSITED_TOPIC = keccak256("CeloDeposited(address,uint256)");

    // =========================================================================
    //                    #fallback function (2)
    // =========================================================================

    function test_Fallback_WhenReceivingCeloEmitsDepositEvent() public {
        uint256 value = 100;
        vm.deal(owner1, value);

        vm.expectEmit(true, false, false, true, address(multiSig));
        emit CeloDeposited(owner1, value);

        vm.prank(owner1);
        (bool ok,) = address(multiSig).call{value: value}("");
        assertTrue(ok);
    }

    function test_Fallback_WhenReceiving0ValueDoesNotEmitEvent() public {
        // Send 0 value: the tx succeeds and no CeloDeposited event is emitted.
        IVmExt(address(vm)).recordLogs();

        vm.prank(owner1);
        (bool ok,) = address(multiSig).call{value: 0}("");
        assertTrue(ok);

        IVmExt.Log[] memory logs = IVmExt(address(vm)).getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            assertNotEq(uint256(logs[i].topics[0]), uint256(CELO_DEPOSITED_TOPIC));
        }
    }

    // =========================================================================
    //                       #setPauser (4)
    // =========================================================================

    function test_SetPauser_AllowsMultiSigToSetPauser() public {
        bytes memory payload = abi.encodeWithSelector(IMultiSigFull.setPauser.selector, nonOwner);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(payload),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.pauser(), nonOwner);
    }

    function test_SetPauser_AllowsMultiSigToSetItselfAsPauser() public {
        bytes memory payload =
            abi.encodeWithSelector(IMultiSigFull.setPauser.selector, address(multiSig));
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(payload),
            delay,
            owner1,
            owner2
        );
        assertEq(msig.pauser(), address(multiSig));
    }

    function test_SetPauser_DoesNotAllowOwnerToSetPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, owner1)
        );
        vm.prank(owner1);
        msig.setPauser(nonOwner);
    }

    function test_SetPauser_DoesNotAllowNonOwnerToSetPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMultiSigErrors.SenderMustBeMultisigWallet.selector, nonOwner)
        );
        vm.prank(nonOwner);
        msig.setPauser(nonOwner);
    }

    // =========================================================================
    //                     #pauseContracts (6)
    // =========================================================================

    function test_PauseContracts_CanBeCalledByOwner() public {
        vm.prank(owner1);
        msig.pauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_PauseContracts_CanBeCalledByOwnerToPauseMultisig() public {
        // Set MultiSig as its own pauser (impersonate wallet)
        vm.prank(address(multiSig));
        msig.setPauser(address(multiSig));

        vm.prank(owner1);
        msig.pauseContracts(_singleAddress(address(multiSig)));
        assertTrue(msig.isPaused());
    }

    function test_PauseContracts_CanBeCalledByDifferentOwner() public {
        vm.prank(owner2);
        msig.pauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_PauseContracts_CanBeCalledByGovernance() public {
        vm.prank(address(mockGovernance));
        msig.pauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_PauseContracts_RevertsWhenMultiSigPauserIsNotMultiSig() public {
        // Set governance as pauser (not multisig itself)
        vm.prank(address(multiSig));
        msig.setPauser(address(mockGovernance));

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.OnlyPauser.selector));
        vm.prank(owner1);
        msig.pauseContracts(_singleAddress(address(multiSig)));
        // Kept verbatim from the original: the reverted call targeted the MultiSig, so
        // PausableTest was never in scope and this assertion is a tautology.
        assertFalse(pausableTest.isPaused());
    }

    function test_PauseContracts_RevertsWhenCalledByNonOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernanceOrOwner.selector, nonOwner)
        );
        vm.prank(nonOwner);
        msig.pauseContracts(_singleAddress(address(pausableTest)));
        // Kept verbatim from the original: the call above reverted, so PausableTest was
        // never paused and this assertion is a tautology.
        assertFalse(pausableTest.isPaused());
    }

    // =========================================================================
    //                    #unpauseContracts (4)
    // =========================================================================

    function _pausePausableTest() internal {
        vm.prank(owner1);
        msig.pauseContracts(_singleAddress(address(pausableTest)));
    }

    function test_UnpauseContracts_CanBeCalledByGovernance() public {
        _pausePausableTest();
        vm.prank(address(mockGovernance));
        msig.unpauseContracts(_singleAddress(address(pausableTest)));
        assertFalse(pausableTest.isPaused());
    }

    function test_UnpauseContracts_RevertsWhenCalledByOwner() public {
        _pausePausableTest();
        vm.expectRevert(
            abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, owner1)
        );
        vm.prank(owner1);
        msig.unpauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_UnpauseContracts_RevertsWhenCalledByMultiSig() public {
        _pausePausableTest();
        vm.expectRevert(
            abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, address(multiSig))
        );
        vm.prank(address(multiSig));
        msig.unpauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    function test_UnpauseContracts_RevertsWhenCalledByNonOwner() public {
        _pausePausableTest();
        vm.expectRevert(
            abi.encodeWithSelector(IMultiSigErrors.SenderNotGovernance.selector, nonOwner)
        );
        vm.prank(nonOwner);
        msig.unpauseContracts(_singleAddress(address(pausableTest)));
        assertTrue(pausableTest.isPaused());
    }

    // =========================================================================
    //                      when paused (4)
    // =========================================================================

    function _setupPaused() internal returns (uint256 submittedProposal) {
        // Submit a proposal (confirmed only by owner1, not fully confirmed)
        submittedProposal =
            _submitProposal(owner1, _singleAddress(nonOwner), _singleUint(0), _singleBytes(hex""));

        // Set mockPauserAddr as the pauser via multisig proposal
        bytes memory txData =
            abi.encodeWithSelector(IMultiSigFull.setPauser.selector, mockPauserAddr);
        _executeMultisigProposal(
            msig,
            _singleAddress(address(multiSig)),
            _singleUint(0),
            _singleBytes(txData),
            delay,
            owner1,
            owner2
        );

        // Pause the multisig
        vm.prank(mockPauserAddr);
        msig.pause();
    }

    function test_WhenPaused_CantCallSubmitProposal() public {
        _setupPaused();

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.Paused.selector));
        vm.prank(owner1);
        msig.submitProposal(_singleAddress(nonOwner), _singleUint(0), _singleBytes(hex""));
    }

    function test_WhenPaused_CantCallConfirmProposal() public {
        uint256 submittedProposal = _setupPaused();

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.Paused.selector));
        vm.prank(owner2);
        msig.confirmProposal(submittedProposal);
    }

    function test_WhenPaused_CantCallScheduleProposal() public {
        uint256 submittedProposal = _setupPaused();

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.Paused.selector));
        vm.prank(owner2);
        msig.scheduleProposal(submittedProposal);
    }

    function test_WhenPaused_CantCallExecuteProposal() public {
        uint256 submittedProposal = _setupPaused();

        vm.expectRevert(abi.encodeWithSelector(IMultiSigErrors.Paused.selector));
        vm.prank(owner2);
        msig.executeProposal(submittedProposal);
    }
}
