// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/DevchainHelper.sol";
import "./helpers/deploy/TestAccountDeployHelper.sol";

/// @dev Group size configuration of the real Celo Validators contract. Declared locally because
///      `ICeloValidators` in `DevchainHelper` only covers what the other suites need.
interface ICeloValidatorsMaxGroupSize {
    function maxGroupSize() external view returns (uint256);

    function setMaxGroupSize(uint256 size) external returns (bool);
}

/**
 * @title GroupHealthTest
 * @notice Port of the Hardhat era test-ts/group-health.test.ts (`describe("GroupHealth")`).
 * @dev Ports the `before()` hook of the TypeScript suite: ten validator groups with three
 *      validators each are registered against the real Celo core contracts of the devchain and
 *      MockGroupHealth is deployed against the devchain registry. The original pulled
 *      MockGroupHealth out of the "FullTestManager" Hardhat fixture; `deploy/test/group_health.ts`
 *      is tagged for both fixtures, so `deployTestGroupHealth(REGISTRY_ADDRESS)` deploys the very
 *      same contract and nothing else of that fixture is touched by this suite.
 *
 *      `setUp()` runs before every test, which is what the `evm_snapshot` / `evm_revert` pair of
 *      the original did. Nested `beforeEach` blocks become `_setUp...()` helpers.
 */
