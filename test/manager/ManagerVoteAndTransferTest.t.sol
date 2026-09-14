// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./ManagerTestBase.sol";

/**
 * @title ManagerVoteAndTransferTest
 * @notice Ports `#voteProposal()`, `#revokeVotes()`, `#unlockBalance()`,
 *         `#updateHistoryAndReturnLockedStCeloInVoting()`, `#transfer()` and
 *         `#getAddressStrategy()` of test-ts/manager.test.ts.
 */
contract ManagerVoteAndTransferTest is ManagerTestBase {
    uint256 private constant PROPOSAL_ID = 1;
    uint256 private constant INDEX = 0;
    uint256 private constant YES = 10;
    uint256 private constant NO = 20;
    uint256 private constant ABSTAIN = 30;

    /// @dev `defaultGroupDeposit` of the `#transfer()` blocks.
    uint256 private constant DEFAULT_GROUP_DEPOSIT = 1000;
    /// @dev `specificGroupStrategyDeposit` of the `#transfer()` blocks.
    uint256 private constant SPECIFIC_GROUP_DEPOSIT = 100;

    // =========================================================================
    //                           #voteProposal()
    // =========================================================================

    function test_voteProposal_ShouldCallAllSubsequentContractsCorrectly() public {
        manager.voteProposal(PROPOSAL_ID, INDEX, YES, NO, ABSTAIN);

        assertEq(mockStakedCelo.lockedBalance(), YES + NO + ABSTAIN);

        assertEq(mockVote.proposalId(), PROPOSAL_ID);
        assertEq(mockVote.totalYesVotes(), YES);
        assertEq(mockVote.totalNoVotes(), NO);
        assertEq(mockVote.totalAbstainVotes(), ABSTAIN);

        assertEq(mockAccount.proposalIdVoted(), PROPOSAL_ID);
        assertEq(mockAccount.indexVoted(), INDEX);
        assertEq(mockAccount.yesVotesVoted(), YES);
        assertEq(mockAccount.noVotesVoted(), NO);
        assertEq(mockAccount.abstainVoteVoted(), ABSTAIN);
    }

    // =========================================================================
    //                           #revokeVotes()
    // =========================================================================

    function test_revokeVotes_ShouldCallAllSubsequentContractsCorrectly() public {
        mockVote.setVotes(YES, NO, ABSTAIN);
        manager.revokeVotes(PROPOSAL_ID, INDEX);

        assertEq(mockVote.revokeProposalId(), PROPOSAL_ID);

        assertEq(mockAccount.proposalIdVoted(), PROPOSAL_ID);
        assertEq(mockAccount.indexVoted(), INDEX);
        assertEq(mockAccount.yesVotesVoted(), YES);
        assertEq(mockAccount.noVotesVoted(), NO);
        assertEq(mockAccount.abstainVoteVoted(), ABSTAIN);
    }

    // =========================================================================
    //                          #unlockBalance()
    // =========================================================================

    function test_unlockBalance_ShouldCallAllSubsequentContractsCorrectly() public {
        manager.unlockBalance(nonVote);
        assertEq(mockStakedCelo.unlockedBalanceFor(), nonVote);
    }

    // =========================================================================
    //          #updateHistoryAndReturnLockedStCeloInVoting()
    // =========================================================================

    function test_updateHistoryAndReturnLockedStCeloInVoting_ShouldCallAllSubsequentContractsCorrectly()
        public
    {
        manager.updateHistoryAndReturnLockedStCeloInVoting(nonVote);
        assertEq(mockVote.updatedHistoryFor(), nonVote);
    }

    // =========================================================================
    //                            #transfer()
    // =========================================================================

    function test_transfer_WhenDepositorVotedForDefaultStrategy_ShouldNotScheduleAnyTransfersIfBothAccountUseDefaultStrategy()
        public
    {
        setUpTransfer();
        setUpDepositorVotedForDefaultStrategy();

        vm.prank(address(mockStakedCelo));
        manager.transfer(depositor, depositor2, 10);

        assertNoTransferScheduled();
    }

    function test_transfer_WhenDepositorVotedForDefaultStrategy_ShouldNotScheduleAnyTransfersIfBothAccountUseDefaultStrategyDepositor2AlsoDeposited()
        public
    {
        setUpTransfer();
        setUpDepositorVotedForDefaultStrategy();

        vm.prank(depositor2);
        manager.deposit{value: 150}();
        updateGroupCelo();

        vm.prank(address(mockStakedCelo));
        manager.transfer(depositor, depositor2, 10);

        assertNoTransferScheduled();
    }

    function test_transfer_WhenDepositorVotedForDefaultStrategy_WhenChangingStrategyFromDefaultSpecific_ShouldScheduleTransfersIfDefaultStrategySpecificStrategy()
        public
    {
        setUpTransfer();
        setUpDepositorVotedForDefaultStrategy();

        address specificGroupStrategyAddress = groupAddresses[2];
        vm.prank(depositor2);
        manager.changeStrategy(specificGroupStrategyAddress);
        vm.prank(depositor2);
        manager.deposit{value: SPECIFIC_GROUP_DEPOSIT}();
        updateGroupCelo();

        vm.prank(address(mockStakedCelo));
        manager.transfer(depositor, depositor2, DEFAULT_GROUP_DEPOSIT);

        assertEq(
            specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress),
            DEFAULT_GROUP_DEPOSIT + SPECIFIC_GROUP_DEPOSIT
        );
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[0]), 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(groupAddresses[1]), 0);
    }

    function test_transfer_WhenDepositorVotedForSpecificStrategy_ShouldNotScheduleAnyTransfersIfSecondAccountAlsoVotedForSameSpecificGroupStrategy()
        public
    {
        setUpTransfer();
        setUpDepositorVotedForSpecificStrategy();
        address specificGroupStrategyAddress = groupAddresses[2];

        uint256 differentDeposit = 1 ether;
        vm.prank(depositor2);
        manager.changeStrategy(specificGroupStrategyAddress);
        vm.prank(depositor2);
        manager.deposit{value: differentDeposit}();

        vm.prank(address(mockStakedCelo));
        manager.transfer(depositor, depositor2, 10);

        assertEq(
            specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress),
            differentDeposit + SPECIFIC_GROUP_DEPOSIT
        );
    }

    function test_transfer_WhenDepositorVotedForSpecificStrategy_ShouldScheduleTransfersIfSpecificStrategyDefaultStrategy()
        public
    {
        setUpTransfer();
        setUpDepositorVotedForSpecificStrategy();
        address specificGroupStrategyAddress = groupAddresses[2];

        (address tail, ) = mockDefaultStrategy.getGroupsTail();

        vm.prank(address(mockStakedCelo));
        manager.transfer(depositor, depositor2, SPECIFIC_GROUP_DEPOSIT);

        assertEq(specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress), 0);
        assertEq(mockDefaultStrategy.stCeloInGroup(tail), SPECIFIC_GROUP_DEPOSIT);
    }

    function test_transfer_WhenDepositorVotedForSpecificStrategy_ShouldScheduleTransfersIfSpecificStrategyDifferentSpecificStrategy()
        public
    {
        setUpTransfer();
        setUpDepositorVotedForSpecificStrategy();
        address specificGroupStrategyAddress = groupAddresses[2];

        uint256 differentDeposit = 1 ether;
        vm.prank(depositor2);
        manager.changeStrategy(groupAddresses[0]);
        vm.prank(depositor2);
        manager.deposit{value: differentDeposit}();

        mockAccount.setCeloForGroup(groupAddresses[0], differentDeposit);

        vm.prank(address(mockStakedCelo));
        manager.transfer(depositor2, depositor, differentDeposit);

        assertEq(
            specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress),
            differentDeposit + SPECIFIC_GROUP_DEPOSIT
        );
    }

    function test_transfer_WhenDepositorVotedForSpecificStrategy_ShouldScheduleTransfersToDefaultIfDifferentSpecificStrategyWasBlocked()
        public
    {
        setUpTransfer();
        setUpDepositorVotedForSpecificStrategy();
        address specificGroupStrategyAddress = groupAddresses[2];

        uint256 differentDeposit = 100;
        address differentSpecificGroupStrategyAddress = groupAddresses[0];
        vm.prank(owner);
        specificGroupStrategy.blockGroup(specificGroupStrategyAddress);
        vm.prank(depositor2);
        manager.changeStrategy(differentSpecificGroupStrategyAddress);
        vm.prank(depositor2);
        manager.deposit{value: differentDeposit}();
        mockAccount.setCeloForGroup(differentSpecificGroupStrategyAddress, differentDeposit);

        (address tail, ) = mockDefaultStrategy.getGroupsTail();

        vm.prank(address(mockStakedCelo));
        manager.transfer(depositor2, depositor, differentDeposit);

        (uint256 stCeloInStrategy, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(specificGroupStrategyAddress);
        assertEq(stCeloInStrategy, differentDeposit + SPECIFIC_GROUP_DEPOSIT);
        assertEq(overflow, 0);
        assertEq(unhealthy, differentDeposit);
        assertEq(mockDefaultStrategy.stCeloInGroup(tail), differentDeposit);
    }

    function test_transfer_WhenDepositorVotedForSpecificStrategy_ShouldScheduleTransfersFromDefaultIfSpecificStrategyWasBlocked()
        public
    {
        setUpTransfer();
        setUpDepositorVotedForSpecificStrategy();
        address specificGroupStrategyAddress = groupAddresses[2];

        uint256 differentDeposit = 1000;
        address differentSpecificGroupStrategyAddress = groupAddresses[0];
        vm.prank(depositor2);
        manager.changeStrategy(differentSpecificGroupStrategyAddress);
        vm.prank(depositor2);
        manager.deposit{value: differentDeposit}();
        updateGroupCelo();
        vm.prank(owner);
        specificGroupStrategy.blockGroup(differentSpecificGroupStrategyAddress);
        updateGroupCelo();

        vm.prank(address(mockStakedCelo));
        manager.transfer(depositor2, depositor, differentDeposit);

        (uint256 stCeloInDifferent, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(differentSpecificGroupStrategyAddress);
        assertEq(
            specificGroupStrategy.stCeloInGroup(specificGroupStrategyAddress),
            differentDeposit + SPECIFIC_GROUP_DEPOSIT
        );
        assertEq(stCeloInDifferent, 0);
        assertEq(overflow, 0);
        assertEq(unhealthy, 0);
    }

    function test_transfer_WhenDepositorVotedForSpecificStrategyThatIsOverflowingAndUnhealthyDifferentSpecificStrategy_ShouldScheduleCorrectTransfer()
        public
    {
        setUpTransfer();
        uint256 deposit = setUpOverflowingUnhealthySpecificStrategy();

        (uint256 stCeloInStrategy, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        (uint256 stCeloInDifferent, , ) = specificGroupStrategy.getStCeloInGroup(groupAddresses[4]);
        assertEq(stCeloInStrategy, 0);
        assertEq(overflow, 0);
        assertEq(unhealthy, 0);
        assertEq(stCeloInDifferent, deposit);
    }

    // =========================================================================
    //                        #getAddressStrategy()
    // =========================================================================

    function test_getAddressStrategy_ShouldReturnDefaultStrategy() public view {
        assertEq(manager.getAddressStrategy(depositor), ADDRESS_ZERO);
    }

    function test_getAddressStrategy_WhenStrategyChanged_ShouldReturnSpecificStrategy() public {
        setUpStrategyChanged();
        assertEq(manager.getAddressStrategy(depositor), groupAddresses[2]);
    }

    function test_getAddressStrategy_WhenStrategyChanged_WhenStrategyBlocked_ShouldReturnDefaultStrategy()
        public
    {
        setUpStrategyChanged();
        vm.prank(owner);
        specificGroupStrategy.blockGroup(groupAddresses[2]);

        assertEq(manager.getAddressStrategy(depositor), ADDRESS_ZERO);
    }

    function test_getAddressStrategy_WhenStrategyChanged_WhenGroupUnhealthy_ShouldReturnDefaultStrategy()
        public
    {
        setUpStrategyChanged();
        slashGroup(groupAddresses[2]);
        mockGroupHealth.updateGroupHealth(groupAddresses[2]);

        assertEq(manager.getAddressStrategy(depositor), ADDRESS_ZERO);
    }

    // =========================================================================
    //                          BLOCK FIXTURES
    // =========================================================================

    /// @dev `beforeEach` of `#transfer()`.
    /// @dev Deviation: Foundry pranks the StakedCelo caller instead of impersonating it, so
    ///      this transfer is not needed to pay for gas. It is kept so that the balances of
    ///      `nonVote` and of the StakedCelo mock match the original; no assertion depends on
    ///      it.
    function setUpTransfer() private {
        vm.prank(nonVote);
        (bool sent, ) = address(mockStakedCelo).call{value: 1 ether}("");
        assertTrue(sent);
    }

    /// @dev `beforeEach` of `#transfer() > When depositor voted for default strategy`.
    function setUpDepositorVotedForDefaultStrategy() private {
        activateGroupsWithCeloList(arr(uint256(40), uint256(50)));
        vm.prank(depositor);
        manager.deposit{value: DEFAULT_GROUP_DEPOSIT}();
        updateGroupCelo();
    }

    /// @dev `beforeEach` of `#transfer() > When depositor voted for specific strategy`.
    function setUpDepositorVotedForSpecificStrategy() private {
        activateGroupsWithCeloList(arr(uint256(40), uint256(50)));
        mockAccount.setCeloForGroup(groupAddresses[2], SPECIFIC_GROUP_DEPOSIT);
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[2]);
        vm.prank(depositor);
        manager.deposit{value: SPECIFIC_GROUP_DEPOSIT}();
    }

    /// @dev `beforeEach` of `#transfer() > When depositor voted for specific strategy that is
    ///      overflowing and unhealthy -> different specific strategy`.
    function setUpOverflowingUnhealthySpecificStrategy() private returns (uint256 deposit) {
        uint256 depositOverCapacity = 10 ether;
        prepareOverflowAndReadCapacities(false);
        deposit = firstGroupCapacity + depositOverCapacity;

        vm.startPrank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[1]);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[2]);
        vm.stopPrank();
        mockDefaultStrategy.activateGroup(groupAddresses[1], ADDRESS_ZERO, ADDRESS_ZERO);
        mockDefaultStrategy.activateGroup(groupAddresses[2], ADDRESS_ZERO, groupAddresses[1]);

        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[0]);
        vm.prank(depositor);
        manager.deposit{value: deposit}();

        revokeElection(groupAddresses[0]);
        mockGroupHealth.updateGroupHealth(groupAddresses[0]);
        specificGroupStrategy.rebalanceWhenHealthChanged(groupAddresses[0]);

        (uint256 stCeloInStrategy, uint256 overflow, uint256 unhealthy) = specificGroupStrategy
            .getStCeloInGroup(groupAddresses[0]);
        assertEq(stCeloInStrategy, deposit);
        assertEq(overflow, depositOverCapacity);
        assertEq(unhealthy, firstGroupCapacity);

        updateGroupCelo();
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[4]);
    }

    /// @dev `beforeEach` of `#getAddressStrategy() > When strategy changed`.
    function setUpStrategyChanged() private {
        activateGroupsWithCeloList(arr(uint256(40), uint256(50)));
        vm.prank(depositor);
        manager.changeStrategy(groupAddresses[2]);
    }
}
