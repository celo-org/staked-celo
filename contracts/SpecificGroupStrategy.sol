// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UUPSOwnableUpgradeable.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IGroupHealth.sol";
import "./interfaces/IManager.sol";
import "./interfaces/IDefaultStrategy.sol";
import "./Managed.sol";

/**
 * @title SpecificGroupStrategy is responsible for handling any deposit/withdrawal
 * for accounts with specific strategy selected.
 */
contract SpecificGroupStrategy is UUPSOwnableUpgradeable, Managed {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Validator groups that is voted for.
     */
    EnumerableSet.AddressSet private votedGroups;

    /**
     * @notice Validator groups that were blocked from voting.
     */
    EnumerableSet.AddressSet private blockedGroups;

    /**
     * @notice stCELO that was cast for specific group strategies,
     * group => stCELO amount
     */
    mapping(address => uint256) public stCeloInGroup;

    /**
     * @notice Total stCELO that was voted with on specific group strategies (including overflows).
     * @dev To get the actual stCelo in specific strategy
     * it is necessary to subtract `totalStCeloOverflow`.
     */
    uint256 public totalStCeloLocked;

    /**
     * @notice stCELO that was cast for specific group strategies and overflowed
     * to default strategy: group => stCELO amount.
     */
    mapping(address => uint256) private stCeloInGroupOverflowed;

    /**
     * @notice Total stCelo that was overflowed to default strategy.
     */
    uint256 public totalStCeloOverflow;

    /**
     * @notice stCELO that was cast for specific group strategies that
     * became unhealthy and was transfered to default strategy:
     * group => stCELO amount.
     */
    mapping(address => uint256) private stCeloInGroupUnhealthy;

    /**
     * @notice Total stCelo that is cast for unhealthy groups and was moved to default strategy.
     */
    uint256 public totalStCeloUnhealthy;

    /**
     * @notice An instance of the GroupHealth contract for the StakedCelo protocol.
     */
    IGroupHealth public groupHealth;

    /**
     * @notice An instance of the DefaultStrategy contract for the StakedCelo protocol.
     */
    IDefaultStrategy public defaultStrategy;

    /**
     * @notice An instance of the Account contract for the StakedCelo protocol.
     */
    IAccount public account;

    /**
     * @notice Emitted when a group was unblocked.
     * @param group The group's address.
     */
    event GroupUnblocked(address indexed group);

    /**
     * @notice Emmited when group is blocked.
     * @param group The group's address.
     */
    event GroupBlocked(address group);

    /**
     * @notice Used when attempting to block a group that is not allowed.
     * @param group The group's address.
     */
    error GroupAlreadyBlocked(address group);

    /**
     * @notice Used when an attempt to add an specific group to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddGroup(address group);

    /**
     * @notice Used when attempting to block a group failed.
     * @param group The group's address.
     */
    error FailedToBlockGroup(address group);

    /**
     * @notice Used when attempting to unblock a group that is not blocked.
     * @param group The group's address.
     */
    error FailedToUnblockGroup(address group);

    /**
     * @notice Used when a group does not meet the validator group health requirements.
     * @param group The group's address.
     */
    error GroupNotEligible(address group);

    /**
     * @notice Used when attempting to pass in address zero where not allowed.
     */
    error AddressZeroNotAllowed();

    /**
     * @notice Used when attempting to withdraw from specific group
     * but group does not have enough CELO. It is necessary to rebalance the group.
     * @param group The group's address.
     */
    error GroupNotBalanced(address group);

    /**
     * @notice Used when there isn't enough CELO voting for an account's strategy
     * to fulfill a withdrawal.
     * @param group The group's address.
     */
    error CantWithdrawAccordingToStrategy(address group);

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
     * Used when trying to `rebalanceOverflowedGroup` when the group is not overflowing.
     * @param group The group address.
     */
    error GroupNotOverflowing(address group);

    /**
     * Used when trying to `rebalanceOverflowedGroup` when the overflowing group cannot
     * be rebalanced since it has no receivable votes.
     * @param group The group address.
     */
    error GroupStillOverflowing(address group);

    /**
     * Used when trying to `rebalanceWhenHealthChanged` when the group cannot
     * be rebalanced since it is in correct state.
     * @param group The group address.
     */
    error GroupBalanced(address group);

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
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @param _account The address of the Account contract.
     * @param _groupHealth The address of the GroupHealth contract.
     * @param _defaultStrategy The address of the DefaultStrategy contract.
     */
    function setDependencies(
        address _account,
        address _groupHealth,
        address _defaultStrategy
    ) external onlyOwner {
        if (
            _account == address(0) || _groupHealth == address(0) || _defaultStrategy == address(0)
        ) {
            revert AddressZeroNotAllowed();
        }

        account = IAccount(_account);
        groupHealth = IGroupHealth(_groupHealth);
        defaultStrategy = IDefaultStrategy(_defaultStrategy);
    }

    /**
     * @notice Unblocks previously blocked group.
     * @param group The address of the group to add to the set of specific group
     * strategies.
     */
    function unblockGroup(address group) external onlyOwner {
        if (!groupHealth.isGroupValid(group)) {
            revert GroupNotEligible(group);
        }

        if (!blockedGroups.remove(group)) {
            revert FailedToUnblockGroup(group);
        }

        emit GroupUnblocked(group);
    }

    /**
     * @notice Marks a group as blocked for voting.
     * @param group The group address.
     */
    function blockGroup(address group) external onlyOwner {
        _blockGroup(group);
    }

    /**
     * @notice Used to withdraw CELO from a specific group
     * that account voted for previously. It is expected that strategy will be balanced.
     * For balancing use `rebalance` function.
     * @param group The validator group that we want to withdraw from.
     * @param celoWithdrawalAmount The amount of CELO to withdraw.
     * @param stCeloWithdrawalAmount The amount of stCELO to withdraw.
     * @return groups The groups to withdraw from.
     * @return votes The amount to withdraw from each group.
     */
    function generateWithdrawalVoteDistribution(
        address group,
        uint256 celoWithdrawalAmount,
        uint256 stCeloWithdrawalAmount,
        bool isTransfer
    ) external onlyManager returns (address[] memory groups, uint256[] memory votes) {
        if (votedGroups.length() == 0) {
            revert NoGroups();
        }

        if (stCeloWithdrawalAmount > stCeloInGroup[group]) {
            revert CantWithdrawAccordingToStrategy(group);
        }

        updateGroupStCelo(group, stCeloWithdrawalAmount, false);

        uint256 overflowingStCelo = stCeloInGroupOverflowed[group];
        uint256 unhealthyStCelo = stCeloInGroupUnhealthy[group];
        if (overflowingStCelo > 0 || unhealthyStCelo > 0) {
            uint256 celoToBeMovedFromDefaultStrategy = Math.min(
                celoWithdrawalAmount,
                IManager(manager).toCelo(overflowingStCelo + unhealthyStCelo)
            );
            celoWithdrawalAmount -= celoToBeMovedFromDefaultStrategy;

            (address[] memory overflowGroups, uint256[] memory overflowVotes) = defaultStrategy
                .generateWithdrawalVoteDistribution(celoToBeMovedFromDefaultStrategy);

            handleWithdrawalOverflowAndUnhealthyAccounting(
                group,
                celoToBeMovedFromDefaultStrategy,
                overflowingStCelo
            );

            if (celoWithdrawalAmount > 0) {
                groups = new address[](overflowGroups.length + 1);
                votes = new uint256[](overflowGroups.length + 1);
                for (uint256 i = 0; i < overflowGroups.length; i++) {
                    groups[i] = overflowGroups[i];
                    votes[i] = overflowVotes[i];
                }
                if (!isTransfer && account.getCeloForGroup(group) < celoWithdrawalAmount) {
                    revert GroupNotBalanced(group);
                }
                groups[overflowGroups.length] = group;
                votes[overflowGroups.length] = celoWithdrawalAmount;
            } else {
                groups = overflowGroups;
                votes = overflowVotes;
            }
        } else {
            groups = new address[](1);
            votes = new uint256[](1);
            groups[0] = group;
            votes[0] = celoWithdrawalAmount;
        }
    }

    /**
     * @notice Generates groups and votes to distribute votes to.
     * @param group The validator group that we want to deposit to or transfer from.
     * @param celoAmount The amount of CELO.
     * @param stCeloAmount The amount of stCELO.
     * @return finalGroups The groups to withdraw from.
     * @return finalVotes The amount to withdraw from each group.
     */
    function generateDepositVoteDistribution(
        address group,
        uint256 celoAmount,
        uint256 stCeloAmount
    ) external onlyManager returns (address[] memory finalGroups, uint256[] memory finalVotes) {
        votedGroups.add(group);
        updateGroupStCelo(group, stCeloAmount, true);

        if (groupHealth.isGroupValid(group) && !blockedGroups.contains(group)) {
            uint256 receivableVotes = IManager(manager).getReceivableVotesForGroup(group);
            uint256 votesToBeScheduledForSpecificGroup = Math.min(receivableVotes, celoAmount);

            celoAmount -= votesToBeScheduledForSpecificGroup;
            if (celoAmount > 0) {
                // overflow
                (address[] memory groups, uint256[] memory votesForGroups) = defaultStrategy
                    .generateDepositVoteDistribution(celoAmount, group);
                updateOverflowGroup(group, IManager(manager).toStakedCelo(celoAmount), true);
                finalGroups = new address[](groups.length + 1);
                finalVotes = new uint256[](groups.length + 1);
                for (uint256 i = 0; i < groups.length; i++) {
                    finalGroups[i] = groups[i];
                    finalVotes[i] = votesForGroups[i];
                }
                finalGroups[groups.length] = group;
                finalVotes[groups.length] = votesToBeScheduledForSpecificGroup;
            } else {
                finalGroups = new address[](1);
                finalVotes = new uint256[](1);
                finalGroups[0] = group;
                finalVotes[0] = votesToBeScheduledForSpecificGroup;
            }
        } else {
            (finalGroups, finalVotes) = defaultStrategy.generateDepositVoteDistribution(
                celoAmount,
                group
            );
            updateUnhealthyGroupStCelo(group, stCeloAmount, true);
        }
    }

    /**
     * @notice Used when validator gets unhealthy and we need to move funds to default strategy
     * @param group The group address.
     */
    function rebalanceWhenHealthChanged(address group) external {
        bool isGroupValid = groupHealth.isGroupValid(group);
        uint256 unhealthyStCelo = stCeloInGroupUnhealthy[group];

        if (isGroupValid && !blockedGroups.contains(group)) {
            if (unhealthyStCelo == 0) {
                revert GroupBalanced(group);
            }
            uint256 toMove = unhealthyStCelo;

            transferFromDefaultStrategy(group, toMove);
            updateUnhealthyGroupStCelo(group, toMove, false);
        } else {
            uint256 totalStCeloInGroup = stCeloInGroup[group];
            if (totalStCeloInGroup == unhealthyStCelo) {
                revert GroupBalanced(group);
            }

            if (defaultStrategy.getNumberOfGroups() == 0) {
                revert NoActiveGroups();
            }

            uint256 overflow = stCeloInGroupOverflowed[group];
            uint256 toMove = totalStCeloInGroup - unhealthyStCelo - overflow;

            transferToDefaultStrategy(group, toMove);
            updateUnhealthyGroupStCelo(group, toMove, true);
        }
    }

    /**
     * @notice Returns if a group is a voted group.
     * @param group The validator group.
     * @return Whether or not is group is voted.
     */
    function isVotedGroup(address group) external view returns (bool) {
        return votedGroups.contains(group);
    }

    /**
     * @notice Returns if group is blocked.
     * @param group The validator group.
     * @return Whether or not group is blocked.
     */
    function isBlockedGroup(address group) external view returns (bool) {
        return blockedGroups.contains(group);
    }

    /**
     * @notice Returns the number of blocked groups.
     * @return The length of blocked groups.
     */
    function getNumberOfBlockedGroups() external view returns (uint256) {
        return blockedGroups.length();
    }

    /**
     * @notice Returns the blocked group at index.
     * @return The blocked group.
     */
    function getBlockedGroup(uint256 index) external view returns (address) {
        return blockedGroups.at(index);
    }

    /**
     * @notice Returns the number of voted groups.
     * @return The length of voted groups.
     */
    function getNumberOfVotedGroups() external view returns (uint256) {
        return votedGroups.length();
    }

    /**
     * @notice Returns the specific group at index.
     * @return The specific group.
     */
    function getVotedGroup(uint256 index) external view returns (address) {
        return votedGroups.at(index);
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
     * @notice When there is group that is overflowing and
     * in meantime there are votes that freed up. This function
     * makes sure to reschedule votes correctly for overflowing group.
     * @param group The group address.
     */
    function rebalanceOverflowedGroup(address group) public {
        if (!groupHealth.isGroupValid(group) || blockedGroups.contains(group)) {
            revert GroupNotEligible(group);
        }

        uint256 overflowingStCelo = stCeloInGroupOverflowed[group];
        if (overflowingStCelo == 0) {
            revert GroupNotOverflowing(group);
        }

        uint256 receivableVotes = IManager(manager).getReceivableVotesForGroup(group);
        if (receivableVotes == 0) {
            revert GroupStillOverflowing(group);
        }

        uint256 receivableStCelo = IManager(manager).toStakedCelo(receivableVotes);
        uint256 toMove = Math.min(receivableStCelo, overflowingStCelo);
        transferFromDefaultStrategy(group, toMove);
        updateOverflowGroup(group, toMove, false);
    }

    /**
     * @notice Returns the specific group total stCELO.
     * @return total The total stCELO amount.
     * @return overflow The stCELO amount that is overflowed to default strategy.
     * @return unhealthy The stCELO amount that is moved to default strategy
     * because group is/was unhealthy.
     */
    function getStCeloInGroup(address group)
        public
        view
        returns (
            uint256 total,
            uint256 overflow,
            uint256 unhealthy
        )
    {
        total = stCeloInGroup[group];
        overflow = stCeloInGroupOverflowed[group];
        unhealthy = stCeloInGroupUnhealthy[group];
    }

    /**
     * @notice Adds/substracts value to totals of strategy and
     * total stCELO in specific group.
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
            totalStCeloLocked += stCeloAmount;
        } else {
            stCeloInGroup[group] -= stCeloAmount;
            totalStCeloLocked -= stCeloAmount;
        }
    }

    /**
     * @notice Adds/substracts value to unhealthy totals of strategy and
     * unhealthy total stCELO in specific group.
     * @param group The validator group that we are updating.
     * @param stCeloAmount The amount of stCELO.
     * @param add Whether to add or substract.
     */
    function updateUnhealthyGroupStCelo(
        address group,
        uint256 stCeloAmount,
        bool add
    ) internal {
        if (add) {
            stCeloInGroupUnhealthy[group] += stCeloAmount;
            totalStCeloUnhealthy += stCeloAmount;
        } else {
            stCeloInGroupUnhealthy[group] -= stCeloAmount;
            totalStCeloUnhealthy -= stCeloAmount;
        }
    }

    /**
     * @notice Updates overflow stCELO amount of group.
     * @param group The group that is overflowing.
     * @param stCeloAmount The stCELO amount.
     * @param add Whether to add or subtract stCELO amount.
     */
    function updateOverflowGroup(
        address group,
        uint256 stCeloAmount,
        bool add
    ) private {
        if (add) {
            stCeloInGroupOverflowed[group] += stCeloAmount;
            totalStCeloOverflow += stCeloAmount;
        } else {
            stCeloInGroupOverflowed[group] -= stCeloAmount;
            totalStCeloOverflow -= stCeloAmount;
        }
    }

    /**
     * @notice Blocks a group from being added as voted group.
     * @param group The group address.
     */
    function _blockGroup(address group) private {
        if (defaultStrategy.getNumberOfGroups() == 0) {
            revert NoActiveGroups();
        }

        if (blockedGroups.contains(group)) {
            revert GroupAlreadyBlocked(group);
        }

        blockedGroups.add(group);

        emit GroupBlocked(group);
    }

    /**
     * Transfers stCelo to default strategy without updating accounting in specific group.
     * @param group The group addres.
     * @param stCeloToMove StCelo amount to be moved.
     */
    function transferToDefaultStrategy(address group, uint256 stCeloToMove) private {
        uint256 toMoveCelo = IManager(manager).toCelo(stCeloToMove);
        address[] memory fromGroups = new address[](1);
        uint256[] memory fromVotes = new uint256[](1);
        fromGroups[0] = group;
        fromVotes[0] = toMoveCelo;
        (address[] memory toGroups, uint256[] memory toVotes) = defaultStrategy
            .generateDepositVoteDistribution(toMoveCelo, address(0));
        IManager(manager).scheduleTransferWithinStrategy(fromGroups, toGroups, fromVotes, toVotes);
    }

    /**
     * Transfers stCelo from default strategy without updating accounting in specific group.
     * @param group The group addres.
     * @param stCeloToMove StCELO amount to be moved.
     */
    function transferFromDefaultStrategy(address group, uint256 stCeloToMove) private {
        uint256 toMoveCelo = IManager(manager).toCelo(stCeloToMove);
        (address[] memory fromGroups, uint256[] memory fromVotes) = defaultStrategy
            .generateWithdrawalVoteDistribution(toMoveCelo);
        address[] memory toGroups = new address[](1);
        uint256[] memory toVotes = new uint256[](1);
        toGroups[0] = group;
        toVotes[0] = toMoveCelo;
        IManager(manager).scheduleTransferWithinStrategy(fromGroups, toGroups, fromVotes, toVotes);
    }

    /**
     * Handles accounting when group is overflowing/unhelthy during withdrawal.
     * @param group The group address.
     * @param celoToBeMovedFromDefaultStrategy The celo that is being moved from default strategy.
     * @param overflowingStCelo StCELO amount that is overflowing.
     */
    function handleWithdrawalOverflowAndUnhealthyAccounting(
        address group,
        uint256 celoToBeMovedFromDefaultStrategy,
        uint256 overflowingStCelo
    ) private {
        uint256 stCeloToBeMoved = IManager(manager).toStakedCelo(celoToBeMovedFromDefaultStrategy);
        uint256 subtractedFromOveflow = Math.min(overflowingStCelo, stCeloToBeMoved);
        if (subtractedFromOveflow > 0) {
            updateOverflowGroup(group, subtractedFromOveflow, false);
        }
        uint256 subtracteddFromUnHealthy = stCeloToBeMoved - subtractedFromOveflow;
        if (subtracteddFromUnHealthy > 0) {
            updateUnhealthyGroupStCelo(group, subtracteddFromUnHealthy, false);
        }
    }
}
