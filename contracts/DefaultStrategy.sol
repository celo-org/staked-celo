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
import "./common/linkedlists/AddressSortedLinkedList.sol";
import "hardhat/console.sol";

/**
 * @title DefaultStrategy is responsible for handling any deposit/withdrawal
 * for accounts without any specific strategy.
 */
contract DefaultStrategy is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed {
    using EnumerableSet for EnumerableSet.AddressSet;
    using AddressSortedLinkedList for SortedLinkedList.List;

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
    // EnumerableSet.AddressSet private activeGroups;
    SortedLinkedList.List private activeGroups;

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
     * @notice Maximum number of groups to distribute votes to.
     */
    uint256 public maxGroupsToDistributeTo;

    /**
     * @notice Maximum number of groups to withdraw from.
     */
    uint256 public maxGroupsToWithdrawFrom;

    /**
     * @notice Total stCELO that was voted with on default strategy.
     */
    uint256 private totalStCeloInDefaultStrategy;

    /**
     * @notice Loop limit while sorting active groups on chain.
     */
    uint256 private sortingLoopLimit;

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
     * @notice Used when attempting to withdraw from specific strategy
     * but group does not have enough CELO. Group either doesn't have enough stCELO
     * or it is necessary to rebalance the group.
     * @param group The group's address.
     * @param expected The expected vote amount.
     * @param real The real vote amount.
     */
    error GroupNotBalancedOrNotEnoughStCelo(address group, uint256 expected, uint256 real);

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
     * @notice Used when atempting to distribute votes but validator group limit is reached.
     */
    error NotAbleToDistributeVotes();

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
        maxGroupsToDistributeTo = 8;
        maxGroupsToWithdrawFrom = 8;
        sortingLoopLimit = 10;
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
     * @notice Set maximum number of group to distribute votes to.
     * @param value The new value.
     */
    function setMaxGroupsToDistributeTo(uint256 value) external onlyOwner {
        maxGroupsToDistributeTo = value;
    }

    /**
     * @notice Set maximum number of group to withdraw from.
     * @param value The new value.
     */
    function setMaxGroupsToWithdrawFrom(uint256 value) external onlyOwner {
        maxGroupsToWithdrawFrom = value;
    }

    /**
     * @notice Set sorting loop limit while sorting on chain.
     * @param value The new value.
     */
    function setSortingLoopLimit(uint256 value) external onlyOwner {
        sortingLoopLimit = value;
    }

    /**
     * @notice Distributes votes by computing the number of votes each active
     * group should receive.
     * @param votes The amount of votes to distribute.
     * @param stCeloAmountMinted The stCeloAmount that was minted.
     * @param add Whether funds are being added or removed.
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
    function generateGroupVotesToDistributeTo(
        uint256 votes,
        uint256 stCeloAmountMinted,
        bool add
    ) external onlyManager returns (address[] memory finalGroups, uint256[] memory finalVotes) {
        if (activeGroups.getNumElements() == 0) {
            revert NoActiveGroups();
        }

        uint256 numberOfGroupsToDistributeTo = Math.min(
            maxGroupsToDistributeTo,
            activeGroups.getNumElements()
        );

        address[] memory groups = new address[](numberOfGroupsToDistributeTo);
        uint256[] memory votesPerGroup = new uint256[](numberOfGroupsToDistributeTo);

        address votedGroup = activeGroups.getTail();
        uint256 countOfGroupsDistributedTo;
        bool ordered = true; // TODO: add tests for not ordered strategies
        for (
            countOfGroupsDistributedTo = 0;
            countOfGroupsDistributedTo < numberOfGroupsToDistributeTo;
            countOfGroupsDistributedTo++
        ) {
            if (votes == 0 || votedGroup == address(0)) {
                break;
            }
            uint256 receivableVotes = getElection().getNumVotesReceivable(votedGroup) -
                getElection().getTotalVotesForGroup(votedGroup) -
                account.scheduledVotesForGroup(votedGroup);
            logGroup(votedGroup, votes, receivableVotes);
            groups[countOfGroupsDistributedTo] = votedGroup;
            votesPerGroup[countOfGroupsDistributedTo] = Math.min(receivableVotes, votes);
            votes -= votesPerGroup[countOfGroupsDistributedTo];
            if (add) {
                addToStrategyTotalStCeloVotes(
                    votedGroup,
                    IManager(manager).toStakedCelo(votesPerGroup[countOfGroupsDistributedTo])
                );
            } else {
                subtractFromStrategyTotalStCeloVotes(
                    votedGroup,
                    IManager(manager).toStakedCelo(votesPerGroup[countOfGroupsDistributedTo])
                );
            }
             (address lesserKey, address greaterKey) = getLesserAndGreaterOfActiveGroups(
                votedGroup,
                votesPerGroup[countOfGroupsDistributedTo],
                sortingLoopLimit,
                !add
            );
            if (lesserKey != greaterKey && ordered) {
                activeGroups.update(votedGroup, votesPerGroup[countOfGroupsDistributedTo], lesserKey, greaterKey);
                votedGroup = activeGroups.getTail();
            } else {
                (, , votedGroup) = activeGroups.get(votedGroup);
                ordered = false;
            }
        }

        if (votes != 0) {
            revert NotAbleToDistributeVotes();
        }

        finalGroups = new address[](countOfGroupsDistributedTo);
        finalVotes = new uint256[](countOfGroupsDistributedTo);

        for (uint256 j = 0; j < countOfGroupsDistributedTo; j++) {
            finalGroups[j] = groups[j];
            finalVotes[j] = votesPerGroup[j];
        }
    }

    function logGroup(
        address group,
        uint256 votes,
        uint256 receivableVotes
    ) private {
        uint256 scheduledVotes = account.scheduledVotesForGroup(group);
        console.log(
            "group %s, canReceiveVotes %s",
            group,
            getElection().canReceiveVotes(group, votes + scheduledVotes)
        );
        console.log(
            "group %s receivable votes %s canReceiveVotes %s",
            group,
            receivableVotes,
            getElection().canReceiveVotes(group, votes + scheduledVotes)
        );
        console.log("scheduledVotes %s", scheduledVotes);
        console.log("scheduledVotes %s", votes);
        console.log("totalVotesForGroup %s", getElection().getTotalVotesForGroup(group));
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
        if (activeGroups.getNumElements() == 0) {
            revert NoGroups();
        }

        uint256 numberOfGroupsToWithdrawFrom = Math.min(
            maxGroupsToWithdrawFrom,
            activeGroups.getNumElements()
        );

        address[] memory groups = new address[](numberOfGroupsToWithdrawFrom);
        uint256[] memory votesPerGroup = new uint256[](numberOfGroupsToWithdrawFrom);

        address votedGroup = activeGroups.getHead();
        uint256 countOfGroupsDistributedTo;
        for (
            countOfGroupsDistributedTo = 0;
            countOfGroupsDistributedTo < numberOfGroupsToWithdrawFrom;
            countOfGroupsDistributedTo++
        ) {
            if (withdrawal == 0 || votedGroup == address(0)) {
                break;
            }

            uint256 withdrawableVotes = defaultStrategyTotalStCeloVotes[votedGroup];
            uint256 votesForGroup = Math.min(withdrawableVotes, withdrawal);
            groups[countOfGroupsDistributedTo] = votedGroup;
            votesPerGroup[countOfGroupsDistributedTo] = votesForGroup;
            (address lesserKey, address greaterKey) = getLesserAndGreaterOfActiveGroups(
                votedGroup,
                votesForGroup,
                sortingLoopLimit,
                true
            );
            if (lesserKey != greaterKey) {
                activeGroups.update(votedGroup, votesForGroup, lesserKey, greaterKey);
            }

            withdrawal -= votesForGroup;
            subtractFromStrategyTotalStCeloVotes(
                votedGroup,
                IManager(manager).toStakedCelo(votesForGroup)
            );
            (, votedGroup, ) = activeGroups.get(votedGroup);
        }

        if (withdrawal != 0) {
            revert NotAbleToDistributeVotes();
        }

        finalGroups = new address[](countOfGroupsDistributedTo);
        finalVotes = new uint256[](countOfGroupsDistributedTo);

        for (uint256 j = 0; j < countOfGroupsDistributedTo; j++) {
            finalGroups[j] = groups[j];
            finalVotes[j] = votesPerGroup[j];
        }
        return (finalGroups, finalVotes);
    }

    function getLesserAndGreaterOfActiveGroups(
        address originalKey,
        uint256 newValue,
        uint256 loopLimit,
        bool withdrawal
    ) private view returns (address previous, address next) {
        (, address previousKey, address nextKey) = activeGroups.get(originalKey);

        address originalNeighbourKey = withdrawal ? nextKey : previousKey;
        console.log("loop length %s", Math.min(activeGroups.getNumElements(), loopLimit));

        for (uint256 i = 0; i < Math.min(activeGroups.getNumElements(), loopLimit); i++) {
            address keyToCheck = withdrawal ? previousKey : nextKey;
            console.log("previousKey %s nextKey %s", previousKey, nextKey);
            console.log("keyToCheck %", keyToCheck);
            if (
                keyToCheck == address(0) || withdrawal
                    ? activeGroups.getValue(keyToCheck) < newValue
                    : activeGroups.getValue(keyToCheck) > newValue
            ) {
                if (withdrawal) {
                    previous = previousKey;
                    next = nextKey == originalKey ? originalNeighbourKey : nextKey;
                } else {
                    previous = previousKey == originalKey ? originalNeighbourKey : previousKey;
                    next = nextKey;
                }
                return (previous, next);
            }
            (, previousKey, nextKey) = activeGroups.get(withdrawal ? previousKey : nextKey);
        }
    }

    /**
     * @notice Marks a group as votable for default strategy.
     * @param group The address of the group to add to the set of votable
     * groups.
     * @param lesser The group receiving fewer votes (in default strategy) than `group`,
     * or 0 if `group` has the fewest votes of any validator group.
     * @param greater The group receiving more votes (in default strategy) than `group`,
     *  or 0 if `group` has the most votes of any validator group.
     * @dev Fails if the maximum number of groups are already being voted for by
     * the Account smart contract (as per the `maxNumGroupsVotedFor` in the
     * Election contract).
     */
    function activateGroup(
        address group,
        address lesser,
        address greater
    ) external onlyOwner {
        if (!groupHealth.isValidGroup(group)) {
            revert GroupNotEligible(group);
        }

        if (activeGroups.contains(group)) {
            revert GroupAlreadyAdded(group);
        }

        if (
            activeGroups.getNumElements() >= getElection().maxNumGroupsVotedFor() &&
            !getElection().allowedToVoteOverMaxNumberOfGroups(address(account))
        ) {
            revert MaxGroupsVotedForReached();
        }

        activeGroups.insert(group, 0, lesser, greater);

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
     */
    function deprecateGroup(address group) external onlyOwner {
        _deprecateGroup(group);
    }

    /**
     * @notice Marks an unhealthy group as deprecated.
     * @param group The group to deprecate if unhealthy.
     */
    function deprecateUnhealthyGroup(address group) external {
        if (groupHealth.isValidGroup(group)) {
            revert HealthyGroup(group);
        }
        _deprecateGroup((group));
    }

    /**
     * @notice Returns the unordered array of active groups.
     * @return The array of active groups.
     */
    function getGroups() external view returns (address[] memory) {
        return activeGroups.getKeys();
    }

    /**
     * @notice Returns the length of active groups.
     * @return The length of active groups.
     */
    function getGroupsLength() external view returns (uint256) {
        return activeGroups.getNumElements();
    }

    /**
     * @notice Returns previous and next address of key.
     * @param key The key of searched group.
     * @return previousAddress The previous address.
     * @return nextAddress The next address.
     */
    function getGroupPreviousAndNext(address key)
        external
        view
        returns (address previousAddress, address nextAddress)
    {
        (, previousAddress, nextAddress) = activeGroups.get(key);
    }

    /**
     * @notice Returns head and previous address of head.
     * @return head The head of groups.
     * @return previousAddress The previous address.
     */
    function getGroupsHead() external view returns (address head, address previousAddress) {
        head = activeGroups.getHead();
        (, previousAddress, ) = activeGroups.get(head);
    }

    /**
     * @notice Returns tail and next address of tail.
     * @return head The tail of groups.
     * @return nextAddress The previous address.
     */
    function getGroupsTail() external view returns (address head, address nextAddress) {
        head = activeGroups.getTail();
        (, nextAddress, ) = activeGroups.get(head);
    }

    /**
     * @notice Returns whether active groups contain group.
     * @return Whether or not is active group.
     */
    function groupsContain(address group) external view returns (bool) {
        return activeGroups.contains(group);
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
     * @notice Marks a group as deprecated.
     * @param group The group to deprecate.
     */
    function _deprecateGroup(address group) private {
        if (!activeGroups.contains(group)) {
            revert GroupNotActive(group);
        }
        activeGroups.remove(group);

        emit GroupDeprecated(group);

        uint256 strategyTotalStCeloVotes = defaultStrategyTotalStCeloVotes[group];

        if (IManager(manager).toCelo(strategyTotalStCeloVotes) > 0) {
            // TODO: add transfer + tests
        }

        emit GroupRemoved(group);
    }
}
