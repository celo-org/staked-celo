// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./EndToEndTestBase.sol";

/**
 * @title EndToEndOverflowTest
 * @notice Port of test-ts/end-to-end-overflow.test.ts ("e2e overflow test").
 */
contract EndToEndOverflowTest is EndToEndTestBase {
    uint256 internal constant ZERO = 0;

    /**
     * @dev Deviation: the Hardhat test hardcoded the capacities the ganache devchain ended up
     *      with (40.166666666666666666 / 99.25 / 200.166666666666666666 CELO). `prepareOverflow`
     *      solves the vote amounts from the chain state so that exactly 40 / 100 / 200 CELO of
     *      receivable votes are left, which is what these constants assert.
     */
    uint256 internal constant FIRST_G_CAPACITY = 40 ether;
    uint256 internal constant SECOND_GROUP_CAPACITY = 100 ether;
    uint256 internal constant THIRD_GROUP_CAPACITY = 200 ether;

    address internal specGroupDifferentFromActive;
    address internal specGroupSameAsActive;

    /// @dev Kept in storage to keep the stack of the single test function small.
    uint256 internal g0ReceivableVotes;
    uint256 internal g0ExpectedOverflow;

    function setUp() public override {
        super.setUp();
        specGroupDifferentFromActive = groups[5];
        specGroupSameAsActive = groups[0];
    }

    function _numberOfGroups() internal pure override returns (uint256) {
        return 11;
    }

    /// @dev groups[1] has an extra validator so that it has a higher voting limit.
    function _validatorsPerGroup(uint256 index) internal pure override returns (uint256) {
        return index == 1 ? 2 : 1;
    }

    function _groupBalance() internal pure override returns (uint256) {
        return 21_000 ether;
    }

    function _voterBalance() internal pure override returns (uint256) {
        return 10_000_000_000 ether;
    }

    /// @dev groups[5] is elected on MockGroupHealth on top of the activated groups.
    function _groupsToElect() internal view override returns (address[] memory) {
        return _activatedGroupsPlus(groups[5]);
    }

    function test_DepositTransferAndActivate() public {
        prepareOverflow(defaultStrategy, voter, activatedGroupAddresses, false);
        expectCeloForGroup(groups[0], ZERO);
        expectCeloForGroup(groups[1], ZERO);
        expectCeloForGroup(groups[2], ZERO);
        expectCeloForGroup(specGroupDifferentFromActive, ZERO);
        expectReceivableVotes(groups[0], FIRST_G_CAPACITY);
        expectReceivableVotes(groups[1], SECOND_GROUP_CAPACITY);
        expectReceivableVotes(groups[2], THIRD_GROUP_CAPACITY);
        uint256 celoDeposit = 10 ether;
        uint256 overflow = celoDeposit;

        vm.prank(depositor0);
        manager.changeStrategy(specGroupSameAsActive);
        vm.prank(depositor1);
        manager.changeStrategy(specGroupSameAsActive);
        vm.prank(depositor2);
        manager.changeStrategy(groups[1]);

        deposit(depositor0, celoDeposit);
        expectCeloForGroup(groups[0], celoDeposit);
        expectReceivableVotes(groups[0], FIRST_G_CAPACITY - celoDeposit);
        expectSpecGStCelo(specGroupSameAsActive, celoDeposit, 0);

        (address tail, ) = defaultStrategy.getGroupsTail();
        assertEq(tail, groups[2]);

        deposit(depositor1, FIRST_G_CAPACITY);
        expectCeloForGroup(groups[0], FIRST_G_CAPACITY);
        expectReceivableVotes(groups[0], ZERO);
        expectSpecGStCelo(specGroupSameAsActive, celoDeposit + FIRST_G_CAPACITY, celoDeposit);
        expectVotes(groups[0], ZERO, FIRST_G_CAPACITY, ZERO, ZERO);
        expectVotes(groups[1], ZERO, ZERO, ZERO, ZERO);
        expectVotes(groups[2], ZERO, overflow, ZERO, ZERO);

        (address head, ) = defaultStrategy.getGroupsHead();

        vm.prank(depositor1);
        manager.changeStrategy(specGroupDifferentFromActive);
        rebalanceAllAndActivate();
        expectCeloForGroup(groups[0], celoDeposit);

        expectVotes(specGroupDifferentFromActive, FIRST_G_CAPACITY, ZERO, ZERO, ZERO);
        expectVotes(groups[0], celoDeposit, ZERO, ZERO, ZERO);
        expectVotes(head, ZERO, ZERO, ZERO, ZERO);

        g0ReceivableVotes = manager.getReceivableVotesForGroup(specGroupSameAsActive);
        g0ExpectedOverflow = FIRST_G_CAPACITY - g0ReceivableVotes;
        vm.prank(depositor1);
        manager.changeStrategy(specGroupSameAsActive);

        expectSpecGStCelo(specGroupDifferentFromActive, ZERO, ZERO);
        expectSpecGStCelo(
            specGroupSameAsActive,
            celoDeposit + FIRST_G_CAPACITY,
            g0ExpectedOverflow
        );

        rebalanceAllAndActivate();
        expectCeloForGroup(groups[0], FIRST_G_CAPACITY + celoDeposit - g0ExpectedOverflow);
        expectVotes(specGroupSameAsActive, celoDeposit + g0ReceivableVotes, ZERO, ZERO, ZERO);
        expectVotes(groups[1], g0ExpectedOverflow / 3, ZERO, ZERO, ZERO);
        expectVotes(groups[2], g0ExpectedOverflow / 3, ZERO, ZERO, ZERO);
        // since default group[0] is overflowing - it is not possible to move Celo there
        // this celo stays in the specific strategy
        expectVotes(specGroupDifferentFromActive, g0ExpectedOverflow / 3, ZERO, ZERO, ZERO);

        activateAndVote();

        _depositOutsideCapacityAndRebalanceOverflow();
    }

    /// @dev The tail of the test: a deposit that changes the capacity of groups[1], a vote made
    ///      outside of the protocol and the resulting overflow rebalance.
    function _depositOutsideCapacityAndRebalanceOverflow() private {
        // since new CELO was deposited, capacity was changed
        uint256 newSecondGroupCapacity = manager.getReceivableVotesForGroup(groups[1]);
        uint256 newDeposit = newSecondGroupCapacity / 2;
        lockCelo(voter, newDeposit * 10);

        uint256 newSecondGroupCapacityAfterLock = manager.getReceivableVotesForGroup(groups[1]);
        deposit(depositor2, newDeposit);
        expectReceivableVotes(groups[1], newSecondGroupCapacityAfterLock - newDeposit);

        // someone made deposit outside of the protocol and scheduled votes are not
        // activatable anymore
        uint256 receivableByGroup1 = manager.getReceivableVotesForGroup(groups[1]);
        uint256 scheduledForGroup1 = account.scheduledVotesForGroup(groups[1]);

        uint256 voteAmount = receivableByGroup1 + scheduledForGroup1;
        (address lesser, address greater) = findLesserAndGreaterAfterVote(
            groups[1],
            int256(voteAmount)
        );
        vm.prank(voter);
        celoElection.vote(groups[1], voteAmount, lesser, greater);

        expectVotes(groups[1], g0ExpectedOverflow / 3, newDeposit, ZERO, ZERO);
        expectVotes(groups[2], g0ExpectedOverflow / 3, ZERO, ZERO, ZERO);

        manager.rebalanceOverflow(groups[1], groups[2]);

        expectVotes(groups[1], g0ExpectedOverflow / 3, ZERO, ZERO, ZERO);
        expectVotes(groups[2], g0ExpectedOverflow / 3, scheduledForGroup1, ZERO, ZERO);
    }

    function expectVotes(
        address group,
        uint256 votes,
        uint256 toVote,
        uint256 toRevoke,
        uint256 toWithdraw
    ) internal view {
        assertInRange(account.votesForGroup(group), votes, 1);
        assertInRange(account.scheduledVotesForGroup(group), toVote, 1);
        assertInRange(account.scheduledRevokeForGroup(group), toRevoke, 1);
        assertInRange(account.scheduledWithdrawalsForGroup(group), toWithdraw, 1);
    }

    function expectCeloForGroup(address group, uint256 amount) internal view {
        assertEq(account.getCeloForGroup(group), amount);
    }

    function expectReceivableVotes(address group, uint256 amount) internal view {
        assertEq(manager.getReceivableVotesForGroup(group), amount);
    }

    function expectSpecGStCelo(
        address strategy,
        uint256 total,
        uint256 overflow
    ) internal view {
        (uint256 totalActual, uint256 overflowActual, ) = specificGroupStrategy.getStCeloInGroup(
            strategy
        );
        assertEq(totalActual, total);
        assertEq(overflowActual, overflow);
    }
}
