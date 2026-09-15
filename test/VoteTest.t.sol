// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/DevchainHelper.sol";
import "./helpers/deploy/TestAccountDeployHelper.sol";
import "../contracts/Pausable.sol";
import "../contracts/common/Errors.sol";

/**
 * @title VoteTest
 * @notice Port of legacy/test-ts/vote.test.ts (`describe("Vote")`).
 * @dev Ports the `before()` hook of the TypeScript suite: ten validator groups with one
 *      validator each are registered against the real Celo core contracts of the devchain, the
 *      "TestVote" Hardhat fixture is deployed against the devchain registry
 *      (`deployTestVote(REGISTRY_ADDRESS)`), the first three groups are elected on
 *      MockGroupHealth and activated in MockDefaultStrategy. `setUp()` runs before every test,
 *      which is what the `evm_snapshot` / `evm_revert` pair of the original did.
 *
 *      Governance is the real Celo Governance contract resolved from the devchain registry, the
 *      same contract the original drove through ContractKit's `GovernanceWrapper`: proposals are
 *      really proposed, dequeued and voted on, and the vote totals are read back from it.
 */
contract VoteTest is TestAccountDeployHelper, DevchainHelper {
    // =========================================================================
    //                     EVENTS (for vm.expectEmit)
    // =========================================================================

    event ContractPaused();
    event ContractUnpaused();
    event PauserSet(address pauser);
    event LockedStCeloInVoting(address account, uint256 lockedCelo);

    // =========================================================================
    //                            TEST STATE
    // =========================================================================

    address internal depositor0;
    address internal depositor1;
    address internal nonStakedCelo;
    address internal nonAccount;
    address internal nonOwner;
    address internal voter;
    address internal pauser;

    address[] internal groupAddresses;
    address[] internal activatedGroupAddresses;
    address[] internal validatorAddresses;

    /// @dev Kept in storage so that the longer test bodies stay clear of "stack too deep".
    uint256 internal referendumDuration;

    /// @dev The calldata of ContractKit's `propose([{to: manager, input: manager.owner()}], url)`.
    bytes internal constant PROPOSAL_INPUT = hex"8da5cb5b";

    string internal constant DESCRIPTION_URL = "http://www.descriptionUrl.com";

    uint256 internal constant PROPOSAL_1_ID = 1;
    uint256 internal constant PROPOSAL_1_INDEX = 0;
    uint256 internal constant PROPOSAL_2_ID = 2;
    uint256 internal constant PROPOSAL_2_INDEX = 1;
    uint256 internal constant PROPOSAL_3_ID = 3;
    uint256 internal constant PROPOSAL_3_INDEX = 2;

    // =========================================================================
    //                               SETUP
    // =========================================================================

    function setUp() public {
        loadDevchain();

        (depositor0, ) = randomSigner(300 ether);
        (depositor1, ) = randomSigner(300 ether);
        (nonStakedCelo, ) = randomSigner(100 ether);
        (nonOwner, ) = randomSigner(100 ether);
        (nonAccount, ) = randomSigner(100 ether);
        (voter, ) = randomSigner(300 ether);

        createCeloAccount(voter);
        _registerGroups();

        deployTestVote(REGISTRY_ADDRESS);
        pauser = owner;

        _wireDependencies();

        electMockValidatorGroupsAndUpdate(mockGroupHealth, activatedGroupAddresses);
        _activateGroups();
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

    /// @dev Ten validator groups with one validator each; the first three get activated.
    function _registerGroups() private {
        for (uint256 i = 0; i < 10; i++) {
            (address group, ) = randomSigner(11_000 ether);
            groupAddresses.push(group);
            if (i < 3) {
                activatedGroupAddresses.push(group);
            }
            address validator = createWallet(11_000 ether);
            validatorAddresses.push(validator);

            registerValidatorGroup(group);
            registerValidatorAndAddToGroupMembers(group, validator);
        }
    }

    function _wireDependencies() private {
        vm.startPrank(owner);
        vote.setPauser();
        mockDefaultStrategy.setDependencies(
            address(account),
            address(mockGroupHealth),
            address(specificGroupStrategy)
        );
        manager.setDependencies(
            address(stakedCelo),
            address(account),
            address(vote),
            address(mockGroupHealth),
            address(specificGroupStrategy),
            address(mockDefaultStrategy)
        );
        vote.setDependencies(address(stakedCelo), address(account));
        vm.stopPrank();
    }

    function _activateGroups() private {
        address previousKey = ADDRESS_ZERO;
        for (uint256 i = 0; i < activatedGroupAddresses.length; i++) {
            vm.startPrank(owner);
            mockDefaultStrategy.addActivatableGroup(activatedGroupAddresses[i]);
            mockDefaultStrategy.activateGroup(
                activatedGroupAddresses[i],
                ADDRESS_ZERO,
                previousKey
            );
            vm.stopPrank();
            previousKey = activatedGroupAddresses[i];
        }
    }

    // =========================================================================
    //                              HELPERS
    // =========================================================================

    /// @notice Ports `proposeNewProposal(dequeue)` of the original suite.
    /// @dev Deviation: the ganache devchain of the original charged a negligible governance
    ///      deposit, the anvil devchain charges 100 CELO per proposal. The proposer is topped up
    ///      with the deposit here; no assertion of the suite looks at its CELO balance.
    function _proposeNewProposal(bool dequeue) internal returns (uint256 proposalId) {
        uint256 minDeposit = celoGovernance.minDeposit();

        address[] memory destinations = new address[](1);
        destinations[0] = address(manager);
        uint256[] memory values = new uint256[](1);
        uint256[] memory dataLengths = new uint256[](1);
        dataLengths[0] = PROPOSAL_INPUT.length;

        vm.deal(depositor1, depositor1.balance + minDeposit);
        vm.prank(depositor1);
        proposalId = celoGovernance.propose{value: minDeposit}(
            values,
            destinations,
            PROPOSAL_INPUT,
            dataLengths,
            DESCRIPTION_URL
        );

        if (dequeue) {
            timeTravel(celoGovernance.dequeueFrequency() + 1);
            vm.prank(depositor1);
            celoGovernance.dequeueProposalsIfReady();
        }
    }

    /// @notice `proposeNewProposal()` with the TypeScript default `dequeue = true`.
    function _proposeNewProposal() internal returns (uint256) {
        return _proposeNewProposal(true);
    }

    function _deposit(address depositor, uint256 amount) internal {
        vm.prank(depositor);
        manager.deposit{value: amount}();
    }

    /// @notice Ports `depositAndActivate(depositor, value)` of the original suite.
    function _depositAndActivate(address depositor, uint256 amount) internal {
        _deposit(depositor, amount);

        for (uint256 i = 0; i < activatedGroupAddresses.length; i++) {
            address group = activatedGroupAddresses[i];
            uint256 scheduledVotes = account.scheduledVotesForGroup(group);
            (address lesser, address greater) = findLesserAndGreaterAfterVote(
                group,
                int256(scheduledVotes)
            );
            vm.prank(depositor);
            account.activateAndVote(group, lesser, greater);
        }

        mineToNextEpoch();

        for (uint256 i = 0; i < activatedGroupAddresses.length; i++) {
            vm.prank(depositor);
            account.activateAndVote(activatedGroupAddresses[i], ADDRESS_ZERO, ADDRESS_ZERO);
        }
    }

    function _voteProposal(
        address depositor,
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) internal {
        vm.prank(depositor);
        manager.voteProposal(proposalId, index, yesVotes, noVotes, abstainVotes);
    }

    /// @notice Ports `checkGovernanceTotalVotes(...)`, reading the real Governance contract.
    function _checkGovernanceTotalVotes(
        uint256 proposalId,
        uint256 expectedYes,
        uint256 expectedNo,
        uint256 expectedAbstain
    ) internal view {
        (uint256 yes, uint256 no, uint256 abstain) = celoGovernance.getVoteTotals(proposalId);
        assertEq(yes, expectedYes);
        assertEq(no, expectedNo);
        assertEq(abstain, expectedAbstain);
    }

    /// @dev `updateHistoryAndReturnLockedStCeloInVoting` as the impersonated Manager contract,
    ///      which is what `getImpersonatedSigner(managerContract.address, ...)` did.
    function _updateHistory(address beneficiary) internal {
        vm.prank(address(manager));
        vote.updateHistoryAndReturnLockedStCeloInVoting(beneficiary);
    }

    // =========================================================================
    //                    #getVoteWeight() tests (3)
    // =========================================================================

    // 1
    function test_GetVoteWeight_ReturnsZeroWhenNoStCelo() public {
        uint256 voteWeight = vote.getVoteWeight(depositor0);
        assertEq(voteWeight, 0);
    }

    // 2
    function test_GetVoteWeight_ReturnsDepositedStCelo() public {
        uint256 amountOfCeloToDeposit = 10000000000000000; // 0.01 ether
        _deposit(depositor0, amountOfCeloToDeposit);
        uint256 voteWeight = vote.getVoteWeight(depositor0);
        assertEq(voteWeight, amountOfCeloToDeposit);
    }

    // 3
    function test_GetVoteWeight_ReturnsDepositedPlusLockedStCelo() public {
        uint256 amountOfCeloToDeposit = 10 ether;
        _depositAndActivate(depositor0, amountOfCeloToDeposit);
        _proposeNewProposal();

        // Check initial vote weight (just deposited amount)
        uint256 initialVoteWeight = vote.getVoteWeight(depositor0);
        assertEq(initialVoteWeight, amountOfCeloToDeposit);

        // Get initial balances before voting
        uint256 initialRegularBalance = stakedCelo.balanceOf(depositor0);
        uint256 initialLockedBalance = stakedCelo.lockedVoteBalanceOf(depositor0);
        assertEq(initialLockedBalance, 0);

        // Vote on proposal to create locked stCELO
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        // After voting, verify that locked vote balance exists and is non-zero
        uint256 finalRegularBalance = stakedCelo.balanceOf(depositor0);
        uint256 finalLockedBalance = stakedCelo.lockedVoteBalanceOf(depositor0);
        assertTrue(finalLockedBalance > 0);

        // The total stCELO (regular + locked) should equal the initial regular balance
        uint256 totalStCeloBalance = finalRegularBalance + finalLockedBalance;
        assertEq(totalStCeloBalance, initialRegularBalance);

        // Vote weight should include both regular and locked stCELO
        uint256 finalVoteWeight = vote.getVoteWeight(depositor0);
        assertEq(finalVoteWeight, vote.toCelo(totalStCeloBalance));
        assertEq(finalVoteWeight, amountOfCeloToDeposit);
    }

    // =========================================================================
    //                  #getReferendumDuration() tests (1)
    // =========================================================================

    // 4
    function test_GetReferendumDuration_ReturnsSameAsGovernance() public {
        assertEq(vote.getReferendumDuration(), celoGovernance.getReferendumStageDuration());
    }

    // =========================================================================
    //                    #voteProposal() tests (6)
    // =========================================================================

    // 5
    function test_VoteProposal_RevertsWhenNoStCelo() public {
        _proposeNewProposal();

        vm.expectRevert(abi.encodeWithSelector(Vote.NoStakedCelo.selector, depositor0));
        vm.prank(depositor0);
        manager.voteProposal(PROPOSAL_1_ID, PROPOSAL_1_INDEX, 1, 0, 0);
    }

    // 6
    function test_VoteProposal_WhenDeposited_RevertsWhenVotingMoreThanBalance() public {
        _proposeNewProposal();
        _depositAndActivate(depositor0, 10 ether);

        vm.expectRevert(abi.encodeWithSelector(Vote.NotEnoughStakedCelo.selector, depositor0));
        vm.prank(depositor0);
        manager.voteProposal(PROPOSAL_1_ID, PROPOSAL_1_INDEX, 8 ether, 2 ether, 1 ether);
    }

    // 7
    function test_VoteProposal_WhenDeposited_RevertsWhenVotingForNonExistingProposal() public {
        _proposeNewProposal();
        _depositAndActivate(depositor0, 10 ether);

        vm.expectRevert(bytes("Proposal not dequeued"));
        vm.prank(depositor0);
        manager.voteProposal(100, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);
    }

    // 8
    function test_VoteProposal_WhenDeposited_WhenVoted_ReturnsCorrectVotes() public {
        _proposeNewProposal();
        _depositAndActivate(depositor0, 10 ether);
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        _checkGovernanceTotalVotes(PROPOSAL_1_ID, 7 ether, 2 ether, 1 ether);
    }

    // 9
    function test_VoteProposal_WhenDeposited_WhenVoted_ReturnsCorrectVotesWhenRevoted() public {
        _proposeNewProposal();
        _depositAndActivate(depositor0, 10 ether);
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 5 ether, 3 ether, 1 ether);

        _checkGovernanceTotalVotes(PROPOSAL_1_ID, 5 ether, 3 ether, 1 ether);
    }

    // 10
    function test_VoteProposal_WhenVotingOnTwoProposals_ReturnsCorrectVotes() public {
        _proposeNewProposal();
        _depositAndActivate(depositor0, 10 ether);
        _depositAndActivate(depositor1, 10 ether);
        _proposeNewProposal();
        _proposeNewProposal();

        _voteProposal(depositor0, PROPOSAL_2_ID, PROPOSAL_2_INDEX, 6 ether, 2 ether, 1 ether);
        _voteProposal(depositor0, PROPOSAL_3_ID, PROPOSAL_3_INDEX, 2 ether, 3 ether, 4 ether);
        _voteProposal(depositor1, PROPOSAL_2_ID, PROPOSAL_2_INDEX, 1 ether, 2 ether, 3 ether);
        _voteProposal(depositor1, PROPOSAL_3_ID, PROPOSAL_3_INDEX, 4 ether, 3 ether, 1 ether);

        _checkGovernanceTotalVotes(PROPOSAL_2_ID, 7 ether, 4 ether, 4 ether);
        _checkGovernanceTotalVotes(PROPOSAL_3_ID, 6 ether, 6 ether, 5 ether);
    }

    // =========================================================================
    //                    #getVoteRecord() tests (3)
    // =========================================================================

    // 11
    function test_GetVoteRecord_ReturnsEmptyWhenNotVoted() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();

        Vote.ProposalVoteRecord memory record = vote.getVoteRecord(PROPOSAL_1_ID);

        assertEq(record.proposalId, 0);
        assertEq(record.yesVotes, 0);
        assertEq(record.noVotes, 0);
        assertEq(record.abstainVotes, 0);
    }

    // 12
    function test_GetVoteRecord_WhenVoted_ReturnsCorrectValues() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        Vote.ProposalVoteRecord memory record = vote.getVoteRecord(PROPOSAL_1_ID);

        assertEq(record.proposalId, PROPOSAL_1_ID);
        assertEq(record.yesVotes, 7 ether);
        assertEq(record.noVotes, 2 ether);
        assertEq(record.abstainVotes, 1 ether);
    }

    // 13
    function test_GetVoteRecord_WhenVoted_UpdatesWhenRevoted() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 5 ether, 3 ether, 1 ether);

        Vote.ProposalVoteRecord memory record = vote.getVoteRecord(PROPOSAL_1_ID);

        assertEq(record.proposalId, PROPOSAL_1_ID);
        assertEq(record.yesVotes, 5 ether);
        assertEq(record.noVotes, 3 ether);
        assertEq(record.abstainVotes, 1 ether);
    }

    // =========================================================================
    //                #getLockedStCeloInVoting() tests (3)
    // =========================================================================

    // 14
    function test_GetLockedStCeloInVoting_ReturnsZeroWhenNotVoted() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();

        assertEq(vote.getLockedStCeloInVoting(depositor0), 0);
    }

    // 15
    function test_GetLockedStCeloInVoting_WhenVoted_ReturnsLockedCelo() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        assertEq(vote.getLockedStCeloInVoting(depositor0), 10 ether);
    }

    // 16
    function test_GetLockedStCeloInVoting_WhenVoted_UpdatesWhenRevoted() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 5 ether, 3 ether, 1 ether);

        assertEq(vote.getLockedStCeloInVoting(depositor0), 9 ether);
    }

    // =========================================================================
    //      #updateHistoryAndReturnLockedStCeloInVoting() tests (6)
    // =========================================================================

    // 17
    function test_UpdateHistory_ReturnsZeroWhenNotVoted() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();

        vm.expectEmit(true, true, true, true, address(vote));
        emit LockedStCeloInVoting(depositor0, 0);
        _updateHistory(depositor0);
    }

    // 18
    function test_UpdateHistory_WhenVoted_ReturnsLockedCelo() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        vm.expectEmit(true, true, true, true, address(vote));
        emit LockedStCeloInVoting(depositor0, 10 ether);
        _updateHistory(depositor0);
    }

    // 19
    function test_UpdateHistory_WhenVoted_ReturnsLockedCeloWithMaxProposals() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        uint256 concurrent = 3 * 7; // 3 proposals per day * week
        setGovernanceConcurrentProposals(concurrent);
        for (uint256 i = 0; i < concurrent; i++) {
            // dequeue only after the last proposal
            _proposeNewProposal(i == concurrent - 1);
        }

        for (uint256 i = 0; i < concurrent; i++) {
            _voteProposal(depositor0, i + 1, i, 7 ether, 2 ether, 1 ether);
        }

        vm.expectEmit(true, true, true, true, address(vote));
        emit LockedStCeloInVoting(depositor0, 10 ether);
        _updateHistory(depositor0);
    }

    // 20
    function test_UpdateHistory_WhenVoted_UpdatesWhenRevoted() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 5 ether, 3 ether, 1 ether);

        vm.expectEmit(true, true, true, true, address(vote));
        emit LockedStCeloInVoting(depositor0, 9 ether);
        _updateHistory(depositor0);
    }

    // 21
    function test_UpdateHistory_WhenVotedOn3Proposals_ReturnsCorrectOrder() public {
        _setUpThreeVotedProposals();

        uint256[] memory votedProposals = vote.getVotedStillRelevantProposals(depositor0);

        assertEq(votedProposals.length, 3);
        assertEq(votedProposals[0], PROPOSAL_2_ID);
        assertEq(votedProposals[1], PROPOSAL_1_ID);
        assertEq(votedProposals[2], PROPOSAL_3_ID);

        assertTrue(vote.proposalTimestamps(PROPOSAL_1_ID) > 0);
        assertTrue(vote.proposalTimestamps(PROPOSAL_2_ID) > 0);
        assertTrue(vote.proposalTimestamps(PROPOSAL_3_ID) > 0);
    }

    // 22
    function test_UpdateHistory_WhenVotedOn3Proposals_RemovesExpiredProposal() public {
        _setUpThreeVotedProposals();

        timeTravel(referendumDuration - celoGovernance.dequeueFrequency() + 1);
        _updateHistory(depositor0);

        uint256[] memory votedProposals = vote.getVotedStillRelevantProposals(depositor0);
        assertEq(votedProposals.length, 2);
        assertEq(votedProposals[0], PROPOSAL_2_ID);
        assertEq(votedProposals[1], PROPOSAL_3_ID);

        assertEq(vote.proposalTimestamps(PROPOSAL_1_ID), 0);
        assertTrue(vote.proposalTimestamps(PROPOSAL_2_ID) > 0);
        assertTrue(vote.proposalTimestamps(PROPOSAL_3_ID) > 0);
    }

    /// @dev The `beforeEach` of `describe("When voted on 3 proposals")`: proposal 1 is dequeued
    ///      first, proposals 2 and 3 one dequeue frequency later, then they are voted on in the
    ///      order 2, 1, 3.
    function _setUpThreeVotedProposals() private {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();

        referendumDuration = vote.getReferendumDuration();
        _proposeNewProposal(false);
        _proposeNewProposal();

        _voteProposal(depositor0, PROPOSAL_2_ID, PROPOSAL_2_INDEX, 1 ether, 2 ether, 3 ether);
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);
        _voteProposal(depositor0, PROPOSAL_3_ID, PROPOSAL_3_INDEX, 2 ether, 3 ether, 4 ether);
    }

    // =========================================================================
    //                    #revokeVotes() tests (2)
    // =========================================================================

    // 23
    function test_RevokeVotes_RevertsWhenNoStCelo() public {
        vm.expectRevert(abi.encodeWithSelector(Vote.NoStakedCelo.selector, depositor0));
        vm.prank(depositor0);
        manager.revokeVotes(PROPOSAL_1_ID, PROPOSAL_1_INDEX);
    }

    // 24
    function test_RevokeVotes_WhenDeposited_WhenVoted_ReturnsCorrectValues() public {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);

        vm.prank(depositor0);
        manager.revokeVotes(PROPOSAL_1_ID, PROPOSAL_1_INDEX);

        _checkGovernanceTotalVotes(PROPOSAL_1_ID, 0, 0, 0);
    }

    // =========================================================================
    //                    #setDependencies() tests (3)
    // =========================================================================

    // 25
    function test_SetDependencies_RevertsWithZeroStCeloAddress() public {
        address voteOwner = vote.owner();
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        vm.prank(voteOwner);
        vote.setDependencies(ADDRESS_ZERO, nonAccount);
    }

    // 26
    function test_SetDependencies_RevertsWithZeroAccountAddress() public {
        address voteOwner = vote.owner();
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        vm.prank(voteOwner);
        vote.setDependencies(nonStakedCelo, ADDRESS_ZERO);
    }

    // 27
    function test_SetDependencies_RevertsWhenCalledByNonOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonOwner);
        vote.setDependencies(nonStakedCelo, nonAccount);
    }

    // =========================================================================
    //              #deleteExpiredProposalTimestamp() tests (4)
    // =========================================================================

    // 28
    function test_DeleteExpiredProposalTimestamp_VoterHasProposalAsVoted() public {
        _setUpVotedProposal();

        uint256[] memory proposalIds = vote.getVotedStillRelevantProposals(depositor0);
        assertEq(proposalIds.length, 1);
        assertEq(proposalIds[0], PROPOSAL_1_ID);
    }

    // 29
    function test_DeleteExpiredProposalTimestamp_HasProposalTimestamp() public {
        _setUpVotedProposal();

        assertTrue(vote.proposalTimestamps(PROPOSAL_1_ID) > 0);
    }

    // 30
    function test_DeleteExpiredProposalTimestamp_RevertsWhenNotExpired() public {
        _setUpVotedProposal();

        vm.expectRevert(abi.encodeWithSelector(Vote.ProposalNotExpired.selector));
        vote.deleteExpiredProposalTimestamp(PROPOSAL_1_ID);
    }

    // 31
    function test_DeleteExpiredProposalTimestamp_WhenExpired_DeletesTimestamp() public {
        _setUpVotedProposal();

        /**
         * @dev Deviation: the original travelled `referendumDuration - dequeueFrequency + 1`,
         *      which expired the proposal only because the ganache devchain dequeued every few
         *      seconds: the proposal timestamp is the dequeue timestamp, and the fixture only
         *      spends about the 100 seconds of `mineToNextEpoch()` between the dequeue and this
         *      assertion. The anvil devchain dequeues every four hours, so the port waits out
         *      the whole referendum stage instead, which is what the original expressed.
         */
        timeTravel(vote.getReferendumDuration() + 1);

        vote.deleteExpiredProposalTimestamp(PROPOSAL_1_ID);
        assertEq(vote.proposalTimestamps(PROPOSAL_1_ID), 0);
    }

    /// @dev The `beforeEach` of `describe("#deleteExpiredProposalTimestamp()")`.
    function _setUpVotedProposal() private {
        _proposeNewProposal();
        _depositAndActivate(depositor0, 10 ether);
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);
    }

    // =========================================================================
    //              #deleteExpiredVoterProposalId() tests (4)
    // =========================================================================

    // 32
    function test_DeleteExpiredVoterProposalId_VoterHasProposalAsVoted() public {
        _setUpTwoVotedProposals();

        uint256[] memory proposalIds = vote.getVotedStillRelevantProposals(depositor0);
        assertEq(proposalIds.length, 2);
        assertEq(proposalIds[0], PROPOSAL_1_ID);
        assertEq(proposalIds[1], PROPOSAL_2_ID);
    }

    // 33
    function test_DeleteExpiredVoterProposalId_RevertsWhenIncorrectIndex() public {
        _setUpTwoVotedProposals();

        vm.expectRevert(abi.encodeWithSelector(Vote.IncorrectIndex.selector));
        vote.deleteExpiredVoterProposalId(depositor0, PROPOSAL_1_ID, PROPOSAL_2_INDEX);
    }

    // 34
    function test_DeleteExpiredVoterProposalId_RevertsWhenNotExpired() public {
        _setUpTwoVotedProposals();

        vm.expectRevert(abi.encodeWithSelector(Vote.ProposalNotExpired.selector));
        vote.deleteExpiredVoterProposalId(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX);
    }

    // 35
    function test_DeleteExpiredVoterProposalId_WhenExpired_DeletesProposalFromHistory() public {
        _setUpTwoVotedProposals();

        timeTravel(vote.getReferendumDuration() - celoGovernance.dequeueFrequency() + 1);

        vote.deleteExpiredVoterProposalId(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX);

        uint256[] memory proposalIds = vote.getVotedStillRelevantProposals(depositor0);
        assertEq(proposalIds.length, 1);
        assertEq(proposalIds[0], PROPOSAL_2_ID);
    }

    /// @dev The `beforeEach` of `describe("#deleteExpiredVoterProposalId()")`.
    function _setUpTwoVotedProposals() private {
        _depositAndActivate(depositor0, 10 ether);
        _proposeNewProposal();
        _proposeNewProposal();
        _voteProposal(depositor0, PROPOSAL_1_ID, PROPOSAL_1_INDEX, 7 ether, 2 ether, 1 ether);
        _voteProposal(depositor0, PROPOSAL_2_ID, PROPOSAL_2_INDEX, 7 ether, 2 ether, 1 ether);
    }

    // =========================================================================
    //                      #setPauser() tests (4)
    // =========================================================================

    // 36
    function test_SetPauser_SetsCorrectPauserAddress() public {
        vm.prank(owner);
        vote.setPauser();
        assertEq(vote.pauser(), owner);
    }

    // 37
    function test_SetPauser_EmitsPauserSetEvent() public {
        vm.expectEmit(true, true, true, true, address(vote));
        emit PauserSet(owner);
        vm.prank(owner);
        vote.setPauser();
    }

    // 38
    function test_SetPauser_RevertsWhenCalledByNonOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonOwner);
        vote.setPauser();
    }

    // 39
    function test_SetPauser_WhenOwnerChanged_SetsNewOwner() public {
        vm.prank(owner);
        vote.transferOwnership(nonOwner);

        vm.prank(nonOwner);
        vote.setPauser();
        assertEq(vote.pauser(), nonOwner);
    }

    // =========================================================================
    //                        #pause() tests (3)
    // =========================================================================

    // 40
    function test_Pause_CanBeCalledByPauser() public {
        vm.prank(pauser);
        vote.pause();
        assertTrue(vote.isPaused());
    }

    // 41
    function test_Pause_EmitsContractPausedEvent() public {
        vm.expectEmit(true, true, true, true, address(vote));
        emit ContractPaused();
        vm.prank(pauser);
        vote.pause();
    }

    // 42
    function test_Pause_RevertsWhenCalledByRandomAccount() public {
        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonOwner);
        vote.pause();
        assertFalse(vote.isPaused());
    }

    // =========================================================================
    //                       #unpause() tests (3)
    // =========================================================================

    // 43
    function test_Unpause_CanBeCalledByPauser() public {
        vm.prank(pauser);
        vote.pause();

        vm.prank(pauser);
        vote.unpause();
        assertFalse(vote.isPaused());
    }

    // 44
    function test_Unpause_EmitsContractUnpausedEvent() public {
        vm.prank(pauser);
        vote.pause();

        vm.expectEmit(true, true, true, true, address(vote));
        emit ContractUnpaused();
        vm.prank(pauser);
        vote.unpause();
    }

    // 45
    function test_Unpause_RevertsWhenCalledByRandomAccount() public {
        vm.prank(pauser);
        vote.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.OnlyPauser.selector));
        vm.prank(nonOwner);
        vote.unpause();
        assertTrue(vote.isPaused());
    }

    // =========================================================================
    //                     when paused tests (3)
    // =========================================================================

    // 46
    function test_WhenPaused_CantCallDeleteExpiredVoterProposalId() public {
        vm.prank(pauser);
        vote.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(depositor0);
        vote.deleteExpiredVoterProposalId(depositor0, 0, 0);
    }

    // 47
    function test_WhenPaused_CantCallUpdateHistory() public {
        vm.prank(pauser);
        vote.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(depositor0);
        vote.updateHistoryAndReturnLockedStCeloInVoting(depositor0);
    }

    // 48
    function test_WhenPaused_CantCallDeleteExpiredProposalTimestamp() public {
        vm.prank(pauser);
        vote.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.Paused.selector));
        vm.prank(depositor0);
        vote.deleteExpiredProposalTimestamp(0);
    }
}
