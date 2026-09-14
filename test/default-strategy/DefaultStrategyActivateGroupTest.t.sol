// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./DefaultStrategyTestBase.sol";

/// @dev Group size configuration of the real Celo Validators contract. Declared locally because
///      `ICeloValidators` in `DevchainHelper` only covers what the other suites need.
interface ICeloValidatorsGroupSize {
    function maxGroupSize() external view returns (uint256);

    function setMaxGroupSize(uint256 size) external returns (bool);
}

/**
 * @title DefaultStrategyActivateGroupTest
 * @notice Ports the group lifecycle describe blocks of `test-ts/default-strategy.test.ts`:
 *         `#addActivatableGroup`, `#activateGroup()`, `#deactivateGroup()` and
 *         `#deactivateUnhealthyGroup()`.
 */
contract DefaultStrategyActivateGroupTest is DefaultStrategyTestBase {
    /// @dev `deactivatedGroup` of the original suite: groups[1].
    address internal deactivatedGroup;

    function setUp() public {
        _deployDefaultStrategyFixture();
        deactivatedGroup = groupAddresses[1];
    }

    // =========================================================================
    //                        #addActivatableGroup
    // =========================================================================

    function test_addActivatableGroup_RevertsWhenGroupNotHealthy() public {
        mockGroupHealth.setGroupValidity(groupAddresses[0], false);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.GroupNotEligible.selector, groupAddresses[0])
        );
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
    }

    function test_addActivatableGroup_AddsGroupToActivatable() public {
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
        assertEq(defaultStrategy.getActivatableGroupAt(0), groupAddresses[0]);
    }

    function test_addActivatableGroup_RevertsWhenAddingGroupTwice() public {
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.GroupAlreadyAdded.selector, groupAddresses[0])
        );
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
    }

    function test_addActivatableGroup_RevertsWhenAddingGroupThatIsAlreadyActive() public {
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
        mockDefaultStrategy.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.GroupAlreadyAdded.selector, groupAddresses[0])
        );
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
    }

    function test_addActivatableGroup_ShouldRevertWhenNotCalledByOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonOwner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
    }

    function test_addActivatableGroup_EmitsActivatableGroupAddedEvent() public {
        _expectEmitFrom(address(mockDefaultStrategy));
        emit ActivatableGroupAdded(groupAddresses[0]);
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
    }

    // =========================================================================
    //                          #activateGroup()
    // =========================================================================

    function test_activateGroup_CannotActivateNonActivatableGroup() public {
        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.GroupNotActivatable.selector, nonVote)
        );
        vm.prank(nonManager);
        mockDefaultStrategy.activateGroup(nonVote, ADDRESS_ZERO, ADDRESS_ZERO);
    }

    /// @dev `describe("When group is activatable")` beforeEach.
    function _setUpGroupIsActivatable() private {
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
        assertEq(defaultStrategy.getActivatableGroupAt(0), groupAddresses[0]);
    }

    function test_activateGroup_WhenGroupIsActivatable_AddsAGroup() public {
        _setUpGroupIsActivatable();

        mockDefaultStrategy.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);

        address[] memory activeGroups = getDefaultGroups(defaultStrategy);
        (address firstActiveGroup, ) = defaultStrategy.getGroupsHead();
        _assertArrayEq(activeGroups, _toArray(groupAddresses[0]));
        assertEq(defaultStrategy.getNumberOfGroups(), 1);
        assertEq(firstActiveGroup, groupAddresses[0]);
    }

    function test_activateGroup_WhenGroupIsActivatable_EmitsAGroupActivatedEvent() public {
        _setUpGroupIsActivatable();

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupActivated(groupAddresses[0]);
        mockDefaultStrategy.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_activateGroup_WhenGroupIsActivatable_ShouldRemoveGroupFromActivatable() public {
        _setUpGroupIsActivatable();

        mockDefaultStrategy.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);
        assertEq(defaultStrategy.activatableGroupsCount(), 0);
    }

    function test_activateGroup_WhenGroupIsNotHealthyRegistered_RevertsWhenTryingToAddAnUnregisteredGroup()
        public
    {
        (address unregisteredGroup, ) = randomSigner(100 ether);
        mockGroupHealth.setGroupValidity(unregisteredGroup, true);
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(unregisteredGroup);
        mockGroupHealth.setGroupValidity(unregisteredGroup, false);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.GroupNotEligible.selector, unregisteredGroup)
        );
        vm.prank(owner);
        mockDefaultStrategy.activateGroup(unregisteredGroup, ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_activateGroup_WhenSomeGroupsAreAlreadyAdded_AddsAnotherGroup() public {
        _activateGroupsFromHead(3);

        (address head, ) = defaultStrategy.getGroupsHead();
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[3]);
        mockDefaultStrategy.activateGroup(groupAddresses[3], ADDRESS_ZERO, head);

        address[] memory expected = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            expected[i] = groupAddresses[i];
        }
        _assertArrayEq(getDefaultGroups(defaultStrategy), expected);
    }

    function test_activateGroup_WhenSomeGroupsAreAlreadyAdded_EmitsAGroupActivatedEvent() public {
        _activateGroupsFromHead(3);

        (address head, ) = defaultStrategy.getGroupsHead();
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[3]);

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupActivated(groupAddresses[3]);
        mockDefaultStrategy.activateGroup(groupAddresses[3], ADDRESS_ZERO, head);
    }

    /// @dev `describe("When activating groups with preexisting celo in protocol")` beforeEach.
    function _setUpPreexistingCelo() private {
        mockAccount.setCeloForGroup(groupAddresses[0], 100);
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
        mockDefaultStrategy.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_activateGroup_WhenActivatingGroupsWithPreexistingCeloInProtocol_ShouldRevertWhenIncorrectLesserAndGreater()
        public
    {
        _setUpPreexistingCelo();

        mockAccount.setCeloForGroup(groupAddresses[1], 200);
        manager.deposit{value: 1 ether}();
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[1]);

        vm.expectRevert(bytes("get lesser and greater failure"));
        mockDefaultStrategy.activateGroup(groupAddresses[1], groupAddresses[0], ADDRESS_ZERO);
    }

    function test_activateGroup_WhenActivatingGroupsWithPreexistingCeloInProtocol_ShouldInsertWithCorrectLesserAndGreater()
        public
    {
        _setUpPreexistingCelo();

        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[1]);
        mockAccount.setCeloForGroup(groupAddresses[1], 200);
        vm.prank(owner);
        mockDefaultStrategy.activateGroup(groupAddresses[1], groupAddresses[0], ADDRESS_ZERO);

        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[1]), 0);
    }

    /// @dev `describe("when maxNumGroupsVotedFor have been voted for")` beforeEach.
    function _setUpMaxNumGroupsVotedFor() private {
        electGroup(groupAddresses[10], someone);
        _activateGroupsFromHead(10);
    }

    function test_activateGroup_WhenMaxNumGroupsVotedForHaveBeenVotedFor_CanAddAnotherGroupWhenEnabledInElectionContract()
        public
    {
        _setUpMaxNumGroupsVotedFor();

        updateMaxNumberOfGroups(address(mockAccount), true);

        (address head, ) = defaultStrategy.getGroupsHead();
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[10]);

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupActivated(groupAddresses[10]);
        vm.prank(owner);
        mockDefaultStrategy.activateGroup(groupAddresses[10], ADDRESS_ZERO, head);
    }

    /// @dev `describe("when some of the groups are currently deactivated")` beforeEach.
    function _setUpSomeGroupsDeactivated() private {
        _setUpMaxNumGroupsVotedFor();

        mockAccount.setCeloForGroup(groupAddresses[2], 100);
        for (uint256 i = 0; i < 10; i++) {
            manager.deposit{value: (i + 1) * 1000}();
        }
        mockAccount.setCeloForGroup(groupAddresses[7], 100);
    }

    function test_activateGroup_WhenMaxNumGroupsVotedForHaveBeenVotedFor_WhenSomeOfTheGroupsAreCurrentlyDeactivated_ReactivatesADeactivatedGroup()
        public
    {
        _setUpSomeGroupsDeactivated();

        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(groupAddresses[2]);
        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(groupAddresses[7]);

        (address head, ) = defaultStrategy.getGroupsHead();
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[2]);
        mockDefaultStrategy.activateGroup(groupAddresses[2], ADDRESS_ZERO, head);

        address[] memory activeGroups = getDefaultGroups(defaultStrategy);
        assertEq(activeGroups[8], groupAddresses[2]);
    }

    function test_activateGroup_WhenMaxNumGroupsVotedForHaveBeenVotedFor_WhenSomeOfTheGroupsAreCurrentlyDeactivated_EmitsAGroupActivatedEvent()
        public
    {
        _setUpSomeGroupsDeactivated();

        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(groupAddresses[2]);
        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(groupAddresses[7]);

        (address head, ) = defaultStrategy.getGroupsHead();
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[2]);

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupActivated(groupAddresses[2]);
        mockDefaultStrategy.activateGroup(groupAddresses[2], ADDRESS_ZERO, head);
    }

    // =========================================================================
    //                         #deactivateGroup()
    // =========================================================================

    /// @dev `describe("When 3 active groups") > describe("when the group is voted for")` beforeEach.
    function _setUpThreeActiveGroupsVotedFor() private {
        _activateGroupsFromHead(3);
        for (uint256 i = 0; i < 3; i++) {
            manager.deposit{value: 100}();
        }
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsVotedFor_RemovesTheGroupFromTheGroupsArray()
        public
    {
        _setUpThreeActiveGroupsVotedFor();

        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(deactivatedGroup);

        address[] memory expected = new address[](2);
        expected[0] = groupAddresses[0];
        expected[1] = groupAddresses[2];
        _assertSameMembers(getDefaultGroups(defaultStrategy), expected);
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsVotedFor_RevertsWhenDeprecatingANonActiveGroup()
        public
    {
        _setUpThreeActiveGroupsVotedFor();

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.GroupNotActive.selector, groupAddresses[3])
        );
        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(groupAddresses[3]);
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsVotedFor_CannotBeCalledByANonOwner()
        public
    {
        _setUpThreeActiveGroupsVotedFor();

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonOwner);
        mockDefaultStrategy.deactivateGroup(deactivatedGroup);
    }

    /// @dev Shared body of the three "should schedule transfer to tail of default strategy" cases.
    function _assertScheduleTransferToTail() private {
        (address tail, ) = defaultStrategy.getGroupsTail();
        uint256 originalStCeloInTail = defaultStrategy.stCeloInGroup(tail);

        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(deactivatedGroup);

        assertEq(defaultStrategy.stCeloInGroup(deactivatedGroup), 0);
        assertEq(defaultStrategy.stCeloInGroup(tail), originalStCeloInTail + 100);
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsVotedFor_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsMoreCeloThanStCeloInTheSystem_ShouldScheduleTransferToTailOfDefaultStrategy()
        public
    {
        _setUpThreeActiveGroupsVotedFor();
        mockAccount.setTotalCelo(600);

        _assertScheduleTransferToTail();
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsVotedFor_WhenDifferentRatiosOfCeloVsStCelo_WhenThereIsLessCeloThanStCeloInTheSystem_ShouldScheduleTransferToTailOfDefaultStrategy()
        public
    {
        _setUpThreeActiveGroupsVotedFor();
        mockAccount.setTotalCelo(150);

        _assertScheduleTransferToTail();
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsVotedFor_ShouldScheduleTransferToTailOfDefaultStrategy()
        public
    {
        _setUpThreeActiveGroupsVotedFor();

        _assertScheduleTransferToTail();
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsNotVotedFor_RemovesTheGroupFromTheGroupsArray()
        public
    {
        _activateGroupsFromHead(3);

        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(deactivatedGroup);

        address[] memory expected = new address[](2);
        expected[0] = groupAddresses[0];
        expected[1] = groupAddresses[2];
        _assertArrayEq(getDefaultGroups(defaultStrategy), expected);
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsNotVotedFor_EmitsAGroupRemovedEvent()
        public
    {
        _activateGroupsFromHead(3);

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupRemoved(deactivatedGroup);
        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(deactivatedGroup);
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsNotVotedFor_RevertsWhenBelowMinCountOfActiveGroups()
        public
    {
        _activateGroupsFromHead(3);

        vm.prank(owner);
        mockDefaultStrategy.setMinCountOfActiveGroups(10);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.MinimumCountOfActiveGroupsReached.selector)
        );
        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(deactivatedGroup);
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsNotVotedFor_RevertsWhenDeprecatingANonActiveGroup()
        public
    {
        _activateGroupsFromHead(3);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.GroupNotActive.selector, groupAddresses[3])
        );
        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(groupAddresses[3]);
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsNotVotedFor_CannotBeCalledByANonOwner()
        public
    {
        _activateGroupsFromHead(3);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonOwner);
        mockDefaultStrategy.deactivateGroup(deactivatedGroup);
    }

    function test_deactivateGroup_When3ActiveGroups_WhenTheGroupIsNotVotedFor_ShouldNotScheduleTransferSinceGroupHasNoVotes()
        public
    {
        _activateGroupsFromHead(3);

        vm.prank(owner);
        mockDefaultStrategy.deactivateGroup(deactivatedGroup);

        (
            address[] memory lastTransferFromGroups,
            uint256[] memory lastTransferFromVotes,
            address[] memory lastTransferToGroups,
            uint256[] memory lastTransferToVotes
        ) = mockAccount.getLastTransferValues();

        assertEq(lastTransferFromGroups.length, 0);
        assertEq(lastTransferFromVotes.length, 0);
        assertEq(lastTransferToGroups.length, 0);
        assertEq(lastTransferToVotes.length, 0);
    }

    // =========================================================================
    //                     #deactivateUnhealthyGroup()
    // =========================================================================

    /// @dev `describe("#deactivateUnhealthyGroup()")` beforeEach.
    function _setUpUnhealthyGroup() private {
        _activateGroupsFromHead(3);
    }

    function test_deactivateUnhealthyGroup_ShouldRevertWhenGroupIsHealthy() public {
        _setUpUnhealthyGroup();

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.HealthyGroup.selector, groupAddresses[1])
        );
        mockDefaultStrategy.deactivateUnhealthyGroup(groupAddresses[1]);
    }

    /// @dev `describe("when the group is not elected")` beforeEach.
    function _setUpGroupNotElected() private {
        _setUpUnhealthyGroup();
        mineToNextEpoch();
        revokeElectionOnMockValidatorGroupsAndUpdate(
            mockGroupHealth,
            _toArray(groupAddresses[1]),
            true
        );
    }

    function test_deactivateUnhealthyGroup_WhenTheGroupIsNotElected_ShouldRemoveGroup() public {
        _setUpGroupNotElected();

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupRemoved(groupAddresses[1]);
        mockDefaultStrategy.deactivateUnhealthyGroup(groupAddresses[1]);
    }

    function test_deactivateUnhealthyGroup_WhenTheGroupIsNotElected_RevertsWhenBelowMinCountOfActiveGroups()
        public
    {
        _setUpGroupNotElected();

        vm.prank(owner);
        mockDefaultStrategy.setMinCountOfActiveGroups(10);

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.MinimumCountOfActiveGroupsReached.selector)
        );
        mockDefaultStrategy.deactivateUnhealthyGroup(groupAddresses[1]);
    }

    function test_deactivateUnhealthyGroup_WhenTheGroupIsNotRegistered_ShouldRemoveGroup() public {
        _setUpUnhealthyGroup();

        deregisterValidatorGroup(deactivatedGroup);
        mineToNextEpoch();
        electMockValidatorGroupsAndUpdate(mockGroupHealth, _toArray(deactivatedGroup));

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupRemoved(deactivatedGroup);
        mockDefaultStrategy.deactivateUnhealthyGroup(deactivatedGroup);
    }

    function test_deactivateUnhealthyGroup_WhenTheGroupHasNoMembers_ShouldRemoveGroup() public {
        _setUpUnhealthyGroup();

        removeMembersFromGroup(deactivatedGroup);
        mineToNextEpoch();
        electMockValidatorGroupsAndUpdate(mockGroupHealth, _toArray(deactivatedGroup));

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupRemoved(deactivatedGroup);
        mockDefaultStrategy.deactivateUnhealthyGroup(deactivatedGroup);
    }

    function test_deactivateUnhealthyGroup_WhenGroupHas3ValidatorsButOnly1IsElected_ShouldRevertWithHealthyGroupMessage()
        public
    {
        _setUpUnhealthyGroup();

        address groupWithThreeValidators = _registerGroupWithThreeValidatorsOneElected();

        vm.expectRevert(
            abi.encodeWithSelector(DefaultStrategy.HealthyGroup.selector, groupWithThreeValidators)
        );
        mockDefaultStrategy.deactivateUnhealthyGroup(groupWithThreeValidators);
    }

    /// @dev `describe("when group has 3 validators, but only 1 is elected.")` beforeEach.
    /// @dev Deviation: the anvil devchain caps a validator group at two members, while the
    ///      ganache devchain the Hardhat suite ran against allowed more. The cap is raised on
    ///      the real Validators contract so the group really has the three members the original
    ///      test registers.
    function _registerGroupWithThreeValidatorsOneElected() private returns (address group) {
        (group, ) = randomSigner(40_000 ether);
        uint256 memberCount = 3;
        _raiseMaxGroupSize(memberCount);
        registerValidatorGroup(group, memberCount);

        uint256 electedValidatorIndex = 0;
        for (uint256 i = 0; i < memberCount; i++) {
            address validator = createWallet(11_000 ether);
            registerValidatorAndAddToGroupMembers(group, validator);
            if (i == memberCount - 1) {
                mockGroupHealth.setElectedValidator(electedValidatorIndex, validator);
            }
        }
        mockGroupHealth.updateGroupHealth(group);

        (address head, ) = defaultStrategy.getGroupsHead();
        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(group);
        mockDefaultStrategy.activateGroup(group, ADDRESS_ZERO, head);
    }

    /// @dev Raises `Validators.maxGroupSize` if the devchain caps groups below `size`.
    function _raiseMaxGroupSize(uint256 size) private {
        ICeloValidatorsGroupSize groupSize = ICeloValidatorsGroupSize(address(celoValidators));
        if (groupSize.maxGroupSize() >= size) {
            return;
        }
        address validatorsOwner = celoValidators.owner();
        vm.prank(validatorsOwner);
        groupSize.setMaxGroupSize(size);
    }

    function test_deactivateUnhealthyGroup_WhenTheGroupIsSlashed_ShouldRemoveGroup() public {
        _setUpUnhealthyGroup();

        updateGroupSlashingMultiplier(deactivatedGroup, mockSlasher);
        mineToNextEpoch();
        electMockValidatorGroupsAndUpdate(mockGroupHealth, _toArray(deactivatedGroup));

        _expectEmitFrom(address(mockDefaultStrategy));
        emit GroupRemoved(groupAddresses[1]);
        mockDefaultStrategy.deactivateUnhealthyGroup(deactivatedGroup);
    }
}
