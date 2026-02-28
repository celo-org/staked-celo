// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/deploy/TestAccountDeployHelper.sol";
import "../contracts/Vote.sol";
import "../contracts/Pausable.sol";
import "../contracts/common/Errors.sol";
import "../contracts/interfaces/IGovernance.sol";

// Enhanced Governance mock for Vote tests.
// MockGovernance returns 0 for getProposal timestamps and 11 for referendum duration.
// This mock stores proposal timestamps and vote totals per proposal, enabling
// realistic Vote contract testing.
contract VoteTestGovernance is IGovernance {
    uint256 public referendumDuration;

    mapping(uint256 => uint256) public proposalTimestamps;

    struct ProposalVotes {
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
    }
    mapping(uint256 => ProposalVotes) internal _proposalVotes;

    constructor(uint256 _referendumDuration) {
        referendumDuration = _referendumDuration;
    }

    function setProposalTimestamp(uint256 proposalId, uint256 timestamp) external {
        proposalTimestamps[proposalId] = timestamp;
    }

    function getProposal(
        uint256 proposalId
    )
        external
        view
        override
        returns (address, uint256, uint256, uint256, string memory)
    {
        return (address(0), 0, proposalTimestamps[proposalId], 0, "");
    }

    function getReferendumStageDuration() external view override returns (uint256) {
        return referendumDuration;
    }

    function votePartially(
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) external override returns (bool) {
        require(proposalTimestamps[proposalId] != 0, "Proposal not dequeued");
        _proposalVotes[proposalId] = ProposalVotes(yesVotes, noVotes, abstainVotes);
        return true;
    }

    function getVoteTotals(
        uint256 proposalId
    ) external view returns (uint256, uint256, uint256) {
        ProposalVotes memory v = _proposalVotes[proposalId];
        return (v.yesVotes, v.noVotes, v.abstainVotes);
    }
}

// Extended VM interface for cheatcodes not in CeloTestVm.
interface VoteTestVm {
    function mockCall(address callee, bytes calldata data, bytes calldata returnData) external;
}

