// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./Managed.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./common/UsingRegistryUpgradeable.sol";
import "./interfaces/IAccount.sol";

/**
 * @title A contract that facilitates voting on behalf of StakedCelo.sol.
 * @notice This contract depends on the Manager to decide how to distribute votes and how to
 * keep track of ownership of CELO voted via this contract.
 */
contract Account is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed, IAccount {
    /**
     * @notice Used to keep track of a pending withdrawal. A similar data structure
     * exists within LockedGold.sol, but it only keeps track of pending withdrawals
     * by the msg.sender to the LockedGold contract.
     * Because this contract facilitates withdrawals for different beneficiaries,
     * this contract must keep track of which beneficiaries correspond to which
     * pending withdrawals to prevent someone from finalizing/taking a pending
     * withdrawal they did not create.
     * @param value The withdrawal amount.
     * @param timestamp The timestamp at which the withdrawal amount becomes available.
     */
    struct PendingWithdrawal {
        uint256 value;
        uint256 timestamp;
    }

    /**
     * @notice Used to keep track of CELO that is scheduled to be used for
     * voting or revoking for a validator group.
     * @param toVote Amount of CELO held by this contract intended to vote for a group.
     * @param toWithdraw Amount of CELO that's scheduled for withdrawal.
     * @param toWithdrawFor Amount of CELO that's scheduled for withdrawal grouped by beneficiary.
     * @param toRevoke Amount of CELO that's scheduled to be revoked.
     */
    struct ScheduledVotes {
        uint256 toVote;
        uint256 toWithdraw;
        mapping(address => uint256) toWithdrawFor;
        uint256 toRevoke;
    }
    /**
     * @notice Keyed by beneficiary address, the related array of pending withdrawals.
     * See `PendingWithdrawal` for more info.
     */
    mapping(address => PendingWithdrawal[]) public pendingWithdrawals;

    /**
     * @notice Keyed by validator group address, the ScheduledVotes struct
     * which holds the amount of CELO that's scheduled to vote, the amount
     * of CELO scheduled to be withdrawn, and the amount of CELO to be
     * withdrawn for each beneficiary.
     */
    mapping(address => ScheduledVotes) private scheduledVotes;

    /**
     * @notice Total amount of CELO scheduled to be withdrawn from all groups
     * by all beneficiaries.
     */
    uint256 public totalScheduledWithdrawals;

    /**
     * @notice Emitted when CELO is scheduled for voting for a given group.
     * @param group The validator group the CELO is intended to vote for.
     * @param amount The amount of CELO scheduled.
     */
    event VotesScheduled(address indexed group, uint256 amount);

    /**
     * @notice Emitted when CELO is scheduled to be revoked from a given group.
     * @param group The validator group the CELO is being revoked from.
     * @param amount The amount of CELO scheduled.
     */
    event RevocationScheduled(address indexed group, uint256 amount);

    /**
     * @notice Emitted when CELO withdrawal is scheduled for a group.
     * @param group The validator group the CELO is withdrawn from.
     * @param withdrawalAmount The amount of CELO requested for withdrawal.
     * @param beneficiary The user for whom the withdrawal amount is intended for.
     */
    event CeloWithdrawalScheduled(
        address indexed beneficiary,
        address indexed group,
        uint256 withdrawalAmount
    );

    /**
     * @notice Emitted when CELO withdrawal kicked off for group. Immediate withdrawals
     * are not included in this event, but can be identified by a GoldToken.sol transfer
     * from this contract.
     * @param group The validator group the CELO is withdrawn from.
     * @param withdrawalAmount The amount of CELO requested for withdrawal.
     * @param beneficiary The user for whom the withdrawal amount is intended for.
     */
    event CeloWithdrawalStarted(
        address indexed beneficiary,
        address indexed group,
        uint256 withdrawalAmount
    );

    /**
     * @notice Emitted when a CELO withdrawal completes for `beneficiary`.
     * @param beneficiary The user for whom the withdrawal amount is intended.
     * @param amount The amount of CELO requested for withdrawal.
     * @param timestamp The timestamp of the pending withdrawal.
     */
    event CeloWithdrawalFinished(address indexed beneficiary, uint256 amount, uint256 timestamp);

    /// @notice Used when the creation of an account with Accounts.sol fails.
    error AccountCreationFailed();

    /// @notice Used when arrays passed for scheduling votes don't have matching lengths.
    error GroupsAndVotesArrayLengthsMismatch();

    /**
     * @notice Used when the sum of votes per groups during vote scheduling
     * doesn't match the `msg.value` sent with the call.
     * @param sentValue The `msg.value` of the call.
     * @param expectedValue The expected sum of votes for groups.
     */
    error TotalVotesMismatch(uint256 sentValue, uint256 expectedValue);

    /// @notice Used when activating of pending votes via Election has failed.
    error ActivatePendingVotesFailed(address group);

    /// @notice Used when voting via Election has failed.
    error VoteFailed(address group, uint256 amount);

    /// @notice Used when call to Election.sol's `revokePendingVotes` fails.
    error RevokePendingFailed(address group, uint256 amount);

    /// @notice Used when call to Election.sol's `revokeActiveVotes` fails.
    error RevokeActiveFailed(address group, uint256 amount);

    /**
     * @notice Used when active + pending votes amount is unable to fulfil a
     * withdrawal request amount.
     */
    error InsufficientRevokableVotes(address group, uint256 amount);

    /// @notice Used when unable to transfer CELO.
    error CeloTransferFailed(address to, uint256 amount);

    /**
     * @notice Used when `pendingWithdrawalIndex` is too high for the
     * beneficiary's pending withdrawals array.
     */
    error PendingWithdrawalIndexTooHigh(
        uint256 pendingWithdrawalIndex,
        uint256 pendingWithdrawalsLength
    );

    /**
     * @notice Used when attempting to schedule more withdrawals
     * than CELO available to the contract.
     * @param group The offending group.
     * @param celoAvailable CELO available to the group across scheduled, pending and active votes.
     * @param celoToWindraw total amount of CELO that would be scheduled to be withdrawn.
     */
    error WithdrawalAmountTooHigh(address group, uint256 celoAvailable, uint256 celoToWindraw);

    /**
     * @notice Used when any of the resolved stakedCeloGroupVoter.pendingWithdrawal
     * values do not match the equivalent record in lockedGold.pendingWithdrawals.
     */
    error InconsistentPendingWithdrawalValues(
        uint256 localPendingWithdrawalValue,
        uint256 lockedGoldPendingWithdrawalValue
    );

    /**
     * @notice Used when any of the resolved stakedCeloGroupVoter.pendingWithdrawal
     * timestamps do not match the equivalent record in lockedGold.pendingWithdrawals.
     */
    error InconsistentPendingWithdrawalTimestamps(
        uint256 localPendingWithdrawalTimestamp,
        uint256 lockedGoldPendingWithdrawalTimestamp
    );

    /// @notice There's no amount of scheduled withdrawal for the given beneficiary and group.
    error NoScheduledWithdrawal(address beneficiary, address group);

    /// @notice Voting for proposal was not successfull.
    error VotingNotSuccessful(uint256 proposalId);

    /**
     * @notice Scheduling transfer was not successfull since
     * total amount of "from" and "to" are not the same.
     */
    error TransferAmountMisalignment();

    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /**
     * @param _registry The address of the Celo Registry.
     * @param _manager The address of the Manager contract.
     * @param _owner The address of the contract owner.
     */
    function initialize(
        address _registry,
        address _manager,
        address _owner
    ) external initializer {
        __UsingRegistry_init(_registry);
        __Managed_init(_manager);
        _transferOwnership(_owner);

        // Create an account so this contract can vote.
        if (!getAccounts().createAccount()) {
            revert AccountCreationFailed();
        }
    }

    /**
     * @notice Deposits CELO sent via msg.value as unlocked CELO intended as
     * votes for groups.
     * @dev Only callable by the Manager contract, which must restrict which groups
     * gets CELO distribution.
     * @param groups The groups the deposited CELO is intended to vote for.
     * @param votes The amount of CELO to schedule for each respective group
     * from `groups`.
     */
    function scheduleVotes(address[] calldata groups, uint256[] calldata votes)
        external
        payable
        onlyManager
    {
        if (groups.length != votes.length) {
            revert GroupsAndVotesArrayLengthsMismatch();
        }

        uint256 totalVotes;
        for (uint256 i = 0; i < groups.length; i++) {
            getAndUpdateToVoteAndToRevoke(groups[i], votes[i], 0);
            totalVotes += votes[i];
        }

        if (totalVotes != uint256(msg.value)) {
            revert TotalVotesMismatch(msg.value, totalVotes);
        }
    }

    /**
     * @notice Schedules votes which will be revoked from some groups and voted to others.
     * @dev Only callable by the Manager contract, which must restrict which groups are valid.
     * @param fromGroups The groups the deposited CELO is intended to be revoked from.
     * @param fromVotes The amount of CELO scheduled to be revoked from each respective group.
     * @param toGroups The groups the transferred CELO is intended to vote for.
     * @param toVotes The amount of CELO to schedule for each respective group
     * from `toGroups`.
     */
    function scheduleTransfer(
        address[] calldata fromGroups,
        uint256[] calldata fromVotes,
        address[] calldata toGroups,
        uint256[] calldata toVotes
    ) external onlyManager {
        if (fromGroups.length != fromVotes.length || toGroups.length != toVotes.length) {
            revert GroupsAndVotesArrayLengthsMismatch();
        }
        uint256 totalFromVotes;
        uint256 totalToVotes;

        for (uint256 i = 0; i < fromGroups.length; i++) {
            getAndUpdateToVoteAndToRevoke(fromGroups[i], 0, fromVotes[i]);
            totalFromVotes += fromVotes[i];
        }

        for (uint256 i = 0; i < toGroups.length; i++) {
            getAndUpdateToVoteAndToRevoke(toGroups[i], toVotes[i], 0);
            totalToVotes += toVotes[i];
        }

        if (totalFromVotes != totalToVotes) {
            revert TransferAmountMisalignment();
        }
    }

    /**
     * @notice Schedule a list of withdrawals to be refunded to a beneficiary.
     * @param groups The groups the deposited CELO is intended to be withdrawn from.
     * @param withdrawals The amount of CELO to withdraw for each respective group.
     * @param beneficiary The account that will receive the CELO once it's withdrawn.
     * from `groups`.
     */
    function scheduleWithdrawals(
        address beneficiary,
        address[] calldata groups,
        uint256[] calldata withdrawals
    ) external onlyManager {
        if (groups.length != withdrawals.length) {
            revert GroupsAndVotesArrayLengthsMismatch();
        }

        uint256 totalWithdrawalsDelta;

        for (uint256 i = 0; i < withdrawals.length; i++) {
            uint256 celoAvailableForGroup = this.getCeloForGroup(groups[i]);
            if (celoAvailableForGroup < withdrawals[i]) {
                revert WithdrawalAmountTooHigh(groups[i], celoAvailableForGroup, withdrawals[i]);
            }

            scheduledVotes[groups[i]].toWithdraw += withdrawals[i];
            scheduledVotes[groups[i]].toWithdrawFor[beneficiary] += withdrawals[i];
            totalWithdrawalsDelta += withdrawals[i];

            emit CeloWithdrawalScheduled(beneficiary, groups[i], withdrawals[i]);
        }

        totalScheduledWithdrawals += totalWithdrawalsDelta;
    }

    /**
     * @notice Starts withdrawal of CELO from `group`. If there is any unlocked CELO for the group,
     * that CELO is used for immediate withdrawal. Otherwise, CELO is taken from pending and active
     * votes, which are subject to the unlock period of LockedGold.sol.
     * @param group The group to withdraw CELO from.
     * @param beneficiary The recipient of the withdrawn CELO.
     * @param lesserAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param greaterAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param lesserAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param greaterAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param index Used by Election's `revokePending` and `revokeActive`. This is the index of
     * `group` in this contract's array of groups it is voting for.
     * @return The amount of immediately withdrawn CELO that is obtained from scheduledVotes
     * for `group`.
     */
    function withdraw(
        address beneficiary,
        address group,
        address lesserAfterPendingRevoke,
        address greaterAfterPendingRevoke,
        address lesserAfterActiveRevoke,
        address greaterAfterActiveRevoke,
        uint256 index
    ) external returns (uint256) {
        uint256 withdrawalAmount = scheduledVotes[group].toWithdrawFor[beneficiary];
        if (withdrawalAmount == 0) {
            revert NoScheduledWithdrawal(beneficiary, group);
        }
        // Emit early to return without needing to emit in multiple places.
        emit CeloWithdrawalStarted(beneficiary, group, withdrawalAmount);
        // Subtract withdrawal amount from all bookkeeping
        scheduledVotes[group].toWithdrawFor[beneficiary] = 0;
        scheduledVotes[group].toWithdraw -= withdrawalAmount;
        totalScheduledWithdrawals -= withdrawalAmount;

        // It might happen that toVotes are from transfers
        // and the contract doesn't have enough CELO.
        (uint256 celoToVoteForGroup, ) = getAndUpdateToVoteAndToRevoke(group, 0, 0);
        uint256 immediateWithdrawalAmount = Math.min(address(this).balance, celoToVoteForGroup);

        if (immediateWithdrawalAmount > 0) {
            if (immediateWithdrawalAmount > withdrawalAmount) {
                immediateWithdrawalAmount = withdrawalAmount;
            }
            scheduledVotes[group].toVote -= immediateWithdrawalAmount;

            // The benefit of using getGoldToken().transfer() rather than transferring
            // using a message value is that the recepient's callback is not called, thus
            // removing concern that a malicious beneficiary would control code at this point.
            bool success = getGoldToken().transfer(beneficiary, immediateWithdrawalAmount);
            if (!success) {
                revert CeloTransferFailed(beneficiary, immediateWithdrawalAmount);
            }
            // If we've withdrawn the entire amount, return.
            if (immediateWithdrawalAmount == withdrawalAmount) {
                return immediateWithdrawalAmount;
            }
        }

        // We know that withdrawalAmount is >= immediateWithdrawalAmount.
        uint256 revokeAmount = withdrawalAmount - immediateWithdrawalAmount;

        ILockedGold lockedGold = getLockedGold();

        // Save the pending withdrawal for `beneficiary`.
        pendingWithdrawals[beneficiary].push(
            PendingWithdrawal(revokeAmount, block.timestamp + lockedGold.unlockingPeriod())
        );

        _revokeVotes(
            group,
            revokeAmount,
            lesserAfterPendingRevoke,
            greaterAfterPendingRevoke,
            lesserAfterActiveRevoke,
            greaterAfterActiveRevoke,
            index
        );

        lockedGold.unlock(revokeAmount);

        return immediateWithdrawalAmount;
    }

    /**
     * @notice Activates any activatable pending votes for group, and locks & votes any
     * unlocked CELO for group.
     * @dev Callable by anyone. In practice, this is expected to be called near the end of each
     * epoch by an off-chain agent.
     * @param group The group to activate pending votes for and lock & vote any unlocked CELO for.
     * @param voteLesser Used by Election's `vote`. This is the group that will recieve fewer
     * votes than group after the votes are cast, or address(0) if no such group exists.
     * @param voteGreater Used by Election's `vote`. This is the group that will recieve greater
     * votes than group after the votes are cast, or address(0) if no such group exists.
     */
    function activateAndVote(
        address group,
        address voteLesser,
        address voteGreater
    ) external {
        IElection election = getElection();

        // The amount of unlocked CELO for group that we want to lock and vote with.
        (uint256 celoToVoteForGroup, ) = getAndUpdateToVoteAndToRevoke(group, 0, 0);

        // Reset the unlocked CELO amount for group.
        scheduledVotes[group].toVote = 0;

        // If there are activatable pending votes from this contract for group, activate them.
        if (election.hasActivatablePendingVotes(address(this), group)) {
            // Revert if the activation fails.
            if (!election.activate(group)) {
                revert ActivatePendingVotesFailed(group);
            }
        }

        // If there is no CELO to lock up and vote with, return.
        if (celoToVoteForGroup == 0) {
            return;
        }

        uint256 accountLockedNonvotingCelo = getLockedGold().getAccountNonvotingLockedGold(
            address(this)
        );

        // There might be some locked unvoting (revoked) CELO from previous transfers
        uint256 toLock = accountLockedNonvotingCelo >= celoToVoteForGroup
            ? 0
            : celoToVoteForGroup - accountLockedNonvotingCelo;

        // Lock up the unlockedCeloForGroup in LockedGold, which increments the
        // non-voting LockedGold balance for this contract.
        if (toLock > 0) {
            getLockedGold().lock{value: toLock}();
        }

        // Vote for group using the newly locked CELO, reverting if it fails.
        if (!election.vote(group, celoToVoteForGroup, voteLesser, voteGreater)) {
            revert VoteFailed(group, celoToVoteForGroup);
        }
    }

    /**
     * @notice Finishes a pending withdrawal created as a result of a `withdrawCelo` call,
     * claiming CELO after the `unlockingPeriod` defined in LockedGold.sol.
     * @dev Callable by anyone, but ultimatly the withdrawal goes to `beneficiary`.
     * The pending withdrawal info found in both StakedCeloGroupVoter and LockedGold must match
     * to ensure that the beneficiary is claiming the appropriate pending withdrawal.
     * @param beneficiary The account that owns the pending withdrawal being processed.
     * @param localPendingWithdrawalIndex The index of the pending withdrawal to finish
     * in pendingWithdrawals[beneficiary] array.
     * @param lockedGoldPendingWithdrawalIndex The index of the pending withdrawal to finish
     * in LockedGold.
     * @return amount The amount of CELO sent to `beneficiary`.
     */
    function finishPendingWithdrawal(
        address beneficiary,
        uint256 localPendingWithdrawalIndex,
        uint256 lockedGoldPendingWithdrawalIndex
    ) external returns (uint256 amount) {
        (uint256 value, uint256 timestamp) = validatePendingWithdrawalRequest(
            beneficiary,
            localPendingWithdrawalIndex,
            lockedGoldPendingWithdrawalIndex
        );

        // Remove the pending withdrawal.
        PendingWithdrawal[] storage localPendingWithdrawals = pendingWithdrawals[beneficiary];
        localPendingWithdrawals[localPendingWithdrawalIndex] = localPendingWithdrawals[
            localPendingWithdrawals.length - 1
        ];
        localPendingWithdrawals.pop();

        // Process withdrawal.
        getLockedGold().withdraw(lockedGoldPendingWithdrawalIndex);

        /**
         * The benefit of using getGoldToken().transfer() is that the recepients callback
         * is not called thus removing concern that a malicious
         * caller would control code at this point.
         */
        bool success = getGoldToken().transfer(beneficiary, value);
        if (!success) {
            revert CeloTransferFailed(beneficiary, value);
        }

        emit CeloWithdrawalFinished(beneficiary, value, timestamp);
        return value;
    }

    /**
     * @notice Turns on/off voting for more then max number of groups.
     * @param flag The on/off flag.
     */
    function setAllowedToVoteOverMaxNumberOfGroups(bool flag) external onlyOwner {
        getElection().setAllowedToVoteOverMaxNumberOfGroups(flag);
    }

    /**
     * @notice Votes on a proposal in the referendum stage.
     * @param proposalId The ID of the proposal to vote on.
     * @param index The index of the proposal ID in `dequeued`.
     * @param yesVotes The yes votes weight.
     * @param noVotes The no votes weight.
     * @param abstainVotes The abstain votes weight.
     */
    function votePartially(
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) external onlyManager {
        bool voteResult = getGovernance().votePartially(
            proposalId,
            index,
            yesVotes,
            noVotes,
            abstainVotes
        );
        if (!voteResult) {
            revert VotingNotSuccessful(proposalId);
        }
    }

    /**
     * @notice Gets the total amount of CELO this contract controls. This is the
     * unlocked CELO balance of the contract plus the amount of LockedGold for this contract,
     * which included unvoting and voting LockedGold.
     * @return The total amount of CELO this contract controls, including LockedGold.
     */
    function getTotalCelo() external view returns (uint256) {
        // LockedGold's getAccountTotalLockedGold returns any non-voting locked gold +
        // voting locked gold for each group the account is voting for, which is an
        // O(# of groups voted for) operation.
        return
            address(this).balance +
            getLockedGold().getAccountTotalLockedGold(address(this)) -
            totalScheduledWithdrawals;
    }

    /**
     * @notice Returns the pending withdrawals for a beneficiary.
     * @param beneficiary The address of the beneficiary who initiated the pending withdrawal.
     * @return values The values of pending withdrawals.
     * @return timestamps The timestamps of pending withdrawals.
     */
    function getPendingWithdrawals(address beneficiary)
        external
        view
        returns (uint256[] memory values, uint256[] memory timestamps)
    {
        uint256 length = pendingWithdrawals[beneficiary].length;
        values = new uint256[](length);
        timestamps = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            PendingWithdrawal memory p = pendingWithdrawals[beneficiary][i];
            values[i] = p.value;
            timestamps[i] = p.timestamp;
        }

        return (values, timestamps);
    }

    /**
     * @notice Returns the number of pending withdrawals for a beneficiary.
     * @param beneficiary The address of the beneficiary who initiated the pending withdrawal.
     * @return The numbers of pending withdrawals for `beneficiary`
     */
    function getNumberPendingWithdrawals(address beneficiary) external view returns (uint256) {
        return pendingWithdrawals[beneficiary].length;
    }

    /**
     * @notice Returns a pending withdrawals for a beneficiary.
     * @param beneficiary The address of the beneficiary who initiated the pending withdrawal.
     * @param index The index in `beneficiary`'s pendingWithdrawals array.
     * @return value The values of the pending withdrawal.
     * @return timestamp The timestamp of the pending withdrawal.
     */
    function getPendingWithdrawal(address beneficiary, uint256 index)
        external
        view
        returns (uint256 value, uint256 timestamp)
    {
        PendingWithdrawal memory withdrawal = pendingWithdrawals[beneficiary][index];

        return (withdrawal.value, withdrawal.timestamp);
    }

    /**
     * @notice Returns the total amount of CELO directed towards `group`. This is
     * the Unlocked CELO balance for `group` plus the combined amount in pending
     * and active votes made by this contract.
     * @param group The address of the validator group.
     * @return The total amount of CELO directed towards `group`.
     */
    function getCeloForGroup(address group) external view returns (uint256) {
        return
            getElection().getTotalVotesForGroupByAccount(group, address(this)) +
            scheduledVotes[group].toVote -
            scheduledVotes[group].toRevoke -
            scheduledVotes[group].toWithdraw;
    }

    /**
     * @notice Returns the total amount of CELO that's scheduled to vote for a group.
     * @param group The address of the validator group.
     * @return The total amount of CELO directed towards `group`.
     */
    function scheduledVotesForGroup(address group) external view returns (uint256) {
        return scheduledVotes[group].toVote;
    }

    /**
     * @notice Returns the total amount of CELO that's scheduled to be revoked for a group.
     * @param group The address of the validator group.
     * @return The total amount of CELO scheduled to be revoked from `group`.
     */
    function scheduledRevokeForGroup(address group) external view returns (uint256) {
        return scheduledVotes[group].toRevoke;
    }

    /**
     * @notice Returns the total amount of CELO that's scheduled to be withdrawn for a group.
     * @param group The address of the validator group.
     * @return The total amount of CELO to be withdrawn for `group`.
     */
    function scheduledWithdrawalsForGroup(address group) external view returns (uint256) {
        return scheduledVotes[group].toWithdraw;
    }

    /**
     * @notice Returns the total amount of CELO that's scheduled to be withdrawn for a group
     * scoped by a beneficiary.
     * @param group The address of the validator group.
     * @param beneficiary The beneficiary of the withdrawal.
     * @return The total amount of CELO to be withdrawn for `group` by `beneficiary`.
     */
    function scheduledWithdrawalsForGroupAndBeneficiary(address group, address beneficiary)
        external
        view
        returns (uint256)
    {
        return scheduledVotes[group].toWithdrawFor[beneficiary];
    }

    /**
     * @notice Returns the storage, major, minor, and patch version of the contract.
     * @return Storage version of the contract.
     * @return Major version of the contract.
     * @return Minor version of the contract.
     * @return Patch version of the contract.
     */
    function getVersionNumber()
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (1, 2, 0, 0);
    }

    /**
     * @notice Revokes votes from a validator group. It first attempts to revoke pending votes,
     * and then active votes if necessary.
     * @dev Reverts if `revokeAmount` exceeds the total number of pending and active votes for
     * the group from this contract.
     * @param group The group to revoke CELO from.
     * @param lesserAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param greaterAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param lesserAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param greaterAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param index Used by Election's `revokePending` and `revokeActive`. This is the index of
     * `group` in the this contract's array of groups it is voting for.
     */
    function revokeVotes(
        address group,
        address lesserAfterPendingRevoke,
        address greaterAfterPendingRevoke,
        address lesserAfterActiveRevoke,
        address greaterAfterActiveRevoke,
        uint256 index
    ) public {
        (, uint256 revokeAmount) = getAndUpdateToVoteAndToRevoke(group, 0, 0);

        if (revokeAmount == 0) {
            return;
        }

        _revokeVotes(
            group,
            revokeAmount,
            lesserAfterPendingRevoke,
            greaterAfterPendingRevoke,
            lesserAfterActiveRevoke,
            greaterAfterActiveRevoke,
            index
        );

        scheduledVotes[group].toRevoke -= revokeAmount;
    }

    /**
     * @notice Revokes votes from a validator group. It first attempts to revoke pending votes,
     * and then active votes if necessary.
     * @dev Reverts if `revokeAmount` exceeds the total number of pending and active votes for
     * the group from this contract.
     * @param group The group to withdraw CELO from.
     * @param revokeAmount The amount of votes to revoke.
     * @param lesserAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param greaterAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param lesserAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param greaterAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param index Used by Election's `revokePending` and `revokeActive`. This is the index of
     * `group` in the this contract's array of groups it is voting for.
     */
    function _revokeVotes(
        address group,
        uint256 revokeAmount,
        address lesserAfterPendingRevoke,
        address greaterAfterPendingRevoke,
        address lesserAfterActiveRevoke,
        address greaterAfterActiveRevoke,
        uint256 index
    ) internal {
        IElection election = getElection();
        uint256 pendingVotesAmount = election.getPendingVotesForGroupByAccount(
            group,
            address(this)
        );

        uint256 toRevokeFromPending = Math.min(revokeAmount, pendingVotesAmount);
        if (toRevokeFromPending > 0) {
            if (
                !election.revokePending(
                    group,
                    toRevokeFromPending,
                    lesserAfterPendingRevoke,
                    greaterAfterPendingRevoke,
                    index
                )
            ) {
                revert RevokePendingFailed(group, revokeAmount);
            }
        }

        uint256 toRevokeFromActive = revokeAmount - toRevokeFromPending;
        if (toRevokeFromActive == 0) {
            return;
        }

        uint256 activeVotesAmount = election.getActiveVotesForGroupByAccount(group, address(this));
        if (activeVotesAmount < toRevokeFromActive) {
            revert InsufficientRevokableVotes(group, revokeAmount);
        }

        if (
            !election.revokeActive(
                group,
                toRevokeFromActive,
                lesserAfterActiveRevoke,
                greaterAfterActiveRevoke,
                index
            )
        ) {
            revert RevokeActiveFailed(group, revokeAmount);
        }
    }

    /**
     * @notice Validates a local pending withdrawal matches a given beneficiary and LockedGold
     * pending withdrawal.
     * @dev See finishPendingWithdrawal.
     * @param beneficiary The account that owns the pending withdrawal being processed.
     * @param localPendingWithdrawalIndex The index of the pending withdrawal to finish
     * in pendingWithdrawals[beneficiary] array.
     * @param lockedGoldPendingWithdrawalIndex The index of the pending withdrawal to finish
     * in LockedGold.
     * @return value The value of the pending withdrawal.
     * @return timestamp The timestamp of the pending withdrawal.
     */
    function validatePendingWithdrawalRequest(
        address beneficiary,
        uint256 localPendingWithdrawalIndex,
        uint256 lockedGoldPendingWithdrawalIndex
    ) internal view returns (uint256 value, uint256 timestamp) {
        if (localPendingWithdrawalIndex >= pendingWithdrawals[beneficiary].length) {
            revert PendingWithdrawalIndexTooHigh(
                localPendingWithdrawalIndex,
                pendingWithdrawals[beneficiary].length
            );
        }

        (
            uint256 lockedGoldPendingWithdrawalValue,
            uint256 lockedGoldPendingWithdrawalTimestamp
        ) = getLockedGold().getPendingWithdrawal(address(this), lockedGoldPendingWithdrawalIndex);

        PendingWithdrawal memory pendingWithdrawal = pendingWithdrawals[beneficiary][
            localPendingWithdrawalIndex
        ];

        if (pendingWithdrawal.value != lockedGoldPendingWithdrawalValue) {
            revert InconsistentPendingWithdrawalValues(
                pendingWithdrawal.value,
                lockedGoldPendingWithdrawalValue
            );
        }

        if (pendingWithdrawal.timestamp != lockedGoldPendingWithdrawalTimestamp) {
            revert InconsistentPendingWithdrawalTimestamps(
                pendingWithdrawal.timestamp,
                lockedGoldPendingWithdrawalTimestamp
            );
        }

        return (pendingWithdrawal.value, pendingWithdrawal.timestamp);
    }

    /**
     * @notice Adds amount to `toVote` and `toRevoke` and returns the `toVote`
     * and `toRevoke` amount of CELO directed towards `group`. This is the `toVote`
     * CELO balance for `group` minus the `toRevoke` amount and vice versa.
     * Both `toRevoke` and `toVote` are updated.
     * @param group The address of the validator group.
     * @param addToVote The amount to add to `toVote`.
     * @param addToRevoke The amount to add to `toRevoke`.
     * @return toVote The `toVote` amount of CELO directed towards `group`.
     * @return toRevoke The `toRevoke` amount of CELO directed towards `group`.
     */
    function getAndUpdateToVoteAndToRevoke(
        address group,
        uint256 addToVote,
        uint256 addToRevoke
    ) private returns (uint256 toVote, uint256 toRevoke) {
        toVote = scheduledVotes[group].toVote + addToVote;
        toRevoke = scheduledVotes[group].toRevoke + addToRevoke;

        if (toVote > toRevoke) {
            scheduledVotes[group].toVote = toVote = toVote - toRevoke;
            scheduledVotes[group].toRevoke = toRevoke = 0;
        } else {
            scheduledVotes[group].toRevoke = toRevoke = toRevoke - toVote;
            scheduledVotes[group].toVote = toVote = 0;
        }

        if (addToVote > 0) {
            emit VotesScheduled(group, addToVote);
        }

        if (addToRevoke > 0) {
            emit RevocationScheduled(group, addToRevoke);
        }
    }
}
