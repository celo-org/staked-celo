// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/deploy/TestAccountDeployHelper.sol";
import "./helpers/ValidatorHelper.sol";

/// @dev Extended MockValidators with getValidatorGroup support.
///      The standard MockValidators doesn't implement IValidators.getValidatorGroup,
///      which is needed by GroupHealth._isGroupPartiallyValid().
///      This contract adds that function with proper slashing multiplier tracking.
contract GroupHealthTestValidators {
    uint256 private constant FIXED1_UINT = 1000000000000000000000000;

    mapping(address => bool) public isValidator;
    mapping(address => bool) public isValidatorGroup;
    mapping(address => address[]) private _members;
    mapping(address => address) private _affiliations;
    mapping(address => uint256) private _slashingMultiplier;

    function setValidatorGroup(address group) external {
        isValidatorGroup[group] = true;
        if (_slashingMultiplier[group] == 0) {
            _slashingMultiplier[group] = FIXED1_UINT;
        }
    }

    function setValidator(address account) external {
        isValidator[account] = true;
    }

    function affiliate(address group) external returns (bool) {
        _affiliations[msg.sender] = group;
        return true;
    }

    function setMembers(address group, address[] calldata members) external {
        _members[group] = members;
    }

    function getGroupNumMembers(address group) public view returns (uint256) {
        return _members[group].length;
    }

    // Required by GroupHealth._isGroupPartiallyValid via IValidators interface
    function getValidatorGroup(address group)
        external
        view
        returns (
            address[] memory,
            uint256,
            uint256,
            uint256,
            uint256[] memory,
            uint256,
            uint256
        )
    {
        return (_members[group], 0, 0, 0, new uint256[](0), _slashingMultiplier[group], 0);
    }

    function halveSlashingMultiplier(address group) external {
        _slashingMultiplier[group] = _slashingMultiplier[group] / 2;
    }

    function deregisterValidatorGroup(uint256) external returns (bool) {
        isValidatorGroup[msg.sender] = false;
        return true;
    }

    function addSlasher(string calldata) external {
        // no-op, matches MockLockedGold pattern
    }
}

/// @dev Extended accounts mock with getValidatorSigner.
///      The standard MockAccountsCelo (from TestAccountDeployHelper) only has createAccount().
///      GroupHealth._isGroupPartiallyValid() also needs getValidatorSigner(address).
contract GroupHealthTestAccounts {
    function createAccount() external pure returns (bool) {
        return true;
    }

    function getValidatorSigner(address account) external pure returns (address) {
        return account;
    }

    function isAccount(address) external pure returns (bool) {
        return true;
    }
}

