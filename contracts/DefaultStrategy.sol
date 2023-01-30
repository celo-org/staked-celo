// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IGroupHealth.sol";
import "./Managed.sol";
import "./interfaces/IManager.sol";
import "./interfaces/ISpecificGroupStrategy.sol";

/**
 * @title DefaultStrategy is responsible for handling any deposit/withdrawal
 * for accounts without any specific strategy.
 */
contract DefaultStrategy is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Holds a group's address and votes.
     * @param group The address of the group.
     * @param votes The votes assigned to the group.
     */
    struct GroupWithVotes {
        address group;
        uint256 votes;
    }

    /**
     * @notice The set of currently active groups that will be voted for with
     * new deposits.
     */
    EnumerableSet.AddressSet private activeGroups;

    /**
     * @notice The set of deprecated groups. These are groups that should no
     * longer receive new votes from deposits, but still need to be kept track
     * of because the Account contract is still voting for them.
     */
    EnumerableSet.AddressSet private deprecatedGroups;

    /**
     * @notice An instance of the GroupHealth contract for the StakedCelo protocol.
     */
    IGroupHealth public groupHealth;

    /**
     * @notice An instance of the Account contract for the StakedCelo protocol.
     */
    IAccount public account;

    /**
     * @notice An instance of the SpecificGroupStrategy for the StakedCelo protocol.
     */
    ISpecificGroupStrategy public specificGroupStrategy;

    /**
     * @notice stCELO that was cast for default group strategy,
     * strategy => stCELO amount
     */
    mapping(address => uint256) private defaultStrategyTotalStCeloVotes;

    /**
     * @notice Total stCELO that was voted with on default strategy
     */
    uint256 private totalStCeloInDefaultStrategy;

    /**
     * @notice Emitted when a deprecated group is no longer being voted for and
     * the contract forgets about it entirely.
     * @param group The group's address.
     */
    event GroupRemoved(address indexed group);

    /**
     * @notice Emitted when a new group is activated for voting.
     * @param group The group's address.
     */
    event GroupActivated(address indexed group);

    /**
     * @notice Emitted when a group is deprecated.
     * @param group The group's address.
     */
    event GroupDeprecated(address indexed group);

    /**
     * @notice Used when there isn't enough CELO voting for an account's strategy
     * to fulfill a withdrawal.
     * @param group The group's address.
     */
    error CantWithdrawAccordingToStrategy(address group);

    /**
     * @notice Used when attempting to deposit when the total deposit amount
     * would tip each active group over the voting limit as defined in
     * Election.sol.
     */
    error NoVotableGroups();

    /**
     * @notice Used when attempting to activate a group that is already active.
     * @param group The group's address.
     */
    error GroupAlreadyAdded(address group);

    /**
     * @notice Used when an attempt to remove a deprecated group from the
     * EnumerableSet fails.
     * @param group The group's address.
     */
    error FailedToRemoveDeprecatedGroup(address group);

    /**
     * @notice Used when a group does not meet the validator group health requirements.
     * @param group The group's address.
     */
    error GroupNotEligible(address group);

    /**
     * @notice Used when attempting to activate a group when the maximum number
     * of groups voted (as allowed by the Election contract) is already being
     * voted for.
     */
    error MaxGroupsVotedForReached();

    /**
     * @notice Used when an attempt to add an active group to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddActiveGroup(address group);

    /**
     * @notice Used when attempting to deprecate a group that is not active.
     * @param group The group's address.
     */
    error GroupNotActive(address group);

    /**
     * @notice Used when attempting to deprecated a healthy group using deprecateUnhealthyGroup().
     * @param group The group's address.
     */
    error HealthyGroup(address group);

    /**
     * @notice Used when an attempt to add a deprecated group to the
     * EnumerableSet fails.
     * @param group The group's address.
     */
    error FailedToAddDeprecatedGroup(address group);

    /**
     * @notice Used when attempting to deposit when there are not active groups
     * to vote for.
     */
    error NoActiveGroups();

    /**
     * @notice Used when attempting to withdraw but there are no groups being
     * voted for.
     */
    error NoGroups();

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _registry The address of the Celo registry.
     * @param _owner The address of the contract owner.
     * @param _manager The address of the Manager contract.
     */
    function initialize(
        address _registry,
        address _owner,
        address _manager
    ) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
        __Managed_init(_manager);
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @param _account The address of the Account contract.
     * @param _groupHealth The address of the GroupHealth contract.
     * @param _specificGroupStrategy The address of the SpecificGroupStrategy contract.
     */
    function setDependencies(
        address _account,
        address _groupHealth,
        address _specificGroupStrategy
    ) external onlyOwner {
        require(_account != address(0), "Account null");
        require(_groupHealth != address(0), "GroupHealth null");
        require(_specificGroupStrategy != address(0), "SpecificGroupStrategy null");

        groupHealth = IGroupHealth(_groupHealth);
        specificGroupStrategy = ISpecificGroupStrategy(_specificGroupStrategy);
        account = IAccount(_account);
    }

    /**
     * @notice Distributes votes by computing the number of votes each active
     * group should receive.
     * @param votes The amount of votes to distribute.
     * @param stCeloAmountMinted The stCeloAmount that was minted.
     * @return finalGroups The groups that were chosen for distribution.
     * @return finalVotes The votes of chosen finalGroups.
     * @dev The vote distribution strategy is to try and have each validator
     * group to be receiving the same amount of votes from the system. If a
     * group already has more votes than the average of the total available
     * votes it will not be voted for, and instead we'll try to evenly
     * distribute between the remaining groups.
     * @dev Election.sol sets a dynamic limit on the number of votes receivable
     * by a group, based on the group's size, the total amount of Locked
     * CELO, and the total number of electable validators. We don't want to
     * schedule votes for a group when the amount would exceed this threshold.
     * `getVotableGroups` below selects those groups that could receive the
     * entire `votes` amount, and filters out the rest. This is a heuristic:
     * when distributing votes evenly, the group might receive less than
     * `votes`, and the total amount could end up being under the limit.
     * However, doing an exact computation would be both complex and cost a lot
     * of additional gas, hence the heuristic. If indeed all groups are close to
     * their voting limit, causing a larger deposit to revert with
     * NoVotableGroups, despite there still being some room for deposits, this
     * can be worked around by sending a few smaller deposits.
     */
    function generateGroupVotesToDistributeTo(uint256 votes, uint256 stCeloAmountMinted)
        external
        onlyManager
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
        if (activeGroups.length() == 0) {
            revert NoActiveGroups();
        }

        /*
         * "Votable" groups are those that will currently fit under the voting
         * limit in Election.sol even if voted for with the entire `votes`
         * amount. Note that some might still not end up getting voted for given
         * the distribution logic below.
         */
        address[] memory votableGroups = getVotableGroups(votes);
        if (votableGroups.length == 0) {
            revert NoVotableGroups();
        }

        GroupWithVotes[] memory sortedGroups;
        uint256 availableVotes;
        (sortedGroups, availableVotes) = getSortedGroupsWithVotes(votableGroups);
        availableVotes += votes;

        uint256[] memory votesPerGroup = new uint256[](votableGroups.length);
        uint256 groupsVoted = votableGroups.length;
        uint256 targetVotes = availableVotes / groupsVoted;

        /*
         * This would normally be (i = votableGroups.length - 1; i >=0; i--),
         * but we can't i-- on the last iteration when i=0, since i is an
         * unsigned integer. So we iterate with the loop variable 1 greater than
         * expected, set index = i-1, and use index inside the loop.
         */
        for (uint256 i = votableGroups.length; i > 0; i--) {
            uint256 index = i - 1;
            if (sortedGroups[index].votes >= targetVotes) {
                groupsVoted--;
                availableVotes -= sortedGroups[index].votes;
                targetVotes = availableVotes / groupsVoted;
                votesPerGroup[index] = 0;
            } else {
                votesPerGroup[index] = targetVotes - sortedGroups[index].votes;

                if (availableVotes % groupsVoted > index) {
                    votesPerGroup[index]++;
                }
            }
        }

        finalGroups = new address[](groupsVoted);
        finalVotes = new uint256[](groupsVoted);

        uint256 stCeloVoteRatio = stCeloAmountMinted / votes;

        for (uint256 i = 0; i < groupsVoted; i++) {
            finalGroups[i] = sortedGroups[i].group;
            finalVotes[i] = votesPerGroup[i];
            uint256 stCeloAmount = finalVotes[i] * stCeloVoteRatio;
            addToStrategyTotalStCeloVotes(finalGroups[i], stCeloAmount);
        }

        return (finalGroups, finalVotes);
    }

    /**
     * @notice Distributes withdrawals from default strategy by computing the number of votes that
     * should be withdrawn from each group.
     * @param withdrawal The amount of votes to withdraw.
     * @return finalGroups The groups that were chosen for distribution.
     * @return finalVotes The votes of chosen finalGroups.
     * @dev The withdrawal distribution strategy is to:
     * 1. Withdraw as much as possible from any deprecated groups.
     * 2. If more votes still need to be withdrawn, try and have each validator
     * group end up receiving the same amount of votes from the system. If a
     * group already has less votes than the average of the total remaining
     * votes, it will not be withdrawn from, and instead we'll try to evenly
     * distribute between the remaining groups.
     */
    function calculateAndUpdateForWithdrawal(uint256 withdrawal)
        external
        onlyManager
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
        if (activeGroups.length() + deprecatedGroups.length() == 0) {
            revert NoGroups();
        }

        address[] memory deprecatedGroupsWithdrawn;
        uint256[] memory deprecatedWithdrawalsPerGroup;
        uint256 numberDeprecatedGroupsWithdrawn;

        (
            deprecatedGroupsWithdrawn,
            deprecatedWithdrawalsPerGroup,
            numberDeprecatedGroupsWithdrawn,
            withdrawal
        ) = getDeprecatedGroupsWithdrawalDistribution(withdrawal);

        address[] memory groupsWithdrawn;
        uint256[] memory withdrawalsPerGroup;

        (groupsWithdrawn, withdrawalsPerGroup) = getActiveGroupWithdrawalDistribution(withdrawal);

        finalGroups = new address[](groupsWithdrawn.length + numberDeprecatedGroupsWithdrawn);
        finalVotes = new uint256[](groupsWithdrawn.length + numberDeprecatedGroupsWithdrawn);

        for (uint256 i = 0; i < numberDeprecatedGroupsWithdrawn; i++) {
            finalGroups[i] = deprecatedGroupsWithdrawn[i];
            finalVotes[i] = deprecatedWithdrawalsPerGroup[i];
        }

        for (uint256 i = 0; i < groupsWithdrawn.length; i++) {
            finalGroups[i + numberDeprecatedGroupsWithdrawn] = groupsWithdrawn[i];
            finalVotes[i + numberDeprecatedGroupsWithdrawn] = withdrawalsPerGroup[i];
        }

        return (finalGroups, finalVotes);
    }

    /**
     * @notice Marks a group as votable for default strategy.
     * @param group The address of the group to add to the set of votable
     * groups.
     * @dev Fails if the maximum number of groups are already being voted for by
     * the Account smart contract (as per the `maxNumGroupsVotedFor` in the
     * Election contract).
     */
    function activateGroup(address group) external onlyOwner {
        if (!groupHealth.isValidGroup(group)) {
            revert GroupNotEligible(group);
        }

        if (activeGroups.contains(group)) {
            revert GroupAlreadyAdded(group);
        }

        if (deprecatedGroups.contains(group)) {
            if (!deprecatedGroups.remove(group)) {
                revert FailedToRemoveDeprecatedGroup(group);
            }
        }

        if (
            activeGroups.length() + deprecatedGroups.length() >=
            getElection().maxNumGroupsVotedFor() &&
            !getElection().allowedToVoteOverMaxNumberOfGroups(address(account))
        ) {
            revert MaxGroupsVotedForReached();
        }

        if (!activeGroups.add(group)) {
            revert FailedToAddActiveGroup(group);
        }

        // TODO: remove once migrated to v2
        uint256 specificGroupTotalStCelo = specificGroupStrategy.getTotalStCeloVotesForStrategy(
            group
        );
        uint256 stCeloForWholeGroup = IManager(manager).toStakedCelo(
            account.getCeloForGroup(group)
        );
        uint256 currentStCelo = stCeloForWholeGroup -
            Math.min(stCeloForWholeGroup, specificGroupTotalStCelo);
        addToStrategyTotalStCeloVotes(group, currentStCelo);

        emit GroupActivated(group);
    }

    /**
     * @notice Marks a group as deprecated.
     * @param group The group to deprecate.
     * @dev A deprecated group will remain in the `deprecatedGroups` array as
     * long as it is still being voted for by the Account contract. Deprecated
     * groups will be the first to have their votes withdrawn.
     */
    function deprecateGroup(address group) external onlyOwner {
        _deprecateGroup(group);
    }

    /**
     * @notice Marks an unhealthy group as deprecated.
     * @param group The group to deprecate if unhealthy.
     * @dev A deprecated group will remain in the `deprecatedGroups` array as
     * long as it is still being voted for by the Account contract. Deprecated
     * groups will be the first to have their votes withdrawn.
     */
    function deprecateUnhealthyGroup(address group) external {
        if (groupHealth.isValidGroup(group)) {
            revert HealthyGroup(group);
        }
        _deprecateGroup((group));
    }

    /**
     * @notice Returns the array of active groups.
     * @return The array of active groups.
     */
    function getGroups() external view returns (address[] memory) {
        return activeGroups.values();
    }

    /**
     * @notice Returns the length of active groups.
     * @return The length of active groups.
     */
    function getGroupsLength() external view returns (uint256) {
        return activeGroups.length();
    }

    /**
     * @notice Returns the active group at index.
     * @return The active group.
     */
    function getGroup(uint256 index) external view returns (address) {
        return activeGroups.at(index);
    }

    /**
     * @notice Returns whether active groups contain group.
     * @return Whether or not is active group.
     */
    function groupsContain(address group) external view returns (bool) {
        return activeGroups.contains(group);
    }

    /**
     * @notice Returns the length of deprecated groups.
     * @return The length of deprecated groups.
     */
    function getDeprecatedGroupsLength() external view returns (uint256) {
        return deprecatedGroups.length();
    }

    /**
     * @notice Returns the deprecated group at index.
     * @return The deprecated group.
     */
    function getDeprecatedGroup(uint256 index) external view returns (address) {
        return deprecatedGroups.at(index);
    }

    /**
     * @notice Returns whether deprecated groups contain group.
     * @return The group.
     */
    function deprecatedGroupsContain(address group) external view returns (bool) {
        return deprecatedGroups.contains(group);
    }

    /**
     * @notice Returns the list of deprecated groups.
     * @return The list of deprecated groups.
     */
    function getDeprecatedGroups() external view returns (address[] memory) {
        return deprecatedGroups.values();
    }

    /**
     * @notice Returns the group total stCELO
     * @return The total stCELO amount.
     */
    function getTotalStCeloVotesForStrategy(address strategy) external view returns (uint256) {
        return defaultStrategyTotalStCeloVotes[strategy];
    }

    /**
     * @notice Returns the total stCELO locked in default strategy.
     * @return The total stCELO.
     */
    function getTotalStCeloInDefaultStrategy() external view returns (uint256) {
        return totalStCeloInDefaultStrategy;
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
        return (1, 1, 0, 0);
    }

    /**
     * @notice Returns the active groups that can receive the entire `votes`
     * amount based on their current receivable votes limit in Election.sol.
     * @param votes The number of votes that would potentially be added.
     * @return The list of votable active groups.
     */
    function getVotableGroups(uint256 votes) internal returns (address[] memory) {
        uint256 numberGroups = activeGroups.length();
        uint256 numberVotableGroups = 0;
        address[] memory votableGroups = new address[](numberGroups);

        for (uint256 i = 0; i < numberGroups; i++) {
            address group = activeGroups.at(i);
            uint256 scheduledVotes = account.scheduledVotesForGroup(group);
            if (getElection().canReceiveVotes(group, votes + scheduledVotes)) {
                votableGroups[numberVotableGroups] = group;
                numberVotableGroups++;
            }
        }

        address[] memory votableGroupsFinal = new address[](numberVotableGroups);
        for (uint256 i = 0; i < numberVotableGroups; i++) {
            votableGroupsFinal[i] = votableGroups[i];
        }

        return votableGroupsFinal;
    }

    /**
     * @notice Calculates how many votes should be withdrawn from each
     * deprecated group.
     * @param withdrawal The total amount of votes that needs to be withdrawn.
     * @return deprecatedGroupsWithdrawn The array of deprecated groups to be
     * withdrawn from.
     * @return deprecatedWithdrawalsPerGroup The amount of votes to withdraw
     * from the respective deprecated group in `deprecatedGroupsWithdrawn`.
     * @return numberDeprecatedGroupsWithdrawn The number of groups in
     * `deprecatedGroupsWithdrawn` that have a non zero withdrawal.
     * @return remainingWithdrawal The number of votes that still need to be
     * withdrawn after withdrawing from deprecated groups.
     * @dev Non zero entries of `deprecatedWithdrawalsPerGroup` will be exactly
     * a prefix of length `numberDeprecatedGroupsWithdrawn`.
     */
    function getDeprecatedGroupsWithdrawalDistribution(uint256 withdrawal)
        internal
        returns (
            address[] memory deprecatedGroupsWithdrawn,
            uint256[] memory deprecatedWithdrawalsPerGroup,
            uint256 numberDeprecatedGroupsWithdrawn,
            uint256 remainingWithdrawal
        )
    {
        remainingWithdrawal = withdrawal;
        uint256 numberDeprecatedGroups = deprecatedGroups.length();
        deprecatedGroupsWithdrawn = new address[](numberDeprecatedGroups);
        deprecatedWithdrawalsPerGroup = new uint256[](numberDeprecatedGroups);
        numberDeprecatedGroupsWithdrawn = 0;

        for (uint256 i = 0; i < numberDeprecatedGroups; i++) {
            numberDeprecatedGroupsWithdrawn++;
            deprecatedGroupsWithdrawn[i] = deprecatedGroups.at(i);
            uint256 currentStCeloInStrategy = defaultStrategyTotalStCeloVotes[
                deprecatedGroupsWithdrawn[i]
            ];
            uint256 currentVotes = IManager(manager).toCelo(currentStCeloInStrategy);
            deprecatedWithdrawalsPerGroup[i] = Math.min(remainingWithdrawal, currentVotes);
            remainingWithdrawal -= deprecatedWithdrawalsPerGroup[i];

            if (currentVotes == deprecatedWithdrawalsPerGroup[i]) {
                if (!deprecatedGroups.remove(deprecatedGroupsWithdrawn[i])) {
                    revert FailedToRemoveDeprecatedGroup(deprecatedGroupsWithdrawn[i]);
                }
                emit GroupRemoved(deprecatedGroupsWithdrawn[i]);
            }

            subtractFromStrategyTotalStCeloVotes(
                deprecatedGroupsWithdrawn[i],
                currentStCeloInStrategy
            );

            if (remainingWithdrawal == 0) {
                break;
            }
        }

        return (
            deprecatedGroupsWithdrawn,
            deprecatedWithdrawalsPerGroup,
            numberDeprecatedGroupsWithdrawn,
            remainingWithdrawal
        );
    }

    /**
     * @notice Calculates how votes should be withdrawn from each active group.
     * @param withdrawal The number of votes that need to be withdrawn.
     * @return The array of group addresses that should be withdrawn from.
     * @return The amount of votes to withdraw from the respective group in the
     * array of groups withdrawn from.
     */
    function getActiveGroupWithdrawalDistribution(uint256 withdrawal)
        internal
        returns (address[] memory, uint256[] memory)
    {
        uint256 numberGroups = activeGroups.length();

        if (withdrawal == 0 || numberGroups == 0) {
            address[] memory noGroups = new address[](0);
            uint256[] memory noWithdrawals = new uint256[](0);
            return (noGroups, noWithdrawals);
        }

        GroupWithVotes[] memory sortedGroups;
        uint256 availableVotes;
        (sortedGroups, availableVotes) = getSortedGroupsWithVotes(activeGroups.values());
        if (availableVotes < withdrawal) {
            revert CantWithdrawAccordingToStrategy(address(0));
        }
        availableVotes -= withdrawal;

        uint256 numberGroupsWithdrawn = numberGroups;
        uint256 targetVotes = availableVotes / numberGroupsWithdrawn;

        for (uint256 i = 0; i < numberGroups; i++) {
            if (sortedGroups[i].votes <= targetVotes) {
                numberGroupsWithdrawn--;
                availableVotes -= sortedGroups[i].votes;
                targetVotes = availableVotes / numberGroupsWithdrawn;
            } else {
                break;
            }
        }

        uint256[] memory withdrawalsPerGroup = new uint256[](numberGroupsWithdrawn);
        address[] memory groupsWithdrawn = new address[](numberGroupsWithdrawn);
        uint256 offset = numberGroups - numberGroupsWithdrawn;

        for (uint256 i = 0; i < numberGroupsWithdrawn; i++) {
            groupsWithdrawn[i] = sortedGroups[i + offset].group;
            withdrawalsPerGroup[i] = sortedGroups[i + offset].votes - targetVotes;
            subtractFromStrategyTotalStCeloVotes(
                groupsWithdrawn[i],
                IManager(manager).toStakedCelo(withdrawalsPerGroup[i])
            );
            if (availableVotes % numberGroupsWithdrawn > i) {
                withdrawalsPerGroup[i]--;
            }
        }

        return (groupsWithdrawn, withdrawalsPerGroup);
    }

    /**
     * @notice Adds value to totals of group strategy and
     * total stCELO in all group strategies.
     * @param strategy The validator group that we are adding to.
     * @param stCeloAmount The added amount of stCELO.
     */
    function addToStrategyTotalStCeloVotes(address strategy, uint256 stCeloAmount) internal {
        defaultStrategyTotalStCeloVotes[strategy] += stCeloAmount;
        totalStCeloInDefaultStrategy += stCeloAmount;
    }

    /**
     * @notice Subtracts value from totals of group strategy and
     * total stCELO in all group strategies.
     * @param strategy The validator group that we are adding to.
     * @param stCeloAmount The subtracted amount of stCELO.
     */
    function subtractFromStrategyTotalStCeloVotes(address strategy, uint256 stCeloAmount) internal {
        defaultStrategyTotalStCeloVotes[strategy] -= stCeloAmount;
        totalStCeloInDefaultStrategy -= stCeloAmount;
    }

    /**
     * @notice Returns a list of group addresses with their corresponding
     * current total votes, sorted by the number of votes, and the total number
     * of votes in the system.
     * @param groups The array of addresses of the groups to sort.
     * @return The array of GroupWithVotes structs, sorted by number of votes.
     * @return The total number of votes assigned to active groups.
     */
    function getSortedGroupsWithVotes(address[] memory groups)
        internal
        view
        returns (GroupWithVotes[] memory, uint256)
    {
        GroupWithVotes[] memory groupsWithVotes = new GroupWithVotes[](groups.length);
        uint256 totalVotes = 0;
        for (uint256 i = 0; i < groups.length; i++) {
            uint256 actualCeloInGroup = account.getCeloForGroup(groups[i]);
            uint256 stCeloInStrategy = defaultStrategyTotalStCeloVotes[groups[i]];
            uint256 votes = Math.min(actualCeloInGroup, IManager(manager).toCelo(stCeloInStrategy));
            totalVotes += votes;
            groupsWithVotes[i] = GroupWithVotes(groups[i], votes);
        }

        sortGroupsWithVotes(groupsWithVotes);
        return (groupsWithVotes, totalVotes);
    }

    /**
     * @notice Sorts an array of GroupWithVotes structs based on increasing
     * `votes` values.
     * @param groupsWithVotes The array to sort.
     * @dev This is an in-place insertion sort. In general in Solidity we should
     * be careful of algorithms on arrays, especially O(n^2) ones, but here
     * we're guaranteed to be working with a small array, its length is bounded
     * by the maximum number of groups that can be voted for in Elections.sol.
     */
    function sortGroupsWithVotes(GroupWithVotes[] memory groupsWithVotes) internal pure {
        for (uint256 i = 1; i < groupsWithVotes.length; i++) {
            uint256 j = i;
            while (j > 0 && groupsWithVotes[j].votes < groupsWithVotes[j - 1].votes) {
                (groupsWithVotes[j], groupsWithVotes[j - 1]) = (
                    groupsWithVotes[j - 1],
                    groupsWithVotes[j]
                );
                j--;
            }
        }
    }

    /**
     * @notice Marks a group as deprecated.
     * @param group The group to deprecate.
     */
    function _deprecateGroup(address group) private {
        bool activeGroupsRemoval = activeGroups.remove(group);
        if (!activeGroupsRemoval) {
            revert GroupNotActive(group);
        }

        emit GroupDeprecated(group);

        uint256 strategyTotalStCeloVotes = defaultStrategyTotalStCeloVotes[group];

        if (IManager(manager).toCelo(strategyTotalStCeloVotes) > 0) {
            if (!deprecatedGroups.add(group)) {
                revert FailedToAddDeprecatedGroup(group);
            }
        } else {
            emit GroupRemoved(group);
        }
    }
}