contract GroupHealthTest is TestAccountDeployHelper, DevchainHelper {
    // =========================================================================
    //                          EVENTS (for vm.expectEmit)
    // =========================================================================

    event GroupHealthUpdated(address group, bool healthy);
    event PauserSet(address pauser);
    event ContractPaused();
    event ContractUnpaused();

    // =========================================================================
    //                          TEST STATE
    // =========================================================================

    address internal nonManager;
    address internal _pauser;
    address internal _mockSlasher;

    address[] internal activatedGroupAddresses;
    address[] internal allGroupAddresses;
    address[] internal allValidatorAddresses;

    /// @dev Members per validator group, as in the original `validatorMembers = 3`.
    uint256 internal constant VALIDATOR_MEMBERS = 3;

    // =========================================================================
    //                          SETUP
    // =========================================================================

    function setUp() public {
        loadDevchain();

        (nonManager,) = randomSigner(100 ether);
        (_mockSlasher,) = randomSigner(100 ether);

        deployTestGroupHealth(REGISTRY_ADDRESS);
        _pauser = owner;

        _raiseMaxGroupSize(VALIDATOR_MEMBERS);
        _registerGroups();

        // The original repeated this inside the group loop; the resulting state is the same.
        vm.prank(owner);
        mockGroupHealth.setPauser();
    }

    /// @dev Ambiguous because both CeloTestHelper and DevchainHelper define it.
    function mineToNextEpoch() internal override(CeloTestHelper, DevchainHelper) {
        super.mineToNextEpoch();
    }

    /// @dev Ambiguous because both CeloTestHelper and DevchainHelper define it.
    function currentEpochNumber()
        internal
        view
        override(CeloTestHelper, DevchainHelper)
        returns (uint256)
    {
        return super.currentEpochNumber();
    }

    /// @dev Ten validator groups with three validators each; the first three are the
    ///      `activatedGroups` of the original.
    function _registerGroups() private {
        for (uint256 i = 0; i < 10; i++) {
            (address group,) = randomSigner(11_000 ether * VALIDATOR_MEMBERS);
            allGroupAddresses.push(group);
            if (i < 3) {
                activatedGroupAddresses.push(group);
            }

            registerValidatorGroup(group, VALIDATOR_MEMBERS);

            for (uint256 j = 0; j < VALIDATOR_MEMBERS; j++) {
                address validator = createWallet(11_000 ether);
                allValidatorAddresses.push(validator);
                registerValidatorAndAddToGroupMembers(group, validator);
            }
        }
    }

    /**
     * @dev Deviation: the anvil devchain caps a validator group at two members, while the ganache
     *      devchain the Hardhat suite ran against allowed more. The cap is raised on the real
     *      Validators contract so the groups really have the three members the original
     *      registers.
     */
    function _raiseMaxGroupSize(uint256 size) private {
        ICeloValidatorsMaxGroupSize groupSize = ICeloValidatorsMaxGroupSize(address(celoValidators));
        if (groupSize.maxGroupSize() >= size) {
            return;
        }
        address validatorsOwner = celoValidators.owner();
        vm.prank(validatorsOwner);
        groupSize.setMaxGroupSize(size);
    }

    // =========================================================================
    //                      INTERNAL HELPERS
    // =========================================================================

    /// @dev Wraps single address into a memory array.
    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    /// @dev `electMockValidatorGroupsAndUpdate(validatorsWrapper, gh, activatedGroupAddresses)`.
    function _electAndUpdateActivatedGroups() internal {
        electMockValidatorGroupsAndUpdate(mockGroupHealth, activatedGroupAddresses);
    }

    /// @dev Elect first activated group without updating health. Returns mockedIndexes.
    function _electFirstGroupNoUpdate() internal returns (uint256[] memory) {
        return electMockValidatorGroupsAndUpdate(
            mockGroupHealth, _toArray(activatedGroupAddresses[0]), false, false, true
        );
    }

    /// @dev `electMockValidatorGroupsAndUpdate(..., activatedGroupAddresses, false, false)`.
    function _setupForUpdateGroupHealth() internal {
        electMockValidatorGroupsAndUpdate(
            mockGroupHealth, activatedGroupAddresses, false, false, true
        );
    }

    /// @dev The `beforeEach` of `describe("When validity updated (invalid)")`.
    function _setUpValidityUpdatedInvalid() internal {
        for (uint256 i = 0; i < 150; i++) {
            mockGroupHealth.setElectedValidator(i, nonManager);
        }
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
    }

    /// @dev Shorthand for revokeElectionOnMockValidatorGroupsAndUpdate.
    function _revokeElection(address[] memory validatorGroups, bool update) internal {
        revokeElectionOnMockValidatorGroupsAndUpdate(mockGroupHealth, validatorGroups, update);
    }

    /// @dev Shorthand for updateGroupSlashingMultiplier.
    function _slashGroup(address group) internal {
        updateGroupSlashingMultiplier(group, _mockSlasher);
    }

    // =========================================================================
    //                  #isGroupValid()
    // =========================================================================

    // Test 1
    function test_isGroupValid_ShouldReturnInvalidWhenNotUpdated() public {
        bool valid = mockGroupHealth.isGroupValid(nonManager);
        assertFalse(valid);
    }

    // Test 2: When validity updated (invalid) -> should return invalid
    function test_isGroupValid_WhenUpdatedInvalid_ShouldReturnInvalid() public {
        _setUpValidityUpdatedInvalid();

        // The original asserted the untouched nonManager address; kept, and the group whose
        // health was actually updated with unelected members is asserted as well.
        bool valid = mockGroupHealth.isGroupValid(nonManager);
        assertFalse(valid);
        assertFalse(mockGroupHealth.isGroupValid(activatedGroupAddresses[0]));
    }

    // Test 3: When valid group and updated -> should be valid
    function test_isGroupValid_WhenValidAndUpdated_ShouldBeValid() public {
        _setUpValidityUpdatedInvalid();
        _electAndUpdateActivatedGroups();

        bool valid = mockGroupHealth.isGroupValid(activatedGroupAddresses[0]);
        assertTrue(valid);
    }

    // Test 4: Next epoch, updated to valid -> should return valid
    function test_isGroupValid_NextEpoch_UpdatedToValid_ShouldReturnValid() public {
        _setUpValidityUpdatedInvalid();
        _electAndUpdateActivatedGroups();

        mineToNextEpoch();

        electMockValidatorGroupsAndUpdate(mockGroupHealth, _toArray(activatedGroupAddresses[0]));

        bool valid = mockGroupHealth.isGroupValid(activatedGroupAddresses[0]);
        assertTrue(valid);
    }

    // Test 5: Next epoch, updated to invalid -> should return invalid
    function test_isGroupValid_NextEpoch_UpdatedToInvalid_ShouldReturnInvalid() public {
        _setUpValidityUpdatedInvalid();
        _electAndUpdateActivatedGroups();

        mineToNextEpoch();

        _revokeElection(_toArray(activatedGroupAddresses[0]), true);

        bool valid = mockGroupHealth.isGroupValid(activatedGroupAddresses[0]);
        assertFalse(valid);
    }

    // =========================================================================
    //                  #updateGroupHealth()
    // =========================================================================

    // Test 6: Should update to valid
    function test_updateGroupHealth_ShouldUpdateToValid() public {
        _setupForUpdateGroupHealth();

        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit GroupHealthUpdated(activatedGroupAddresses[0], true);
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
    }

    // Test 7: Should update to invalid when slashed
    function test_updateGroupHealth_Valid_ShouldUpdateToInvalidWhenSlashed() public {
        _setupForUpdateGroupHealth();
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
        assertTrue(mockGroupHealth.isGroupValid(activatedGroupAddresses[0]));

        _slashGroup(activatedGroupAddresses[0]);

        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit GroupHealthUpdated(activatedGroupAddresses[0], false);
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
    }

    // Test 8: Should update to invalid when no members
    function test_updateGroupHealth_Valid_ShouldUpdateToInvalidWhenNoMembers() public {
        _setupForUpdateGroupHealth();
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
        assertTrue(mockGroupHealth.isGroupValid(activatedGroupAddresses[0]));

        removeMembersFromGroup(activatedGroupAddresses[0]);

        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit GroupHealthUpdated(activatedGroupAddresses[0], false);
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
    }

    // Test 9: Should update to invalid when group not registered
    function test_updateGroupHealth_Valid_ShouldUpdateToInvalidWhenNotRegistered() public {
        _setupForUpdateGroupHealth();
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
        assertTrue(mockGroupHealth.isGroupValid(activatedGroupAddresses[0]));

        deregisterValidatorGroup(activatedGroupAddresses[0]);

        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit GroupHealthUpdated(activatedGroupAddresses[0], false);
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
    }

    // Test 10: Should update to invalid when group not elected
    function test_updateGroupHealth_Valid_ShouldUpdateToInvalidWhenNotElected() public {
        _setupForUpdateGroupHealth();
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
        assertTrue(mockGroupHealth.isGroupValid(activatedGroupAddresses[0]));

        _revokeElection(_toArray(activatedGroupAddresses[0]), false);

        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit GroupHealthUpdated(activatedGroupAddresses[0], false);
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
    }

    // =========================================================================
    //                  #markGroupHealthy()
    // =========================================================================

    // Test 11: Reverts when group is already healthy
    function test_markGroupHealthy_RevertsWhenGroupAlreadyHealthy() public {
        uint256[] memory mockedIndexes =
            electMockValidatorGroupsAndUpdate(mockGroupHealth, activatedGroupAddresses);

        vm.expectRevert(
            abi.encodeWithSelector(GroupHealth.GroupHealthy.selector, activatedGroupAddresses[0])
        );
        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
    }

    // Test 12: Should revert when wrong index length provided
    function test_markGroupHealthy_RevertsWhenWrongIndexLength() public {
        uint256[] memory emptyIndexes = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(GroupHealth.MembersLengthMismatch.selector));
        mockGroupHealth.markGroupHealthy(allGroupAddresses[0], emptyIndexes);
    }

    // Test 13: Should update group to healthy when correct indexes were provided
    function test_markGroupHealthy_ShouldUpdateToHealthyWithCorrectIndexes() public {
        uint256[] memory mockedIndexes = _electFirstGroupNoUpdate();
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));

        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        assertTrue(mockGroupHealth.isGroupValid(allGroupAddresses[0]));
    }

    // Test 14: Should not update group to healthy when group slashed
    function test_markGroupHealthy_ShouldNotUpdateWhenSlashed() public {
        uint256[] memory mockedIndexes = _electFirstGroupNoUpdate();
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));

        _slashGroup(activatedGroupAddresses[0]);

        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));
    }

    // Test 15: Should not update group to healthy when group not validator group
    function test_markGroupHealthy_ShouldNotUpdateWhenNotValidatorGroup() public {
        uint256[] memory mockedIndexes = _electFirstGroupNoUpdate();
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));

        deregisterValidatorGroup(activatedGroupAddresses[0]);

        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));
    }

    // Test 16: Should not update group to healthy when validator groups not elected
    function test_markGroupHealthy_ShouldNotUpdateWhenNotElected() public {
        uint256[] memory mockedIndexes = _electFirstGroupNoUpdate();
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));

        _revokeElection(_toArray(activatedGroupAddresses[0]), true);

        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));
    }

    // Test 17: Should not update group to healthy when no members
    function test_markGroupHealthy_ShouldNotUpdateWhenNoMembers() public {
        uint256[] memory mockedIndexes = _electFirstGroupNoUpdate();
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));

        removeMembersFromGroup(activatedGroupAddresses[0]);

        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));
    }

    // =========================================================================
    //                  #setPauser
    // =========================================================================

    // Test 18: Sets the pauser address to the owner of the contract
    function test_setPauser_SetsPauserToOwner() public {
        vm.prank(owner);
        mockGroupHealth.setPauser();
        address newPauser = mockGroupHealth.pauser();
        assertEq(newPauser, owner);
    }

    // Test 19: Emits a PauserSet event
    function test_setPauser_EmitsPauserSetEvent() public {
        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit PauserSet(owner);
        vm.prank(owner);
        mockGroupHealth.setPauser();
    }

    // Test 20: Cannot be called by a non-owner
    function test_setPauser_CannotBeCalledByNonOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonManager);
        mockGroupHealth.setPauser();
    }

    // Test 21: When the owner is changed, sets the pauser to the new owner
    function test_setPauser_WhenOwnerChanged_SetsPauserToNewOwner() public {
        vm.prank(owner);
        mockGroupHealth.transferOwnership(nonManager);

        vm.prank(nonManager);
        mockGroupHealth.setPauser();
        address newPauser = mockGroupHealth.pauser();
        assertEq(newPauser, nonManager);
    }

    // =========================================================================
    //                  #renounceOwnership
    // =========================================================================

    // Test 22: Reverts with RenounceOwnershipDisabled
    function test_renounceOwnership_RevertsWithRenounceOwnershipDisabled() public {
        vm.expectRevert(abi.encodeWithSelector(GroupHealth.RenounceOwnershipDisabled.selector));
        vm.prank(owner);
        mockGroupHealth.renounceOwnership();
    }

    // Test 23: Reverts for any caller
    function test_renounceOwnership_RevertsForAnyCaller() public {
        vm.expectRevert(abi.encodeWithSelector(GroupHealth.RenounceOwnershipDisabled.selector));
        vm.prank(nonManager);
        mockGroupHealth.renounceOwnership();
    }

    // =========================================================================
    //         #isGroupMemberElected (off-by-one fix)
    // =========================================================================

    // Test 24: Should not mark group healthy when index equals numberOfElectedValidators (boundary)
    function test_isGroupMemberElected_ShouldNotMarkHealthyWhenIndexEqualsBoundary() public {
        // Set up exactly 3 elected validators (indices 0, 1, 2)
        for (uint256 i = 0; i < 3; i++) {
            mockGroupHealth.setElectedValidator(i, allValidatorAddresses[i]);
        }

        // Use index 3 (equals numberOfValidators), which should be out of bounds
        // After the fix: if (index >= 3) correctly returns false for index=3
        uint256[] memory boundaryIndexes = new uint256[](3);
        boundaryIndexes[0] = 3;
        boundaryIndexes[1] = 3;
        boundaryIndexes[2] = 3;
        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], boundaryIndexes);

        // Group should remain invalid because the index is out of bounds
        bool valid = mockGroupHealth.isGroupValid(activatedGroupAddresses[0]);
        assertFalse(valid);
    }

    // Test 25: Should mark group healthy when index is within valid bounds
    function test_isGroupMemberElected_ShouldMarkHealthyWhenIndexWithinBounds() public {
        // Elect the validators from the activated group
        uint256[] memory mockedIndexes = _electFirstGroupNoUpdate();

        // Mark the group as healthy with valid indices
        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);

        // Group should be valid
        bool valid = mockGroupHealth.isGroupValid(activatedGroupAddresses[0]);
        assertTrue(valid);
    }

    // =========================================================================
    //                  #pause
    // =========================================================================

    // Test 26: Can be called by the pauser
    function test_pause_CanBeCalledByPauser() public {
        vm.prank(_pauser);
        mockGroupHealth.pause();
        bool isPaused = mockGroupHealth.isPaused();
        assertTrue(isPaused);
    }

    // Test 27: Emits a ContractPaused event
    function test_pause_EmitsContractPausedEvent() public {
        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit ContractPaused();
        vm.prank(_pauser);
        mockGroupHealth.pause();
    }

    // Test 28: Cannot be called by a random account
    function test_pause_CannotBeCalledByRandomAccount() public {
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonManager);
        mockGroupHealth.pause();

        bool isPaused = mockGroupHealth.isPaused();
        assertFalse(isPaused);
    }

    // =========================================================================
    //                  #unpause
    // =========================================================================

    // Test 29: Can be called by the pauser
    function test_unpause_CanBeCalledByPauser() public {
        vm.prank(_pauser);
        mockGroupHealth.pause();

        vm.prank(_pauser);
        mockGroupHealth.unpause();
        bool isPaused = mockGroupHealth.isPaused();
        assertFalse(isPaused);
    }

    // Test 30: Emits a ContractUnpaused event
    function test_unpause_EmitsContractUnpausedEvent() public {
        vm.prank(_pauser);
        mockGroupHealth.pause();

        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit ContractUnpaused();
        vm.prank(_pauser);
        mockGroupHealth.unpause();
    }

    // Test 31: Cannot be called by a random account
    function test_unpause_CannotBeCalledByRandomAccount() public {
        vm.prank(_pauser);
        mockGroupHealth.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonManager);
        mockGroupHealth.unpause();

        bool isPaused = mockGroupHealth.isPaused();
        assertTrue(isPaused);
    }

    // =========================================================================
    //                  when paused
    // =========================================================================

    // Test 32: Can't call updateGroupHealth
    function test_whenPaused_CantCallUpdateGroupHealth() public {
        vm.prank(_pauser);
        mockGroupHealth.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(nonManager);
        mockGroupHealth.updateGroupHealth(ADDRESS_ZERO);
    }

    // Test 33: Can't call markGroupHealthy
    function test_whenPaused_CantCallMarkGroupHealthy() public {
        vm.prank(_pauser);
        mockGroupHealth.pause();

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(nonManager);
        mockGroupHealth.markGroupHealthy(ADDRESS_ZERO, indexes);
    }
}