contract GroupHealthTest is TestAccountDeployHelper, ValidatorHelper {
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

    address nonManager;
    address _pauser;
    address _mockSlasher;

    address[] groups;
    address[] activatedGroups;
    address[] activatedGroupAddresses;
    address[] allGroupAddresses;
    address[] allValidators;
    address[] allValidatorAddresses;

    // Extended mocks
    GroupHealthTestValidators ghValidators;
    GroupHealthTestAccounts ghAccounts;

    // =========================================================================
    //                          SETUP
    // =========================================================================

    function setUp() public {
        // Deploy base fixture (MockGroupHealth + MockValidators + MockElection + MockLockedGold)
        deployTestGroupHealth();

        // Deploy extended mocks with getValidatorGroup + getValidatorSigner
        ghValidators = new GroupHealthTestValidators();
        ghAccounts = new GroupHealthTestAccounts();

        // Re-register extended mocks in MockRegistry
        address registryOwner = IMockRegistryForValidator(mockRegistryAddr).owner();
        vm.startPrank(registryOwner);
        IRegistry(mockRegistryAddr).setAddressFor("Validators", address(ghValidators));
        IRegistry(mockRegistryAddr).setAddressFor("Accounts", address(ghAccounts));
        vm.stopPrank();

        // Update mockValidators reference for ValidatorHelper compatibility
        mockValidators = MockValidators(address(ghValidators));

        // Set up test accounts
        (nonManager, ) = randomSigner(100 ether);
        (_mockSlasher, ) = randomSigner(100 ether);
        _pauser = owner;

        // Register 10 groups with 3 validators each
        uint256 validatorMembers = 3;
        for (uint256 i = 0; i < 10; i++) {
            (address group, ) = randomSigner(11000 ether * validatorMembers);
            groups.push(group);
            if (i < 3) {
                activatedGroupAddresses.push(group);
                activatedGroups.push(group);
            }
            allGroupAddresses.push(group);

            registerValidatorGroup(mockValidators, mockLockedGold, group, validatorMembers);

            for (uint256 j = 0; j < validatorMembers; j++) {
                (address validator, ) = randomSigner(11000 ether);
                allValidators.push(validator);
                allValidatorAddresses.push(validator);
                registerValidatorAndAddToGroupMembers(mockValidators, mockLockedGold, group, validator);
            }

            vm.prank(owner);
            mockGroupHealth.setPauser();
        }
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

    /// @dev Elect activated groups and update health.
    function _electAndUpdateActivatedGroups() internal {
        electMockValidatorGroupsAndUpdate(
            mockValidators,
            address(mockGroupHealth),
            activatedGroupAddresses,
            false,
            true
        );
    }

    /// @dev Set up groups as valid: elect + update for all activated groups.
    function _setupValidGroups() internal {
        _electAndUpdateActivatedGroups();
    }

    /// @dev Elect first activated group without updating health. Returns mockedIndexes.
    function _electFirstGroupNoUpdate() internal returns (uint256[] memory) {
        return electMockValidatorGroupsAndUpdate(
            mockValidators,
            address(mockGroupHealth),
            _toArray(activatedGroupAddresses[0]),
            false,
            false
        );
    }

    /// @dev Make a group valid, then set up for markGroupHealthy tests.
    function _setupForUpdateGroupHealth() internal {
        electMockValidatorGroupsAndUpdate(
            mockValidators,
            address(mockGroupHealth),
            activatedGroupAddresses,
            false,
            false
        );
    }

    /// @dev Shorthand for revokeElectionOnMockValidatorGroupsAndUpdate.
    function _revokeElection(address[] memory validatorGroups, bool update) internal {
        revokeElectionOnMockValidatorGroupsAndUpdate(
            IValidators(address(ghValidators)),
            IAccounts(address(ghAccounts)),
            mockGroupHealth,
            validatorGroups,
            update
        );
    }

    /// @dev Shorthand for updateGroupSlashingMultiplier.
    function _slashGroup(address group) internal {
        updateGroupSlashingMultiplier(
            mockRegistryAddr,
            mockLockedGold,
            mockValidators,
            group,
            _mockSlasher
        );
    }

    // =========================================================================
    //                  #isGroupValid()
    // =========================================================================

    // Test 1
    function test_isGroupValid_ShouldReturnInvalidWhenNotUpdated() public {
        bool valid = mockGroupHealth.isGroupValid(nonManager);
        assertFalse(valid);
    }

    // Test 2: When validity updated (invalid) → should return invalid
    function test_isGroupValid_WhenUpdatedInvalid_ShouldReturnInvalid() public {
        // Setup: set 150 elected validators to nonManager
        for (uint256 i = 0; i < 150; i++) {
            mockGroupHealth.setElectedValidator(i, nonManager);
        }
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);

        bool valid = mockGroupHealth.isGroupValid(nonManager);
        assertFalse(valid);
    }

    // Test 3: When valid group and updated → should be valid
    function test_isGroupValid_WhenValidAndUpdated_ShouldBeValid() public {
        // Setup: invalid election + valid election
        for (uint256 i = 0; i < 150; i++) {
            mockGroupHealth.setElectedValidator(i, nonManager);
        }
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);

        _electAndUpdateActivatedGroups();

        bool valid = mockGroupHealth.isGroupValid(activatedGroupAddresses[0]);
        assertTrue(valid);
    }

    // Test 4: Next epoch, updated to valid → should return valid
    function test_isGroupValid_NextEpoch_UpdatedToValid_ShouldReturnValid() public {
        // Setup: invalid election + valid election
        for (uint256 i = 0; i < 150; i++) {
            mockGroupHealth.setElectedValidator(i, nonManager);
        }
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
        _electAndUpdateActivatedGroups();

        // Mine to next epoch
        mineToNextEpoch();

        // Re-elect first group and update
        electMockValidatorGroupsAndUpdate(
            mockValidators,
            address(mockGroupHealth),
            _toArray(activatedGroupAddresses[0]),
            false,
            true
        );

        bool valid = mockGroupHealth.isGroupValid(activatedGroupAddresses[0]);
        assertTrue(valid);
    }

    // Test 5: Next epoch, updated to invalid → should return invalid
    function test_isGroupValid_NextEpoch_UpdatedToInvalid_ShouldReturnInvalid() public {
        // Setup: invalid election + valid election
        for (uint256 i = 0; i < 150; i++) {
            mockGroupHealth.setElectedValidator(i, nonManager);
        }
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
        _electAndUpdateActivatedGroups();

        // Mine to next epoch
        mineToNextEpoch();

        // Revoke election for first group and update
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

        _slashGroup(activatedGroups[0]);

        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit GroupHealthUpdated(activatedGroupAddresses[0], false);
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
    }

    // Test 8: Should update to invalid when no members
    function test_updateGroupHealth_Valid_ShouldUpdateToInvalidWhenNoMembers() public {
        _setupForUpdateGroupHealth();
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
        assertTrue(mockGroupHealth.isGroupValid(activatedGroupAddresses[0]));

        removeMembersFromGroup(mockValidators, activatedGroups[0]);

        vm.expectEmit(true, true, true, true, address(mockGroupHealth));
        emit GroupHealthUpdated(activatedGroupAddresses[0], false);
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
    }

    // Test 9: Should update to invalid when group not registered
    function test_updateGroupHealth_Valid_ShouldUpdateToInvalidWhenNotRegistered() public {
        _setupForUpdateGroupHealth();
        mockGroupHealth.updateGroupHealth(activatedGroupAddresses[0]);
        assertTrue(mockGroupHealth.isGroupValid(activatedGroupAddresses[0]));

        deregisterValidatorGroup(mockValidators, activatedGroups[0]);

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
        uint256[] memory mockedIndexes = electMockValidatorGroupsAndUpdate(
            mockValidators,
            address(mockGroupHealth),
            activatedGroupAddresses,
            false,
            true
        );

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

        _slashGroup(activatedGroups[0]);

        mockGroupHealth.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));
    }

    // Test 15: Should not update group to healthy when group not validator group
    function test_markGroupHealthy_ShouldNotUpdateWhenNotValidatorGroup() public {
        uint256[] memory mockedIndexes = _electFirstGroupNoUpdate();
        assertFalse(mockGroupHealth.isGroupValid(allGroupAddresses[0]));

        deregisterValidatorGroup(mockValidators, activatedGroups[0]);

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

        removeMembersFromGroup(mockValidators, activatedGroups[0]);

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
