// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./common/linkedlists/AddressSortedLinkedList.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IGroupHealth.sol";
import "./interfaces/IManager.sol";
import "./interfaces/ISpecificGroupStrategy.sol";
import "./Managed.sol";

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
    mapping(address => uint256) public stCELOInGroup;

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
    uint256 public totalStCeloInDefaultStrategy;

    /**
     * @notice Loop limit while sorting active groups on chain.
     */
    uint256 private sortingLoopLimit;

    /**
     * @notice Whether or not active groups are sorted.
     * If active groups are not sorted it is neccessary to call updateActiveGroupOrder
     */
    bool public sorted;

    /**
     * @notice Groups that need to be sorted
     */
    EnumerableSet.AddressSet private unsortedGroups;

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
     * @notice Used when there isn't enough CELO voting for an account's strategy
     * to fulfill a withdrawal.
     */
    error CantWithdrawAccordingToStrategy();

    /**
     * @notice Used when attempting to activate a group that is already active.
     * @param group The group's address.
     */
    error GroupAlreadyAdded(address group);

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
     * @notice Used when attempting to deposit when there are no active groups
     * to vote for.
     */
    error NoActiveGroups();

    /**
     * @notice Used when atempting to distribute votes but validator group limit is reached.
     */
    error NotAbleToDistributeVotes();

    /**
     * @notice Used when attempting sort active groups when there are no unsorted group.
     */
    error NoUnsortedGroup();

    /**
     * @notice Used when rebalancing to a non-active group.
     * @param group The group's address.
     */
    error InvalidToGroup(address group);

    /**
     * @notice Used when rebalancing from not active.
     * @param group The group's address.
     */
    error InvalidFromGroup(address group);

    /**
     * @notice Used when rebalancing and fromGroup doesn't have any extra stCELO.
     * @param group The group's address.
     * @param actualCelo The actual stCELO value.
     * @param expectedCelo The expected stCELO value.
     */
    error RebalanceNoExtraStCelo(address group, uint256 actualCelo, uint256 expectedCelo);

    /**
     * @notice Used when rebalancing and toGroup has enough stCELO.
     * @param group The group's address.
     * @param actualCelo The actual stCELO value.
     * @param expectedCelo The expected stCELO value.
     */
    error RebalanceEnoughStCelo(address group, uint256 actualCelo, uint256 expectedCelo);

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _registry The address of the Celo Registry.
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
        sorted = true;
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
     * @notice Set distribution/withdrawal algorithm parameters.
     * @param distributeTo The distibute to value.
     * @param withdrawFrom The withdraw from value.
     * @param loopLimit The sorting loop limit while sorting on chain.
     */
    function setSortingParams(
        uint256 distributeTo,
        uint256 withdrawFrom,
        uint256 loopLimit
    ) external onlyOwner {
        maxGroupsToDistributeTo = distributeTo;
        maxGroupsToWithdrawFrom = withdrawFrom;
        sortingLoopLimit = loopLimit;
    }

    /**
     * @notice Distributes votes by computing the number of votes each active
     * group should either receive or should be subtracted from.
     * @param votes The amount of votes to distribute.
     * @param withdraw Generation for either desposit or withdrawal.
     * @return finalGroups The groups that were chosen for distribution.
     * @return finalVotes The votes of chosen finalGroups.
     */
    function generateVoteDistribution(uint256 votes, bool withdraw)
        external
        onlyManager
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
        (finalGroups, finalVotes) = _generateVoteDistribution(votes, withdraw);
    }

    /**
     * @notice Updates group order of unsorted group. When there are no more unsorted groups
     * it will mark active groups as sorted.
     * @param group The amount of votes to withdraw.
     * @param lesserKey The key of the group less than the group to update.
     * @param greaterKey The key of the group greater than the group to update.
     */
    function updateActiveGroupOrder(
        address group,
        address lesserKey,
        address greaterKey
    ) external {
        if (!unsortedGroups.contains(group)) {
            revert NoUnsortedGroup();
        }

        activeGroups.update(group, stCELOInGroup[group], lesserKey, greaterKey);
        unsortedGroups.remove(group);
        if (unsortedGroups.length() == 0) {
            sorted = true;
        }
    }

    /**
     * @notice Marks a group as votable for default strategy.
     * It is necessary to call `updateGroupHealth` in GroupHealth smart contract first.
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
        if (!groupHealth.isGroupValid(group)) {
            revert GroupNotEligible(group);
        }

        if (activeGroups.contains(group)) {
            revert GroupAlreadyAdded(group);
        }

        if (
            (specificGroupStrategy.getSpecificGroupStrategiesNumber() +
                activeGroups.getNumElements()) >=
            getElection().maxNumGroupsVotedFor() &&
            !getElection().allowedToVoteOverMaxNumberOfGroups(address(account))
        ) {
            revert MaxGroupsVotedForReached();
        }

        activeGroups.insert(group, 0, lesser, greater);

        // TODO: remove once migrated to v2
        uint256 specificGroupTotalStCelo = specificGroupStrategy
            .specificGroupStrategyTotalStCeloVotes(group);
        uint256 stCeloForWholeGroup = IManager(manager).toStakedCelo(
            account.getCeloForGroup(group)
        );
        uint256 currentStCelo = stCeloForWholeGroup -
            Math.min(stCeloForWholeGroup, specificGroupTotalStCelo);

        updateGroupStCelo(group, currentStCelo, true);

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
        if (groupHealth.isGroupValid(group)) {
            revert HealthyGroup(group);
        }
        _deprecateGroup((group));
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
     * @notice Returns the length of unsorted groups.
     * @return The length of unsorted groups.
     */
    function getUnsortedGroupsLength() external view returns (uint256) {
        return unsortedGroups.length();
    }

    /**
     * @notice Returns the unsorted group at index.
     * @param index The index of the unsorted group.
     * @return The group.
     */
    function getUnsortedGroupAt(uint256 index) external view returns (address) {
        return unsortedGroups.at(index);
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
     * @notice Rebalances CELO between groups that have an incorrect CELO-stCELO ratio.
     * FromGroup is required to have more CELO than it should and ToGroup needs
     * to have less CELO than it should.
     * @param fromGroup The from group.
     * @param toGroup The to group.
     */
    function rebalance(address fromGroup, address toGroup) public {
        if (!activeGroups.contains(fromGroup)) {
            revert InvalidFromGroup(fromGroup);
        }

        if (!activeGroups.contains(toGroup)) {
            revert InvalidToGroup(toGroup);
        }

        (uint256 expectedFromStCelo, uint256 actualFromStCelo) = getExpectedAndActualStCeloForGroup(
            fromGroup
        );
        if (actualFromStCelo <= expectedFromStCelo) {
            // fromGroup needs to have more stCELO than it should
            revert RebalanceNoExtraStCelo(fromGroup, actualFromStCelo, expectedFromStCelo);
        }

        (uint256 expectedToStCelo, uint256 actualToStCelo) = getExpectedAndActualStCeloForGroup(
            toGroup
        );

        if (actualToStCelo >= expectedToStCelo) {
            // toGroup needs to have less stCELO than it should
            revert RebalanceEnoughStCelo(toGroup, actualToStCelo, expectedToStCelo);
        }

        uint256 toMove = Math.min(
            actualFromStCelo - expectedFromStCelo,
            expectedToStCelo - actualToStCelo
        );

        updateGroupStCelo(fromGroup, toMove, false);
        updateGroupStCelo(toGroup, toMove, true);
        if (sorted) {
            (address lesserKey, address greaterKey) = getLesserAndGreaterOfActiveGroupsWithdrawal(
                fromGroup,
                stCELOInGroup[fromGroup]
            );
            if (lesserKey != greaterKey) {
                activeGroups.update(fromGroup, stCELOInGroup[fromGroup], lesserKey, greaterKey);
                (lesserKey, greaterKey) = getLesserAndGreaterOfActiveGroupsDeposit(
                    toGroup,
                    stCELOInGroup[toGroup]
                );
                if (lesserKey != greaterKey) {
                    activeGroups.update(toGroup, stCELOInGroup[toGroup], lesserKey, greaterKey);
                    return;
                }
            }
            sorted = false;
        }
        unsortedGroups.add(toGroup);
        unsortedGroups.add(fromGroup);
    }

    /**
     * @notice Returns expected stCELO vs actual stCELO for group.
     * @param group The group.
     * @return expectedStCelo The stCELO which group should have.
     * @return actualStCelo The stCELO which group has.
     */
    function getExpectedAndActualStCeloForGroup(address group)
        public
        view
        returns (uint256 expectedStCelo, uint256 actualStCelo)
    {
        address head = activeGroups.getHead();
        expectedStCelo = totalStCeloInDefaultStrategy / activeGroups.getNumElements();
        if (group == head) {
            uint256 divisionResidue = totalStCeloInDefaultStrategy -
                (expectedStCelo * activeGroups.getNumElements());
            expectedStCelo += divisionResidue;
        }

        actualStCelo = stCELOInGroup[group];
    }

    /**
     * @notice Adds/substracts value to totals of group and
     * total stCELO in default strategy.
     * @param group The validator group that we are updating.
     * @param stCeloAmount The amount of stCELO.
     * @param add Whether to add or substract.
     */
    function updateGroupStCelo(
        address group,
        uint256 stCeloAmount,
        bool add
    ) internal {
        if (add) {
            stCELOInGroup[group] += stCeloAmount;
            totalStCeloInDefaultStrategy += stCeloAmount;
        } else {
            stCELOInGroup[group] -= stCeloAmount;
            totalStCeloInDefaultStrategy -= stCeloAmount;
        }
    }

    function getLesserAndGreaterOfActiveGroups(
        address originalKey,
        uint256 newValue,
        bool withdrawal
    ) internal view returns (address previous, address next) {
        if (withdrawal) {
            (previous, next) = getLesserAndGreaterOfActiveGroupsWithdrawal(originalKey, newValue);
        } else {
            (previous, next) = getLesserAndGreaterOfActiveGroupsDeposit(originalKey, newValue);
        }
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
        unsortedGroups.remove(group);

        uint256 groupTotalStCeloVotes = stCELOInGroup[group];

        if (groupTotalStCeloVotes > 0) {
            updateGroupStCelo(group, groupTotalStCeloVotes, false);
            address[] memory fromGroups = new address[](1);
            uint256[] memory fromVotes = new uint256[](1);
            fromGroups[0] = group;
            fromVotes[0] = IManager(manager).toCelo(groupTotalStCeloVotes);
            (address[] memory toGroups, uint256[] memory toVotes) = _generateVoteDistribution(
                IManager(manager).toCelo(groupTotalStCeloVotes),
                false
            );
            IManager(manager).scheduleTransferWithinStrategy(
                fromGroups,
                toGroups,
                fromVotes,
                toVotes
            );
        }

        emit GroupRemoved(group);
    }

    /**
     * @notice Distributes votes by computing the number of votes each active
     * group should either receive of should be subtracted from.
     * @param votesAmount The amount of votes to distribute.
     * @param withdraw Generation for either desposit or withdrawal.
     * @return finalGroups The groups that were chosen for distribution.
     * @return finalVotes The votes of chosen finalGroups.
     */
    function _generateVoteDistribution(uint256 votesAmount, bool withdraw)
        private
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
        if (activeGroups.getNumElements() == 0) {
            revert NoActiveGroups();
        }

        uint256 maxGroupCount = Math.min(
            withdraw ? maxGroupsToWithdrawFrom : maxGroupsToDistributeTo,
            activeGroups.getNumElements()
        );

        address[] memory groups = new address[](maxGroupCount);
        uint256[] memory votes = new uint256[](maxGroupCount);

        address votedGroup = withdraw ? activeGroups.getHead() : activeGroups.getTail();
        uint256 groupsIndex;
        uint256 groupVotes;

        for (groupsIndex = 0; groupsIndex < maxGroupCount; groupsIndex++) {
            if (votesAmount == 0 || votedGroup == address(0)) {
                break;
            }

            if (withdraw) {
                groupVotes = IManager(manager).toCelo(stCELOInGroup[votedGroup]);
            } else {
                groupVotes =
                    getElection().getNumVotesReceivable(votedGroup) -
                    getElection().getTotalVotesForGroup(votedGroup) -
                    account.scheduledVotesForGroup(votedGroup);
            }

            votes[groupsIndex] = Math.min(groupVotes, votesAmount);
            groups[groupsIndex] = votedGroup;

            votesAmount -= votes[groupsIndex];

            updateGroupStCelo(
                votedGroup,
                IManager(manager).toStakedCelo(votes[groupsIndex]),
                !withdraw
            );

            (address lesserKey, address greaterKey) = getLesserAndGreaterOfActiveGroups(
                votedGroup,
                stCELOInGroup[votedGroup],
                withdraw
            );
            if ((lesserKey != greaterKey || activeGroups.getNumElements() == 1) && sorted) {
                activeGroups.update(votedGroup, stCELOInGroup[votedGroup], lesserKey, greaterKey);
                votedGroup = withdraw ? activeGroups.getHead() : activeGroups.getTail();
            } else {
                unsortedGroups.add(votedGroup);
                sorted = false;
                if (withdraw) {
                    (, votedGroup, ) = activeGroups.get(votedGroup);
                } else {
                    (, , votedGroup) = activeGroups.get(votedGroup);
                }
            }
        }

        if (votesAmount != 0) {
            revert NotAbleToDistributeVotes();
        }

        finalGroups = new address[](groupsIndex);
        finalVotes = new uint256[](groupsIndex);

        for (uint256 j = 0; j < groupsIndex; j++) {
            finalGroups[j] = groups[j];
            finalVotes[j] = votes[j];
        }
    }

    function getLesserAndGreaterOfActiveGroupsDeposit(address originalKey, uint256 newValue)
        private
        view
        returns (address previous, address next)
    {
        uint256 loopLimit = sortingLoopLimit;
        address originalKeyPrevious;
        previous = originalKey;
        (, originalKeyPrevious, next) = activeGroups.get(originalKey);

        while (next != address(0) && loopLimit != 0) {
            if (newValue <= activeGroups.getValue(next)) {
                break;
            }
            previous = next;
            (, , next) = activeGroups.get(previous);
            loopLimit--;
        }

        if (loopLimit == 0) {
            return (address(0), address(0));
        }

        previous = previous == originalKey ? originalKeyPrevious : previous;
    }

    function getLesserAndGreaterOfActiveGroupsWithdrawal(address originalKey, uint256 newValue)
        private
        view
        returns (address previous, address next)
    {
        uint256 loopLimit = sortingLoopLimit;
        address originalKeyNext;
        next = originalKey;
        (, previous, originalKeyNext) = activeGroups.get(originalKey);
        while (previous != address(0) && loopLimit != 0) {
            if (newValue >= activeGroups.getValue(previous)) {
                break;
            }
            next = previous;
            (, previous, ) = activeGroups.get(next);
            loopLimit--;
        }
        if (loopLimit == 0) {
            return (address(0), address(0));
        }

        next = next == originalKey ? originalKeyNext : next;
    }
}
