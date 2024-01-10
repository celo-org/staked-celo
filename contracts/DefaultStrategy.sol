// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

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
contract DefaultStrategy is UUPSOwnableUpgradeable, Managed {
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
     * @notice StCELO that was cast for default group strategy,
     * strategy => stCELO amount.
     */
    mapping(address => uint256) public stCeloInGroup;

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
    uint256 public totalStCeloInStrategy;

    /**
     * @notice Loop limit while sorting active groups on chain.
     */
    uint256 private sortingLoopLimit;

    /**
     * @notice Whether or not active groups are sorted.
     * If active groups are not sorted it is neccessary to call updateActiveGroupOrder.
     */
    bool public sorted;

    /**
     * @notice Groups that need to be sorted.
     */
    EnumerableSet.AddressSet private unsortedGroups;

    /**
     * @notice Emitted when a group is deactivated.
     * @param group The group's address.
     */
    event GroupRemoved(address indexed group);

    /**
     * @notice Emitted when a new group is activated for voting.
     * @param group The group's address.
     */
    event GroupActivated(address indexed group);

    /**
     * Emmited when sorted status of active groups was changed.
     * @param update The new value.
     */
    event SortedFlagUpdated(bool update);

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
     * @notice Used when attempting to deactivate a group that is not active.
     * @param group The group's address.
     */
    error GroupNotActive(address group);

    /**
     * @notice Used when attempting to deactivate a healthy group using deactivateUnhealthyGroup().
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
    error NotUnsortedGroup();

    /**
     * @notice Used when rebalancing to a non-active group.
     * @param group The group's address.
     */
    error InvalidToGroup(address group);

    /**
     * @notice Used when rebalancing from non-active group.
     * @param group The group's address.
     */
    error InvalidFromGroup(address group);

    /**
     * @notice Used when rebalancing and `fromGroup` doesn't have any extra stCELO.
     * @param group The group's address.
     * @param actualCelo The actual stCELO value.
     * @param expectedCelo The expected stCELO value.
     */
    error RebalanceNoExtraStCelo(address group, uint256 actualCelo, uint256 expectedCelo);

    /**
     * @notice Used when rebalancing and `toGroup` has enough stCELO.
     * @param group The group's address.
     * @param actualCelo The actual stCELO value.
     * @param expectedCelo The expected stCELO value.
     */
    error RebalanceEnoughStCelo(address group, uint256 actualCelo, uint256 expectedCelo);

    /**
     * @notice Used when attempting to pass in address zero where not allowed.
     */
    error AddressZeroNotAllowed();

    /**
     *  @notice Used when a `managerOrStrategy` function is called
     *  by a non-manager or non-strategy.
     *  @param caller `msg.sender` that called the function.
     */
    error CallerNotManagerNorStrategy(address caller);

    /**
     * @notice Checks that only the manager or strategy contract can execute a function.
     */
    modifier managerOrStrategy() {
        if (manager != msg.sender && address(specificGroupStrategy) != msg.sender) {
            revert CallerNotManagerNorStrategy(msg.sender);
        }
        _;
    }

    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _owner The address of the contract owner.
     * @param _manager The address of the Manager contract.
     */
    function initialize(address _owner, address _manager) external initializer {
        _transferOwnership(_owner);
        __Managed_init(_manager);
        maxGroupsToDistributeTo = 8;
        maxGroupsToWithdrawFrom = 8;
        sortingLoopLimit = 10;
        sorted = true;
        emit SortedFlagUpdated(sorted);
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
        if (
            _account == address(0) ||
            _groupHealth == address(0) ||
            _specificGroupStrategy == address(0)
        ) {
            revert AddressZeroNotAllowed();
        }

        groupHealth = IGroupHealth(_groupHealth);
        specificGroupStrategy = ISpecificGroupStrategy(_specificGroupStrategy);
        account = IAccount(_account);
    }

    /**
     * @notice Set distribution/withdrawal algorithm parameters.
     * @param distributeTo Maximum number of groups that can be distributed to.
     * @param withdrawFrom Maximum number of groups that can be withdrawn from.
     * @param loopLimit The sorting loop limit while sorting active groups on chain.
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
     * group should receive.
     * @param celoAmount The amount of votes to distribute.
     * @param depositGroupToIgnore The group that will not be used for deposit.
     * @return finalGroups The groups that were chosen for distribution.
     * @return finalVotes The votes of chosen finalGroups.
     */
    function generateDepositVoteDistribution(uint256 celoAmount, address depositGroupToIgnore)
        external
        managerOrStrategy
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
        return _generateDepositVoteDistribution(celoAmount, depositGroupToIgnore);
    }

    /**
     * @notice Updates group order of unsorted group. When there are no more unsorted groups
     * it will mark active groups as sorted.
     * @param group The group address.
     * @param lesserKey The key of the group less than the group to update.
     * @param greaterKey The key of the group greater than the group to update.
     */
    function updateActiveGroupOrder(
        address group,
        address lesserKey,
        address greaterKey
    ) external {
        if (!unsortedGroups.contains(group)) {
            revert NotUnsortedGroup();
        }

        activeGroups.update(group, stCeloInGroup[group], lesserKey, greaterKey);
        unsortedGroups.remove(group);
        if (unsortedGroups.length() == 0) {
            sorted = true;
            emit SortedFlagUpdated(sorted);
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

        // For migration purposes between V1 and V2. It can be removed once migrated to V2.
        uint256 currentStCelo = 0;
        uint256 stCeloForWholeGroup = IManager(manager).toStakedCelo(
            account.getCeloForGroup(group)
        );

        if (stCeloForWholeGroup != 0) {
            (uint256 specificGroupTotalStCelo, , ) = specificGroupStrategy.getStCeloInGroup(group);
            currentStCelo =
                stCeloForWholeGroup -
                Math.min(stCeloForWholeGroup, specificGroupTotalStCelo);
            updateGroupStCelo(group, currentStCelo, true);
        }

        activeGroups.insert(group, currentStCelo, lesser, greater);

        emit GroupActivated(group);
    }

    /**
     * @notice Rebalances CELO between groups that have an incorrect CELO-stCELO ratio.
     * `fromGroup` is required to have more CELO than it should and `toGroup` needs
     * to have less CELO than it should.
     * @param fromGroup The from group.
     * @param toGroup The to group.
     */
    function rebalance(address fromGroup, address toGroup) external {
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

        trySort(fromGroup, stCeloInGroup[fromGroup], false);
        trySort(toGroup, stCeloInGroup[toGroup], true);
    }

    /**
     * @notice Distributes votes by computing the number of votes to be subtracted
     * from each active group.
     * @param celoAmount The amount of votes to subtract.
     * @return finalGroups The groups that were chosen for subtraction.
     * @return finalVotes The votes of chosen finalGroups.
     */
    function generateWithdrawalVoteDistribution(uint256 celoAmount)
        external
        managerOrStrategy
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
        if (activeGroups.getNumElements() == 0) {
            revert NoActiveGroups();
        }

        uint256 maxGroupCount = Math.min(maxGroupsToWithdrawFrom, activeGroups.getNumElements());

        address[] memory groups = new address[](maxGroupCount);
        uint256[] memory votes = new uint256[](maxGroupCount);

        address votedGroup = activeGroups.getHead();
        uint256 groupsIndex;

        while (groupsIndex < maxGroupCount && celoAmount != 0 && votedGroup != address(0)) {
            votes[groupsIndex] = Math.min(
                Math.min(
                    account.getCeloForGroup(votedGroup),
                    IManager(manager).toCelo(stCeloInGroup[votedGroup])
                ),
                celoAmount
            );

            groups[groupsIndex] = votedGroup;
            celoAmount -= votes[groupsIndex];
            updateGroupStCelo(
                votedGroup,
                IManager(manager).toStakedCelo(votes[groupsIndex]),
                false
            );
            trySort(votedGroup, stCeloInGroup[votedGroup], false);

            if (sorted) {
                votedGroup = activeGroups.getHead();
            } else {
                (, votedGroup, ) = activeGroups.get(votedGroup);
            }

            groupsIndex++;
        }

        if (celoAmount != 0) {
            revert NotAbleToDistributeVotes();
        }

        finalGroups = new address[](groupsIndex);
        finalVotes = new uint256[](groupsIndex);

        for (uint256 i = 0; i < groupsIndex; i++) {
            finalGroups[i] = groups[i];
            finalVotes[i] = votes[i];
        }
    }

    /**
     * @notice Deactivates group.
     * @param group The group to deactivated.
     */
    function deactivateGroup(address group) external onlyOwner {
        _deactivateGroup(group);
    }

    /**
     * @notice Deactivates an unhealthy group.
     * @param group The group to deactivate if unhealthy.
     */
    function deactivateUnhealthyGroup(address group) external {
        if (groupHealth.isGroupValid(group)) {
            revert HealthyGroup(group);
        }
        _deactivateGroup((group));
    }

    /**
     * @notice Returns the number of active groups.
     * @return The number of active groups.
     */
    function getNumberOfGroups() external view returns (uint256) {
        return activeGroups.getNumElements();
    }

    /**
     * @notice Returns previous and next address of key.
     * @param group The group address.
     * @return previousAddress The previous address.
     * @return nextAddress The next address.
     */
    function getGroupPreviousAndNext(address group)
        external
        view
        returns (address previousAddress, address nextAddress)
    {
        (, previousAddress, nextAddress) = activeGroups.get(group);
    }

    /**
     * @notice Returns head and previous address of head.
     * @return head The address of the sorted group with most votes.
     * @return previousAddress The previous address from head.
     */
    function getGroupsHead() external view returns (address head, address previousAddress) {
        head = activeGroups.getHead();
        (, previousAddress, ) = activeGroups.get(head);
    }

    /**
     * @notice Returns tail and next address of tail.
     * @return tail The address of the sorted group with least votes.
     * @return nextAddress The next address after tail.
     */
    function getGroupsTail() external view returns (address tail, address nextAddress) {
        tail = activeGroups.getTail();
        (, , nextAddress) = activeGroups.get(tail);
    }

    /**
     * @notice Returns whether active groups contain group.
     * @return Whether or not the given group is active.
     */
    function isActive(address group) external view returns (bool) {
        return activeGroups.contains(group);
    }

    /**
     * @notice Returns the number of unsorted groups.
     * @return The number of unsorted groups.
     */
    function getNumberOfUnsortedGroups() external view returns (uint256) {
        return unsortedGroups.length();
    }

    /**
     * @notice Returns the unsorted group at index.
     * @param index The index to look up.
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
     * @notice Returns expected stCELO and actual stCELO for group.
     * @param group The group.
     * @return expectedStCelo The amount of stCELO that group should have.
     * (The total amount of stCELO in the default strategy divided by the number of active groups.)
     * @return actualStCelo The amount of stCELO which is currently
     * assigned to group in the strategy.
     */
    function getExpectedAndActualStCeloForGroup(address group)
        public
        view
        returns (uint256 expectedStCelo, uint256 actualStCelo)
    {
        address head = activeGroups.getHead();
        uint256 numberOfActiveGroups = activeGroups.getNumElements();
        expectedStCelo = totalStCeloInStrategy / numberOfActiveGroups;
        if (group == head) {
            uint256 divisionResidue = totalStCeloInStrategy -
                (expectedStCelo * numberOfActiveGroups);
            expectedStCelo += divisionResidue;
        }

        actualStCelo = stCeloInGroup[group];
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
            stCeloInGroup[group] += stCeloAmount;
            totalStCeloInStrategy += stCeloAmount;
        } else {
            stCeloInGroup[group] -= stCeloAmount;
            totalStCeloInStrategy -= stCeloAmount;
        }
    }

    /**
     * @notice Deactivates group.
     * @param group The group to deactivated.
     */
    function _deactivateGroup(address group) private {
        if (!activeGroups.contains(group)) {
            revert GroupNotActive(group);
        }
        activeGroups.remove(group);
        unsortedGroups.remove(group);

        uint256 groupTotalStCeloVotes = stCeloInGroup[group];

        if (groupTotalStCeloVotes > 0) {
            updateGroupStCelo(group, groupTotalStCeloVotes, false);
            address[] memory fromGroups = new address[](1);
            uint256[] memory fromVotes = new uint256[](1);
            fromGroups[0] = group;
            fromVotes[0] = IManager(manager).toCelo(groupTotalStCeloVotes);
            (
                address[] memory toGroups,
                uint256[] memory toVotes
            ) = _generateDepositVoteDistribution(
                    IManager(manager).toCelo(groupTotalStCeloVotes),
                    address(0)
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
     * group should receive.
     * @param celoAmount The amount of votes to distribute.
     * @param depositGroupToIgnore The group that will not be used for deposit.
     * @return finalGroups The groups that were chosen for distribution.
     * @return finalVotes The votes of chosen finalGroups.
     */
    function _generateDepositVoteDistribution(uint256 celoAmount, address depositGroupToIgnore)
        private
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
        if (activeGroups.getNumElements() == 0) {
            revert NoActiveGroups();
        }

        uint256 maxGroupCount = Math.min(maxGroupsToDistributeTo, activeGroups.getNumElements());

        address[] memory groups = new address[](maxGroupCount);
        uint256[] memory votes = new uint256[](maxGroupCount);

        address votedGroup = activeGroups.getTail();
        uint256 groupsIndex;

        while (groupsIndex < maxGroupCount && celoAmount != 0 && votedGroup != address(0)) {
            uint256 receivableVotes = IManager(manager).getReceivableVotesForGroup(votedGroup);
            if (votedGroup == depositGroupToIgnore || receivableVotes == 0) {
                (, , votedGroup) = activeGroups.get(votedGroup);
                continue;
            }

            votes[groupsIndex] = Math.min(receivableVotes, celoAmount);
            groups[groupsIndex] = votedGroup;
            celoAmount -= votes[groupsIndex];
            updateGroupStCelo(votedGroup, IManager(manager).toStakedCelo(votes[groupsIndex]), true);
            trySort(votedGroup, stCeloInGroup[votedGroup], true);

            if (sorted) {
                votedGroup = activeGroups.getTail();
            } else {
                (, , votedGroup) = activeGroups.get(votedGroup);
            }
            groupsIndex++;
        }

        if (celoAmount != 0) {
            revert NotAbleToDistributeVotes();
        }

        finalGroups = new address[](groupsIndex);
        finalVotes = new uint256[](groupsIndex);

        for (uint256 i = 0; i < groupsIndex; i++) {
            finalGroups[i] = groups[i];
            finalVotes[i] = votes[i];
        }
    }

    /**
     * Try to sort group in active groups based on new value.
     * @param group The group address.
     * @param newValue The new value of group.
     * @param valueIncreased Whether value increased/decreased compared to original value.
     */
    function trySort(
        address group,
        uint256 newValue,
        bool valueIncreased
    ) private {
        if (unsortedGroups.contains(group)) {
            return;
        }

        (address lesserKey, address greaterKey) = valueIncreased
            ? activeGroups.getLesserAndGreaterOfAddressThatIncreasedValue(
                group,
                newValue,
                sortingLoopLimit
            )
            : activeGroups.getLesserAndGreaterOfAddressThatDecreasedValue(
                group,
                newValue,
                sortingLoopLimit
            );
        if (lesserKey != greaterKey || activeGroups.getNumElements() == 1) {
            activeGroups.update(group, newValue, lesserKey, greaterKey);
        } else {
            if (sorted) {
                sorted = false;
            }
            unsortedGroups.add(group);
        }
    }
}
