// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./EndToEndTestBase.sol";

/**
 * @title EndToEndVoteProposalTest
 * @notice Port of test-ts/end-to-end-vote-proposal.test.ts ("e2e governance vote").
 */
contract EndToEndVoteProposalTest is EndToEndTestBase {
    uint256 internal constant AMOUNT_OF_CELO_TO_DEPOSIT = 6 ether;
    uint256 internal constant REWARDS_GROUP_0 = 100 ether;
    uint256 internal constant REWARDS_GROUP_1 = 150 ether;
    uint256 internal constant REWARDS_GROUP_2 = 200 ether;

    /// @dev ContractKit's `propose([tx], url)` for a single `owner()` call.
    bytes internal constant PROPOSAL_INPUT = hex"8da5cb5b";

    address internal specificGroupStrategyDifferentFromActive;

    /// @dev Kept in storage so that the long test bodies do not run out of stack slots.
    uint256 internal depositor0VotedWeight;
    uint256 internal depositor1VotingPower;
    uint256 internal proposalId;
    uint256 internal proposalId2;

    function setUp() public override {
        super.setUp();
        specificGroupStrategyDifferentFromActive = groups[5];

        /**
         * @dev Deviation: the ganache devchain of the original suite charged a negligible
         *      governance deposit, the anvil devchain charges 100 CELO per proposal. depositor1
         *      makes three proposals on top of its 6 CELO deposit and the 10 CELO it sends to
         *      the approver, so it is funded with those deposits here.
         */
        vm.deal(depositor1, depositor1.balance + 3 * celoGovernance.minDeposit());

        address approver = celoGovernance.approver();
        vm.prank(depositor1);
        (bool success, ) = approver.call{value: 10 ether}("");
        require(success, "could not fund the approver");
    }

    /// @dev groups[5] is elected on MockGroupHealth on top of the activated groups.
    function _groupsToElect() internal view override returns (address[] memory) {
        return _activatedGroupsPlus(groups[5]);
    }

    function test_VoteProposal() public {
        uint256 referendumStageDuration = celoGovernance.getReferendumStageDuration();

        _depositAndDistributeRewards();
        _proposeAndDequeue();

        uint256 depositor0NonVotedVotes = 100000;

        uint256 depositor0VotingPower = vote.getVoteWeight(depositor0);
        depositor0VotedWeight = depositor0VotingPower - depositor0NonVotedVotes;
        depositor1VotingPower = vote.getVoteWeight(depositor1);

        vm.prank(depositor1);
        manager.voteProposal(proposalId, 0, depositor1VotingPower, 0, 0);

        vm.prank(depositor1);
        manager.voteProposal(proposalId2, 1, depositor1VotingPower, 0, 0);

        vm.prank(depositor0);
        manager.voteProposal(proposalId2, 1, depositor0VotedWeight, 0, 0);

        assertEq(stakedCelo.balanceOf(depositor1), 0);
        assertEq(stakedCelo.lockedVoteBalanceOf(depositor1), AMOUNT_OF_CELO_TO_DEPOSIT);

        Vote.ProposalVoteRecord memory voteRecord = vote.getVoteRecord(proposalId);
        assertTrue(voteRecord.proposalId == proposalId);

        // The original compares the strings of both values through a two argument `expect`,
        // which chai treats as value plus message: the computation is kept, nothing is asserted.
        manager.toCelo(stakedCelo.balanceOf(depositor1));

        assertEq(voteRecord.yesVotes, depositor1VotingPower);

        (uint256 yesVotesProposal1, , ) = celoGovernance.getVoteTotals(proposalId);
        assertEq(yesVotesProposal1, depositor1VotingPower);

        (uint256 yesVotesProposal2, , ) = celoGovernance.getVoteTotals(proposalId2);
        assertEq(yesVotesProposal2, depositor1VotingPower + depositor0VotedWeight);

        vm.prank(depositor0);
        manager.voteProposal(proposalId2, 1, 0, depositor0VotedWeight, 0);

        (uint256 yesAfterChangeToNo, uint256 noAfterChangeToNo, ) = celoGovernance.getVoteTotals(
            proposalId2
        );
        assertEq(yesAfterChangeToNo, depositor1VotingPower);
        assertEq(noAfterChangeToNo, depositor0VotedWeight);

        vm.prank(depositor1);
        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        stakedCelo.transfer(address(manager), AMOUNT_OF_CELO_TO_DEPOSIT);

        timeTravel(referendumStageDuration + 1);

        manager.unlockBalance(depositor1);

        vm.prank(depositor1);
        stakedCelo.transfer(address(manager), AMOUNT_OF_CELO_TO_DEPOSIT / 2);

        vm.prank(depositor1);
        stakedCelo.transfer(address(manager), AMOUNT_OF_CELO_TO_DEPOSIT / 2);

        uint256 lockedStakedCeloDepositor0 = stakedCelo.lockedVoteBalanceOf(depositor0);
        uint256 lockedStakedCeloDepositor1 = stakedCelo.lockedVoteBalanceOf(depositor1);

        assertEq(lockedStakedCeloDepositor1, 0);

        uint256 depositor0StCeloVotedWith = manager.toStakedCelo(depositor0VotedWeight);
        assertEq(lockedStakedCeloDepositor0, depositor0StCeloVotedWith);
    }

    function test_VoteProposalAndChangeStrategy() public {
        _depositAndDistributeRewards();
        _proposeAndDequeue();

        depositor1VotingPower = vote.getVoteWeight(depositor1);

        vm.prank(depositor1);
        manager.voteProposal(proposalId, 0, depositor1VotingPower, 0, 0);

        vm.prank(depositor1);
        manager.changeStrategy(specificGroupStrategyDifferentFromActive);

        (uint256 stCeloInStrategyBeforeChangeStrategy, , ) = specificGroupStrategy
            .getStCeloInGroup(specificGroupStrategyDifferentFromActive);
        assertEq(stCeloInStrategyBeforeChangeStrategy, AMOUNT_OF_CELO_TO_DEPOSIT);
    }

    /// @dev The deposits, the two activation rounds and the epoch rewards both tests share.
    function _depositAndDistributeRewards() private {
        deposit(depositor0, AMOUNT_OF_CELO_TO_DEPOSIT);
        deposit(depositor1, AMOUNT_OF_CELO_TO_DEPOSIT);
        assertEq(stakedCelo.balanceOf(depositor1), AMOUNT_OF_CELO_TO_DEPOSIT);

        activateAndVote();
        mineToNextEpoch();
        activateAndVote();

        distributeRewards(0, REWARDS_GROUP_0);
        distributeRewards(1, REWARDS_GROUP_1);
        distributeRewards(2, REWARDS_GROUP_2);
    }

    /// @dev Creates the three governance proposals of the original tests and dequeues them.
    function _proposeAndDequeue() private {
        uint256 dequeueFrequency = celoGovernance.dequeueFrequency();

        timeTravel(dequeueFrequency + 1);
        proposalId = _propose(address(manager), "http://www.descriptionUrl.com");

        timeTravel(dequeueFrequency + 1);
        proposalId2 = _propose(address(account), "http://www.descriptionUrl2.com");

        timeTravel(dequeueFrequency + 1);
        _propose(address(account), "http://www.descriptionUrl2.com");

        timeTravel(dequeueFrequency + 1);
        vm.prank(depositor1);
        celoGovernance.dequeueProposalsIfReady();
    }

    /// @dev Ports GovernanceWrapper.propose for a proposal with a single `owner()` transaction.
    function _propose(address destination, string memory descriptionUrl)
        private
        returns (uint256)
    {
        address[] memory destinations = new address[](1);
        destinations[0] = destination;
        uint256[] memory values = new uint256[](1);
        uint256[] memory dataLengths = new uint256[](1);
        dataLengths[0] = PROPOSAL_INPUT.length;

        uint256 minDeposit = celoGovernance.minDeposit();
        vm.prank(depositor1);
        return
            celoGovernance.propose{value: minDeposit}(
                values,
                destinations,
                PROPOSAL_INPUT,
                dataLengths,
                descriptionUrl
            );
    }
}
