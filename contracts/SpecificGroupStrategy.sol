// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IGroupHealth.sol";
import "./interfaces/IManager.sol";
import "./interfaces/IDefaultStrategy.sol";
import "./Managed.sol";
import "hardhat/console.sol";

/**
 * @title SpecificGroupStrategy is responsible for handling any deposit/withdrawal
 * for accounts with specific strategy selected.
 */
contract SpecificGroupStrategy is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Specific groups strategies (validator groups) that can be chosen to be voted on.
     */
    EnumerableSet.AddressSet private specificGroupStrategies;

    /**
     * @notice Specific groups strategies that were blocked from voting.
     */
    EnumerableSet.AddressSet private blockedStrategies;

    /**
     * @notice stCELO that was cast for specific group strategies,
     * strategy => stCELO amount
     */
    mapping(address => uint256) public stCeloInStrategy;

    /**
     * @notice Total stCELO that was voted with on specific group strategies (including overflows).
     * To get the actual stCelo in specific strategy
     * it is necessary to subtract `totalStCeloOverflow`.
     */
    uint256 public totalStCeloLocked;

    /**
     * @notice stCELO that was cast for specific group strategies and overflown to defautl strategy,
     * strategy => stCELO amount.
     */
    mapping(address => uint256) private stCeloInStrategyOverflown;

    /**
     * @notice Total stCelo that was overflown to default strategy.
     */
    uint256 public totalStCeloOverflow;

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
     * @notice Emitted when a strategy was unlbocked.
     * @param group The group's address.
     */
    event StrategyUnblocked(address indexed group);

    /**
     * @notice Emmited when strategy is blocked.
     * @param group The group's address.
     */
    event StrategyBlocked(address group);

    /**
     * @notice Used when attempting to block a strategy that is not allowed.
     * @param group The group's address.
     */
    error StrategyAlreadyBlocked(address group);

    /**
     * @notice Used when an attempt to add an specific group strategy to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddSpecificGroupStrategy(address group);

    /**
     * @notice Used when attempting to block a strategy failed.
     * @param group The group's address.
     */
    error FailedToBlockStrategy(address group);

    /**
     * @notice Used when attempting to unblock a strategy that is not blocked.
     * @param group The group's address.
     */
    error FailedToUnBlockStrategy(address group);

    /**
     * @notice Used when attempting to allow strategy that is already allowed.
     * @param group The group's address.
     */
    error StrategyAlreadyAdded(address group);

    /**
     * @notice Used when a strategy does not meet the validator group health requirements.
     * @param group The group's address.
     */
    error StrategyNotEligible(address group);

    /**
     * @notice Used when attempting to withdraw from specific group strategy
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
     * @notice Used when attempting to block a healthy group using `blockUnhealthyStrategy`.
     * @param group The group's address.
     */
    error HealthyGroup(address group);

    /**
     * @notice Used when attempting to allow a strategy when the maximum number
     * of groups voted (as allowed by the Election contract) is already being
     * voted for.
     */
    error MaxGroupsVotedForReached();

    /**
     * Used when trying to `rebalanceOverflownGroup` when the group is not overflowing.
     * @param group The group address.
     */
    error GroupNotOverflowing(address group);

    /**
     * Used when trying to `rebalanceOverflownGroup` when the overflowing group cannot
     * be rebalanced since it has not receivable votes.
     * @param group The group address.
     */
    error GroupStillOverflowing(address group);

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
        require(_account != address(0), "Account null");
        require(_groupHealth != address(0), "GroupHealth null");
        require(_defaultStrategy != address(0), "DefaultStrategy null");

        account = IAccount(_account);
        groupHealth = IGroupHealth(_groupHealth);
        defaultStrategy = IDefaultStrategy(_defaultStrategy);
    }

    /**
     * @notice Unblocks previously blocked Strategy
     * @param group The address of the group to add to the set of specific group
     * strategies.
     */
    function unblockStrategy(address group) external onlyOwner {
        if (!groupHealth.isGroupValid(group)) {
            revert StrategyNotEligible(group);
        }

        if (!blockedStrategies.remove(group)) {
            revert FailedToUnBlockStrategy(group);
        }
        emit StrategyUnblocked(group);
    }

    /**
     * @notice Marks a group as not specific group strategy for voting.
     * @param group The address of the group to remove from the set of specific group
     * strategies.
     */
    function blockStrategy(address group) external onlyOwner {
        _blockStrategy(group);
    }

    /**
     * @notice Blocks unhealthy group.
     * @param group The group to block if unhealthy.
     */
    function blockUnhealthyStrategy(address group) external {
        if (groupHealth.isGroupValid(group)) {
            revert HealthyGroup(group);
        }
        _blockStrategy(group);
    }

    /**
     * @notice Used to withdraw CELO from a specific group strategy
     * that account voted for previously. It is expected that strategy will be balanced.
     * For balancing use `rebalance` function.
     * @param strategy The validator group that we want to withdraw from.
     * @param celoWitdrawalAmount The amount of CELO to withdraw.
     * @param stCeloWithdrawalAmount The amount of stCELO to withdraw.
     * @return groups The groups to withdraw from.
     * @return votes The amount to withdraw from each group.
     */
    function calculateAndUpdateForWithdrawal(
        address strategy,
        uint256 celoWitdrawalAmount,
        uint256 stCeloWithdrawalAmount
    ) external onlyManager returns (address[] memory groups, uint256[] memory votes) {
        (groups, votes) = calculateAndUpdateForWithdrawalTransfer(
            strategy,
            celoWitdrawalAmount,
            stCeloWithdrawalAmount
        );

        uint256 votesRemaining = account.getCeloForGroup(strategy);
        if (votesRemaining < celoWitdrawalAmount) {
            revert GroupNotBalancedOrNotEnoughStCelo(strategy, celoWitdrawalAmount, votesRemaining);
        }
    }

    /**
     * @notice Generates groups and votes to distribute votes to.
     * @param strategy The validator group that we want to deposit to or transfer from.
     * @param votes The amount of votes.
     * @return finalGroups The groups to withdraw from.
     * @return finalVotes The amount to withdraw from each group.
     */
    function generateGroupVotesToDistributeTo(
        address strategy,
        uint256 votes,
        uint256 stCeloAmount
    ) external onlyManager returns (address[] memory finalGroups, uint256[] memory finalVotes) {
        specificGroupStrategies.add(strategy);

        uint256 votesToBeScheduledForSpecificStrategy;

        if (
            (specificGroupStrategies.length() + defaultStrategy.getActiveGroupsNumber()) >=
            getElection().maxNumGroupsVotedFor() &&
            !getElection().allowedToVoteOverMaxNumberOfGroups(address(account))
        ) {
            // if voting for more groups than allowed
            // we will overflow everything to default strategy
            votesToBeScheduledForSpecificStrategy = 0;
        } else {
            uint256 receivableVotes = IManager(manager).getReceivableVotesForGroup(strategy);
            votesToBeScheduledForSpecificStrategy = Math.min(receivableVotes, votes);
        }

        votes -= votesToBeScheduledForSpecificStrategy;
        if (votes > 0) {
            // overflow
            (address[] memory groups, uint256[] memory votesForGroups) = defaultStrategy
                .generateVoteDistribution(votes, false, strategy);
            updateOverflowGroup(strategy, votes, true);
            finalGroups = new address[](groups.length + 1);
            finalVotes = new uint256[](groups.length + 1);
            for (uint256 i = 0; i < groups.length; i++) {
                finalGroups[i] = groups[i];
                finalVotes[i] = votesForGroups[i];
            }
            finalGroups[groups.length] = strategy;
            finalVotes[groups.length] = votesToBeScheduledForSpecificStrategy;
        } else {
            finalGroups = new address[](1);
            finalVotes = new uint256[](1);
            finalGroups[0] = strategy;
            finalVotes[0] = votesToBeScheduledForSpecificStrategy;
        }

        updateGroupStCelo(strategy, stCeloAmount, true);
    }

    /**
     * @notice Returns if a group is a valid specific group strategy.
     * @param strategy The validator group.
     * @return Whether or not is specific group strategy.
     */
    function isSpecificGroupStrategy(address strategy) external view returns (bool) {
        return specificGroupStrategies.contains(strategy);
    }

    /**
     * @notice Returns if strategy is blocked.
     * @param strategy The validator group.
     * @return Whether or not is blocked specific group strategy.
     */
    function isBlockedSpecificGroupStrategy(address strategy) external view returns (bool) {
        return blockedStrategies.contains(strategy);
    }

    /**
     * @notice Returns the length of blocked group strategies.
     * @return The length of blocked groups.
     */
    function getBlockedStrategiesNumber() external view returns (uint256) {
        return blockedStrategies.length();
    }

    /**
     * @notice Returns the blocked group strategy at index.
     * @return The blocked group.
     */
    function getBlockedStrategy(uint256 index) external view returns (address) {
        return blockedStrategies.at(index);
    }

    /**
     * @notice Returns the length of specific group strategies.
     * @return The length of active groups.
     */
    function getSpecificGroupStrategiesNumber() external view returns (uint256) {
        return specificGroupStrategies.length();
    }

    /**
     * @notice Returns the specific group strategy at index.
     * @return The specific group.
     */
    function getSpecificGroupStrategy(uint256 index) external view returns (address) {
        return specificGroupStrategies.at(index);
    }

    /**
     * @notice Returns the specific group strategies
     * @return The specific group strategies.
     */
    function getSpecificGroupStrategies() external view returns (address[] memory) {
        return specificGroupStrategies.values();
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
     * @notice Used to withdraw CELO from the system from specific group strategy
     * that account voted for previously. It is expected that strategy will be balanced.
     * For balancing use `rebalance` function
     * @param strategy The validator group that we want to withdraw from.
     * @param celoWitdrawalAmount The amount of stCELO to withdraw.
     * @return groups The groups to withdraw from.
     * @return votes The amount to withdraw from each group.
     */
    function calculateAndUpdateForWithdrawalTransfer(
        // TODO: add tests
        address strategy,
        uint256 celoWitdrawalAmount,
        uint256 stCeloWithdrawalAmount
    ) public onlyManager returns (address[] memory groups, uint256[] memory votes) {
        if (specificGroupStrategies.length() == 0) {
            revert NoGroups();
        }

        if (stCeloWithdrawalAmount > stCeloInStrategy[strategy]) {
            revert CantWithdrawAccordingToStrategy(strategy);
        }

        uint256 overflowingStCelo = stCeloInStrategyOverflown[strategy];
        if (overflowingStCelo > 0) {
            uint256 overflowingCelo = IManager(manager).toCelo(overflowingStCelo);
            uint256 celoToBeMovedFromOverflow = Math.min(celoWitdrawalAmount, overflowingCelo);
            (address[] memory overflowGroups, uint256[] memory overflowVotes) = defaultStrategy
                .generateVoteDistribution(celoToBeMovedFromOverflow, true, address(0));
            uint256 stCeloToBeMoved = IManager(manager).toStakedCelo(celoToBeMovedFromOverflow);
            updateOverflowGroup(strategy, stCeloToBeMoved, false);
            celoWitdrawalAmount -= celoToBeMovedFromOverflow;
            if (celoWitdrawalAmount > 0) {
                groups = new address[](overflowGroups.length + 1);
                votes = new uint256[](overflowGroups.length + 1);
                for (uint256 i = 0; i < overflowGroups.length; i++) {
                    groups[i] = overflowGroups[i];
                    votes[i] = overflowVotes[i];
                }
                groups[overflowGroups.length] = strategy;
                votes[overflowGroups.length] = celoWitdrawalAmount;
            } else {
                groups = overflowGroups;
                votes = overflowVotes;
            }
        } else {
            groups = new address[](1);
            votes = new uint256[](1);
            groups[0] = strategy;
            votes[0] = celoWitdrawalAmount;
        }

        updateGroupStCelo(strategy, stCeloWithdrawalAmount, false);
    }

    /**
     * @notice When there is function that is overflowing and
     * in meantime there are votes that freed up. This function
     * makes sure to reschedule votes correctly for overflowing group.
     * @param strategy The group address
     */
    function rebalanceOverflownGroup(address strategy) public {
        uint256 overflowingStCelo = stCeloInStrategyOverflown[strategy];
        if (overflowingStCelo == 0) {
            revert GroupNotOverflowing(strategy);
        }

        uint256 receivableVotes = IManager(manager).getReceivableVotesForGroup(strategy);
        if (receivableVotes == 0) {
            revert GroupStillOverflowing(strategy);
        }

        uint256 receivableStCelo = IManager(manager).toStakedCelo(receivableVotes);
        uint256 toMove = Math.min(receivableStCelo, overflowingStCelo);
        updateGroupStCelo(strategy, toMove, false);
        IManager(manager).transferBetweenStrategies(address(0), strategy, toMove);
        updateOverflowGroup(strategy, toMove, false);
    }

    /**
     * @notice Returns the specific group total stCELO
     * @return total The total stCELO amount.
     * @return overflow The stCELO amount that is overflown to default strategy.
     */
    function getStCeloInStrategy(address strategy)
        public
        view
        returns (uint256 total, uint256 overflow)
    {
        total = stCeloInStrategy[strategy];
        overflow = stCeloInStrategyOverflown[strategy];
    }

    /**
     * @notice Adds/substracts value to totals of strategy and
     * total stCELO in specific strategy.
     * @param strategy The validator group that we are updating.
     * @param stCeloAmount The amount of stCELO.
     * @param add Whether to add or substract.
     */
    function updateGroupStCelo(
        address strategy,
        uint256 stCeloAmount,
        bool add
    ) internal {
        if (add) {
            stCeloInStrategy[strategy] += stCeloAmount;
            totalStCeloLocked += stCeloAmount;
        } else {
            stCeloInStrategy[strategy] -= stCeloAmount;
            totalStCeloLocked -= stCeloAmount;
        }
    }

    /**
     * @notice Updates overflow stCELO amount of strategy.
     * @param strategy The strategy that is overflowing.
     * @param stCeloAmount The stCELO amount.
     * @param add Whether to add or subtract stCELO amount.
     */
    function updateOverflowGroup(
        address strategy,
        uint256 stCeloAmount,
        bool add
    ) private {
        if (add) {
            stCeloInStrategyOverflown[strategy] += stCeloAmount;
            totalStCeloOverflow += stCeloAmount;
        } else {
            stCeloInStrategyOverflown[strategy] -= stCeloAmount;
            totalStCeloOverflow -= stCeloAmount;
        }
    }

    /**
     * @notice Marks a group as not specific group strategy for voting.
     * @param group The address of the group to remove from the set of specific group
     * strategies.
     */
    function _blockStrategy(address group) private {
        if (defaultStrategy.getActiveGroupsNumber() == 0) {
            revert NoActiveGroups();
        }

        if (blockedStrategies.contains(group)) {
            revert StrategyAlreadyBlocked(group);
        }

        (uint256 stCeloInSpecificStrategy, uint256 overflownStCelo) = getStCeloInStrategy(group);

        if (stCeloInSpecificStrategy - overflownStCelo != 0) {
            IManager(manager).transferBetweenStrategies(
                group,
                address(0),
                stCeloInSpecificStrategy
            );
        }

        specificGroupStrategies.remove(group);
        blockedStrategies.add(group);

        emit StrategyBlocked(group);
    }
}