contract VoteTest is TestAccountDeployHelper {
    VoteTestGovernance internal testGov;

    // Test addresses
    address internal depositor0;
    address internal depositor1;
    address internal nonStakedCelo;
    address internal nonAccount;
    address internal nonOwner;
    address internal voter;
    address internal pauser;

    // Groups
    address[] internal activatedGroupAddresses;

    uint256 internal constant REFERENDUM_DURATION = 86400; // 1 day

    // Events for expectEmit
    event ContractPaused();
    event ContractUnpaused();
    event PauserSet(address pauser);
    event LockedStCeloInVoting(address account, uint256 lockedCelo);

    function setUp() public {
        // Deploy base infrastructure
        deployTestVote();

        // Deploy enhanced governance mock and register it
        testGov = new VoteTestGovernance(REFERENDUM_DURATION);
        vm.prank(deployer);
        IRegistry(mockRegistryAddr).setAddressFor("Governance", address(testGov));

        // Mock Election.getNumVotesReceivable to return large value so deposit() works
        VoteTestVm(address(vm)).mockCall(
            address(mockElection),
            abi.encodeWithSelector(IElection.getNumVotesReceivable.selector),
            abi.encode(type(uint256).max)
        );

        // Create test addresses
        depositor0 = makeAddr("depositor0");
        depositor1 = makeAddr("depositor1");
        nonStakedCelo = makeAddr("nonStakedCelo");
        nonAccount = makeAddr("nonAccount");
        nonOwner = makeAddr("nonOwner");
        voter = makeAddr("voter");
        pauser = owner;

        // Fund accounts
        vm.deal(depositor0, 300 ether);
        vm.deal(depositor1, 300 ether);
        vm.deal(nonStakedCelo, 100 ether);
        vm.deal(nonOwner, 100 ether);
        vm.deal(nonAccount, 100 ether);
        vm.deal(voter, 300 ether);

        // Set up groups
        activatedGroupAddresses = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            (address group, ) = randomSigner(11000 ether);
            activatedGroupAddresses[i] = group;
        }

        // Wire dependencies
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

        // Set groups as valid in MockGroupHealth
        for (uint256 i = 0; i < 3; i++) {
            mockGroupHealth.setGroupValidity(activatedGroupAddresses[i], true);
        }

        // Add and activate groups in DefaultStrategy
        address previousKey = ADDRESS_ZERO;
        for (uint256 i = 0; i < 3; i++) {
            mockDefaultStrategy.addActivatableGroup(activatedGroupAddresses[i]);
            mockDefaultStrategy.activateGroup(
                activatedGroupAddresses[i],
                ADDRESS_ZERO,
                previousKey
            );
            previousKey = activatedGroupAddresses[i];
        }
        vm.stopPrank();
    }

    // =========================================================================
    //                          HELPERS
    // =========================================================================

    function _deposit(address depositor, uint256 amount) internal {
        vm.prank(depositor);
        manager.deposit{value: amount}();
    }

    function _proposeNewProposal(uint256 proposalId) internal {
        testGov.setProposalTimestamp(proposalId, block.timestamp);
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

    function _checkGovernanceTotalVotes(
        uint256 proposalId,
        uint256 expectedYes,
        uint256 expectedNo,
        uint256 expectedAbstain
    ) internal view {
        (uint256 yes, uint256 no, uint256 abstain) = testGov.getVoteTotals(proposalId);
        assertEq(yes, expectedYes);
        assertEq(no, expectedNo);
        assertEq(abstain, expectedAbstain);
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
        _deposit(depositor0, amountOfCeloToDeposit);
        _proposeNewProposal(1);

        // Check initial vote weight
        uint256 initialVoteWeight = vote.getVoteWeight(depositor0);
        assertEq(initialVoteWeight, amountOfCeloToDeposit);

        // Get initial balances
        uint256 initialRegularBalance = stakedCelo.balanceOf(depositor0);
        uint256 initialLockedBalance = stakedCelo.lockedVoteBalanceOf(depositor0);
        assertEq(initialLockedBalance, 0);

        // Vote to create locked stCELO
        uint256 yesVotes = 7 ether;
        uint256 noVotes = 2 ether;
        uint256 abstainVotes = 1 ether;
        _voteProposal(depositor0, 1, 0, yesVotes, noVotes, abstainVotes);

        // After voting, verify locked balance exists
        uint256 finalRegularBalance = stakedCelo.balanceOf(depositor0);
        uint256 finalLockedBalance = stakedCelo.lockedVoteBalanceOf(depositor0);
        assertTrue(finalLockedBalance > 0);

        // Total stCELO (regular + locked) should equal initial regular balance
        uint256 totalStCeloBalance = finalRegularBalance + finalLockedBalance;
        assertEq(totalStCeloBalance, initialRegularBalance);

        // Vote weight should include both regular and locked stCELO
        uint256 finalVoteWeight = vote.getVoteWeight(depositor0);
        uint256 expectedVoteWeight = vote.toCelo(totalStCeloBalance);
        assertEq(finalVoteWeight, expectedVoteWeight);
        assertEq(finalVoteWeight, amountOfCeloToDeposit);
    }

    // =========================================================================
    //                  #getReferendumDuration() tests (1)
    // =========================================================================

    // 4
    function test_GetReferendumDuration_ReturnsSameAsGovernance() public {
        uint256 referendumDuration = vote.getReferendumDuration();
        assertEq(referendumDuration, REFERENDUM_DURATION);
    }

    // =========================================================================
    //                    #voteProposal() tests (6)
    // =========================================================================

    // 5
    function test_VoteProposal_RevertsWhenNoStCelo() public {
        _proposeNewProposal(1);
        vm.expectRevert(abi.encodeWithSelector(Vote.NoStakedCelo.selector, depositor0));
        vm.prank(depositor0);
        manager.voteProposal(1, 0, 1, 0, 0);
    }

    // 6
    function test_VoteProposal_WhenDeposited_RevertsWhenVotingMoreThanBalance() public {
        _proposeNewProposal(1);
        _deposit(depositor0, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Vote.NotEnoughStakedCelo.selector, depositor0)
        );
        vm.prank(depositor0);
        manager.voteProposal(1, 0, 8 ether, 2 ether, 1 ether);
    }

    // 7
    function test_VoteProposal_WhenDeposited_RevertsWhenVotingForNonExistingProposal() public {
        _proposeNewProposal(1);
        _deposit(depositor0, 10 ether);

        // Proposal 100 has no timestamp set, so governance.votePartially reverts
        vm.expectRevert(bytes("Proposal not dequeued"));
        vm.prank(depositor0);
        manager.voteProposal(100, 0, 7 ether, 2 ether, 1 ether);
    }

    // 8
    function test_VoteProposal_WhenDeposited_WhenVoted_ReturnsCorrectVotes() public {
        _proposeNewProposal(1);
        _deposit(depositor0, 10 ether);

        uint256 yesVotes = 7 ether;
        uint256 noVotes = 2 ether;
        uint256 abstainVotes = 1 ether;
        _voteProposal(depositor0, 1, 0, yesVotes, noVotes, abstainVotes);

        _checkGovernanceTotalVotes(1, yesVotes, noVotes, abstainVotes);
    }

    // 9
    function test_VoteProposal_WhenDeposited_WhenVoted_ReturnsCorrectVotesWhenRevoted() public {
        _proposeNewProposal(1);
        _deposit(depositor0, 10 ether);

        // Initial vote
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        // Revote
        uint256 yesVotesRevote = 5 ether;
        uint256 noVotesRevote = 3 ether;
        uint256 abstainVotesRevote = 1 ether;
        _voteProposal(depositor0, 1, 0, yesVotesRevote, noVotesRevote, abstainVotesRevote);

        _checkGovernanceTotalVotes(1, yesVotesRevote, noVotesRevote, abstainVotesRevote);
    }

    // 10
    function test_VoteProposal_WhenVotingOnTwoProposals_ReturnsCorrectVotes() public {
        uint256 proposal2Id = 2;
        uint256 proposal2Index = 1;
        uint256 proposal3Id = 3;
        uint256 proposal3Index = 2;

        uint256 amountOfCeloToDeposit = 10 ether;

        uint256[2] memory yesVotes = [uint256(6 ether), uint256(2 ether)];
        uint256[2] memory noVotes = [uint256(2 ether), uint256(3 ether)];
        uint256[2] memory abstainVotes = [uint256(1 ether), uint256(4 ether)];

        uint256[2] memory yesVotesD1 = [uint256(1 ether), uint256(4 ether)];
        uint256[2] memory noVotesD1 = [uint256(2 ether), uint256(3 ether)];
        uint256[2] memory abstainVotesD1 = [uint256(3 ether), uint256(1 ether)];

        // Setup: deposit for both depositors, create proposals
        _deposit(depositor0, amountOfCeloToDeposit);
        _deposit(depositor1, amountOfCeloToDeposit);
        _proposeNewProposal(proposal2Id);
        _proposeNewProposal(proposal3Id);

        // Depositor0 votes on both proposals
        _voteProposal(depositor0, proposal2Id, proposal2Index, yesVotes[0], noVotes[0], abstainVotes[0]);
        _voteProposal(depositor0, proposal3Id, proposal3Index, yesVotes[1], noVotes[1], abstainVotes[1]);

        // Depositor1 votes on both proposals
        _voteProposal(depositor1, proposal2Id, proposal2Index, yesVotesD1[0], noVotesD1[0], abstainVotesD1[0]);
        _voteProposal(depositor1, proposal3Id, proposal3Index, yesVotesD1[1], noVotesD1[1], abstainVotesD1[1]);

        // Check totals for proposal 2
        _checkGovernanceTotalVotes(
            proposal2Id,
            yesVotes[0] + yesVotesD1[0],
            noVotes[0] + noVotesD1[0],
            abstainVotes[0] + abstainVotesD1[0]
        );

        // Check totals for proposal 3
        _checkGovernanceTotalVotes(
            proposal3Id,
            yesVotes[1] + yesVotesD1[1],
            noVotes[1] + noVotesD1[1],
            abstainVotes[1] + abstainVotesD1[1]
        );
    }

    // =========================================================================
    //                    #getVoteRecord() tests (3)
    // =========================================================================

    // 11
    function test_GetVoteRecord_ReturnsEmptyWhenNotVoted() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        Vote.ProposalVoteRecord memory record = vote.getVoteRecord(1);

        assertEq(record.proposalId, 0);
        assertEq(record.yesVotes, 0);
        assertEq(record.noVotes, 0);
        assertEq(record.abstainVotes, 0);
    }

    // 12
    function test_GetVoteRecord_WhenVoted_ReturnsCorrectValues() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        uint256 yesVotes = 7 ether;
        uint256 noVotes = 2 ether;
        uint256 abstainVotes = 1 ether;
        _voteProposal(depositor0, 1, 0, yesVotes, noVotes, abstainVotes);

        Vote.ProposalVoteRecord memory record = vote.getVoteRecord(1);

        assertEq(record.proposalId, 1);
        assertEq(record.yesVotes, yesVotes);
        assertEq(record.noVotes, noVotes);
        assertEq(record.abstainVotes, abstainVotes);
    }

    // 13
    function test_GetVoteRecord_WhenVoted_UpdatesWhenRevoted() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        // Initial vote
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        // Revote
        uint256 yesVotesRevote = 5 ether;
        uint256 noVotesRevote = 3 ether;
        uint256 abstainVotesRevote = 1 ether;
        _voteProposal(depositor0, 1, 0, yesVotesRevote, noVotesRevote, abstainVotesRevote);

        Vote.ProposalVoteRecord memory record = vote.getVoteRecord(1);

        assertEq(record.proposalId, 1);
        assertEq(record.yesVotes, yesVotesRevote);
        assertEq(record.noVotes, noVotesRevote);
        assertEq(record.abstainVotes, abstainVotesRevote);
    }

    // =========================================================================
    //                #getLockedStCeloInVoting() tests (3)
    // =========================================================================

    // 14
    function test_GetLockedStCeloInVoting_ReturnsZeroWhenNotVoted() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        uint256 lockedCelo = vote.getLockedStCeloInVoting(depositor0);
        assertEq(lockedCelo, 0);
    }

    // 15
    function test_GetLockedStCeloInVoting_WhenVoted_ReturnsLockedCelo() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        uint256 yesVotes = 7 ether;
        uint256 noVotes = 2 ether;
        uint256 abstainVotes = 1 ether;
        uint256 totalVotes = yesVotes + noVotes + abstainVotes;
        _voteProposal(depositor0, 1, 0, yesVotes, noVotes, abstainVotes);

        uint256 lockedCelo = vote.getLockedStCeloInVoting(depositor0);
        assertEq(lockedCelo, totalVotes);
    }

    // 16
    function test_GetLockedStCeloInVoting_WhenVoted_UpdatesWhenRevoted() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        // Initial vote
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        // Revote
        uint256 yesVotesRevote = 5 ether;
        uint256 noVotesRevote = 3 ether;
        uint256 abstainVotesRevote = 1 ether;
        uint256 totalRevotes = yesVotesRevote + noVotesRevote + abstainVotesRevote;
        _voteProposal(depositor0, 1, 0, yesVotesRevote, noVotesRevote, abstainVotesRevote);

        uint256 lockedCelo = vote.getLockedStCeloInVoting(depositor0);
        assertEq(lockedCelo, totalRevotes);
    }

    // =========================================================================
    //      #updateHistoryAndReturnLockedStCeloInVoting() tests (6)
    // =========================================================================

    // 17
    function test_UpdateHistory_ReturnsZeroWhenNotVoted() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        vm.expectEmit(true, true, true, true);
        emit LockedStCeloInVoting(depositor0, 0);
        vote.updateHistoryAndReturnLockedStCeloInVoting(depositor0);
    }

    // 18
    function test_UpdateHistory_WhenVoted_ReturnsLockedCelo() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        uint256 yesVotes = 7 ether;
        uint256 noVotes = 2 ether;
        uint256 abstainVotes = 1 ether;
        uint256 totalVotes = yesVotes + noVotes + abstainVotes;
        _voteProposal(depositor0, 1, 0, yesVotes, noVotes, abstainVotes);

        vm.expectEmit(true, true, true, true);
        emit LockedStCeloInVoting(depositor0, totalVotes);
        vote.updateHistoryAndReturnLockedStCeloInVoting(depositor0);
    }

    // 19
    function test_UpdateHistory_WhenVoted_ReturnsLockedCeloWithMaxProposals() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        uint256 yesVotes = 7 ether;
        uint256 noVotes = 2 ether;
        uint256 abstainVotes = 1 ether;
        uint256 totalVotes = yesVotes + noVotes + abstainVotes;

        // Vote on proposal 1 first
        _voteProposal(depositor0, 1, 0, yesVotes, noVotes, abstainVotes);

        // Create and vote on 20 more proposals (21 total concurrent)
        uint256 currentMainnetConcurrentProposals = 21;
        for (uint256 i = 0; i < currentMainnetConcurrentProposals; i++) {
            _proposeNewProposal(i + 2); // proposals 2-22
        }
        for (uint256 i = 0; i < currentMainnetConcurrentProposals; i++) {
            _voteProposal(depositor0, i + 1, i, yesVotes, noVotes, abstainVotes);
        }

        vm.expectEmit(true, true, true, true);
        emit LockedStCeloInVoting(depositor0, totalVotes);
        vote.updateHistoryAndReturnLockedStCeloInVoting(depositor0);
    }

    // 20
    function test_UpdateHistory_WhenVoted_UpdatesWhenRevoted() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);

        // Initial vote
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        // Revote
        uint256 yesVotesRevote = 5 ether;
        uint256 noVotesRevote = 3 ether;
        uint256 abstainVotesRevote = 1 ether;
        uint256 totalRevotes = yesVotesRevote + noVotesRevote + abstainVotesRevote;
        _voteProposal(depositor0, 1, 0, yesVotesRevote, noVotesRevote, abstainVotesRevote);

        vm.expectEmit(true, true, true, true);
        emit LockedStCeloInVoting(depositor0, totalRevotes);
        vote.updateHistoryAndReturnLockedStCeloInVoting(depositor0);
    }

    // 21
    function test_UpdateHistory_WhenVotedOn3Proposals_ReturnsCorrectOrder() public {
        _deposit(depositor0, 10 ether);

        // Create proposals with different timestamps
        _proposeNewProposal(1);
        _proposeNewProposal(2);
        timeTravel(100);
        _proposeNewProposal(3);

        uint256 yesVotesP2 = 1 ether;
        uint256 noVotesP2 = 2 ether;
        uint256 abstainVotesP2 = 3 ether;

        uint256 yesVotes = 7 ether;
        uint256 noVotes = 2 ether;
        uint256 abstainVotes = 1 ether;

        uint256 yesVotesP3 = 2 ether;
        uint256 noVotesP3 = 3 ether;
        uint256 abstainVotesP3 = 4 ether;

        // Vote in order: 2, 1, 3
        _voteProposal(depositor0, 2, 1, yesVotesP2, noVotesP2, abstainVotesP2);
        _voteProposal(depositor0, 1, 0, yesVotes, noVotes, abstainVotes);
        _voteProposal(depositor0, 3, 2, yesVotesP3, noVotesP3, abstainVotesP3);

        uint256[] memory votedProposals = vote.getVotedStillRelevantProposals(depositor0);
        uint256 proposal1Timestamp = vote.proposalTimestamps(1);
        uint256 proposal2Timestamp = vote.proposalTimestamps(2);
        uint256 proposal3Timestamp = vote.proposalTimestamps(3);

        assertEq(votedProposals.length, 3);
        assertEq(votedProposals[0], 2);
        assertEq(votedProposals[1], 1);
        assertEq(votedProposals[2], 3);

        assertTrue(proposal1Timestamp > 0);
        assertTrue(proposal2Timestamp > 0);
        assertTrue(proposal3Timestamp > 0);
    }

    // 22
    function test_UpdateHistory_WhenVotedOn3Proposals_RemovesExpiredProposal() public {
        _deposit(depositor0, 10 ether);

        // Create proposal 1 at current time
        _proposeNewProposal(1);

        // Create proposals 2 and 3 later
        timeTravel(REFERENDUM_DURATION / 2);
        _proposeNewProposal(2);
        _proposeNewProposal(3);

        // Vote in order: 2, 1, 3
        _voteProposal(depositor0, 2, 1, 1 ether, 2 ether, 3 ether);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);
        _voteProposal(depositor0, 3, 2, 2 ether, 3 ether, 4 ether);

        // Time travel so proposal 1 expires but 2 and 3 don't
        timeTravel(REFERENDUM_DURATION / 2 + 1);

        // Call updateHistory to remove expired proposals
        vote.updateHistoryAndReturnLockedStCeloInVoting(depositor0);

        uint256 proposal1Timestamp = vote.proposalTimestamps(1);
        uint256 proposal2Timestamp = vote.proposalTimestamps(2);
        uint256 proposal3Timestamp = vote.proposalTimestamps(3);

        uint256[] memory votedProposals = vote.getVotedStillRelevantProposals(depositor0);
        assertEq(votedProposals.length, 2);
        // After removal, proposal 1 is replaced by the last element (3), then popped
        // So order becomes [2, 3] or [3, 2] depending on swap
        // The swap replaces index 1 (proposal 1) with last element (proposal 3), then pops
        // Original: [2, 1, 3] → swap index 1 with last → [2, 3] (3 moved to index 1, then pop)
        assertEq(votedProposals[0], 2);
        assertEq(votedProposals[1], 3);

        assertEq(proposal1Timestamp, 0);
        assertTrue(proposal2Timestamp > 0);
        assertTrue(proposal3Timestamp > 0);
    }

    // =========================================================================
    //                    #revokeVotes() tests (2)
    // =========================================================================

    // 23
    function test_RevokeVotes_RevertsWhenNoStCelo() public {
        vm.expectRevert(abi.encodeWithSelector(Vote.NoStakedCelo.selector, depositor0));
        vm.prank(depositor0);
        manager.revokeVotes(1, 0);
    }

    // 24
    function test_RevokeVotes_WhenDeposited_WhenVoted_ReturnsCorrectValues() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        vm.prank(depositor0);
        manager.revokeVotes(1, 0);

        _checkGovernanceTotalVotes(1, 0, 0, 0);
    }

    // =========================================================================
    //                    #setDependencies() tests (3)
    // =========================================================================

    // 25
    function test_SetDependencies_RevertsWithZeroStCeloAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        vm.prank(owner);
        vote.setDependencies(ADDRESS_ZERO, nonAccount);
    }

    // 26
    function test_SetDependencies_RevertsWithZeroAccountAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressZeroNotAllowed.selector));
        vm.prank(owner);
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
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        uint256[] memory proposalIds = vote.getVotedStillRelevantProposals(depositor0);
        assertEq(proposalIds.length, 1);
        assertEq(proposalIds[0], 1);
    }

    // 29
    function test_DeleteExpiredProposalTimestamp_HasProposalTimestamp() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        uint256 timestamp = vote.proposalTimestamps(1);
        assertTrue(timestamp > 0);
    }

    // 30
    function test_DeleteExpiredProposalTimestamp_RevertsWhenNotExpired() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Vote.ProposalNotExpired.selector));
        vote.deleteExpiredProposalTimestamp(1);
    }

    // 31
    function test_DeleteExpiredProposalTimestamp_WhenExpired_DeletesTimestamp() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);

        // Time travel past referendum duration
        timeTravel(REFERENDUM_DURATION + 1);

        vote.deleteExpiredProposalTimestamp(1);
        uint256 timestamp = vote.proposalTimestamps(1);
        assertEq(timestamp, 0);
    }

    // =========================================================================
    //              #deleteExpiredVoterProposalId() tests (4)
    // =========================================================================

    // 32
    function test_DeleteExpiredVoterProposalId_VoterHasProposalAsVoted() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _proposeNewProposal(2);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);
        _voteProposal(depositor0, 2, 1, 7 ether, 2 ether, 1 ether);

        uint256[] memory proposalIds = vote.getVotedStillRelevantProposals(depositor0);
        assertEq(proposalIds.length, 2);
        assertEq(proposalIds[0], 1);
        assertEq(proposalIds[1], 2);
    }

    // 33
    function test_DeleteExpiredVoterProposalId_RevertsWhenIncorrectIndex() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _proposeNewProposal(2);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);
        _voteProposal(depositor0, 2, 1, 7 ether, 2 ether, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Vote.IncorrectIndex.selector));
        vote.deleteExpiredVoterProposalId(depositor0, 1, 1); // wrong index
    }

    // 34
    function test_DeleteExpiredVoterProposalId_RevertsWhenNotExpired() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _proposeNewProposal(2);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);
        _voteProposal(depositor0, 2, 1, 7 ether, 2 ether, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Vote.ProposalNotExpired.selector));
        vote.deleteExpiredVoterProposalId(depositor0, 1, 0);
    }

    // 35
    function test_DeleteExpiredVoterProposalId_WhenExpired_DeletesProposalFromHistory() public {
        _deposit(depositor0, 10 ether);
        _proposeNewProposal(1);
        _proposeNewProposal(2);
        _voteProposal(depositor0, 1, 0, 7 ether, 2 ether, 1 ether);
        _voteProposal(depositor0, 2, 1, 7 ether, 2 ether, 1 ether);

        // Time travel past referendum duration
        timeTravel(REFERENDUM_DURATION + 1);

        vote.deleteExpiredVoterProposalId(depositor0, 1, 0);

        uint256[] memory proposalIds = vote.getVotedStillRelevantProposals(depositor0);
        assertEq(proposalIds.length, 1);
        assertEq(proposalIds[0], 2);
    }

    // =========================================================================
    //                      #setPauser() tests (4)
    // =========================================================================

    // 36
    function test_SetPauser_SetsCorrectPauserAddress() public {
        vm.prank(owner);
        vote.setPauser();
        address newPauser = vote.pauser();
        assertEq(newPauser, owner);
    }

    // 37
    function test_SetPauser_EmitsPauserSetEvent() public {
        vm.expectEmit(true, true, true, true);
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
        address newPauser = vote.pauser();
        assertEq(newPauser, nonOwner);
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
        vm.expectEmit(true, true, true, true);
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

        vm.expectEmit(true, true, true, true);
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
