// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./common/UsingRegistryUpgradeable.sol";
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
contract SpecificGroupStrategy is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Specific groups strategies (validator groups) that can be chosen to be voted on.
     */
    EnumerableSet.AddressSet private specificGroupStrategies;

    /**
     * @notice stCELO that was cast for specific group strategies,
     * strategy => stCELO amount
     */
    mapping(address => uint256) private specificGroupStrategyTotalStCeloVotes;

    /**
     * @notice Total stCELO that was voted with on specific group strategies
     */
    uint256 private totalStCeloInSpecificGroupStrategies;

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
     * @notice Emitted when a new group is specific group for voting.
     * @param group The group's address.
     */
    event StrategyAllowed(address indexed group);

    /**
     * @notice Emmited when strategy is blocked.
     * @param group The group's address.
     */
    event StrategyBlocked(address group);

    /**
     * @notice Used when attempting to disallow a strategy that is not allowed.
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
     * @notice Used when attempting to disallow a strategy failed.
     * @param group The group's address.
     */
    error FailedToBlockStrategy(address group);

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
     * @notice Used when attempting to deposit when chosen strategy cannot receive any new votes.
     * @param group The group's address.
     */
    error StrategyCannotReceiveVote(address group);

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
     * @notice Marks a group as specific group strategy for voting.
     * @param group The address of the group to add to the set of specific group
     * strategies.
     */
    function allowStrategy(address group) external onlyOwner {
        if (!groupHealth.isValidGroup(group)) {
            revert StrategyNotEligible(group);
        }

        if (specificGroupStrategies.contains(group)) {
            revert StrategyAlreadyAdded(group);
        }

        if (!specificGroupStrategies.add(group)) {
            revert FailedToAddSpecificGroupStrategy(group);
        }

        emit StrategyAllowed(group);
    }

    /**
     * @notice Marks a group as not specific group strategy for voting.
     * @param strategy The address of the group to remove from the set of specific group
     * strategies.
     */
    function blockStrategy(address strategy) external onlyOwner {
        if (defaultStrategy.getGroupsLength() == 0) {
            revert NoActiveGroups();
        }

        if (!specificGroupStrategies.contains(strategy)) {
            revert StrategyAlreadyBlocked(strategy);
        }

        uint256 strategyTotalStCeloVotes = getTotalStCeloVotesForStrategy(strategy);

        if (strategyTotalStCeloVotes != 0) {
            IManager(manager).transferBetweenStrategies(
                strategy,
                address(0),
                strategyTotalStCeloVotes
            );
        }

        if (!specificGroupStrategies.remove(strategy)) {
            revert FailedToBlockStrategy(strategy);
        }

        emit StrategyBlocked(strategy);
    }

    /**
     * @notice Used to withdraw CELO from the system from specific group strategy
     * that account voted for previously. It is expected that strategy will be balanced.
     * For balancing use `rebalance` function
     * @param strategy The validator group that we want to withdraw from.
     * @param withdrawal The amount of stCELO to withdraw.
     * @return groups The groups to withdraw from.
     * @return votes The amount to withdraw from each group.
     */
    function calculateAndUpdateForWithdrawal(
        address strategy,
        uint256 withdrawal,
        uint256 stCeloWithdrawalAmount
    ) external onlyManager returns (address[] memory groups, uint256[] memory votes) {
        uint256 votesRemaining = account.getCeloForGroup(strategy);
        if (votesRemaining < withdrawal) {
            revert GroupNotBalancedOrNotEnoughStCelo(strategy, withdrawal, votesRemaining);
        }

        (groups, votes) = calculateAndUpdateForWithdrawalTransfer(
            strategy,
            withdrawal,
            stCeloWithdrawalAmount
        );
    }

    /**
     * @notice Used to withdraw CELO from the system from specific group strategy
     * that account voted for previously. It is expected that strategy will be balanced.
     * For balancing use `rebalance` function
     * @param strategy The validator group that we want to withdraw from.
     * @param withdrawal The amount of stCELO to withdraw.
     * @return groups The groups to withdraw from.
     * @return votes The amount to withdraw from each group.
     */
    function calculateAndUpdateForWithdrawalTransfer(
        // TODO: add tests
        address strategy,
        uint256 withdrawal,
        uint256 stCeloWithdrawalAmount
    ) public onlyManager returns (address[] memory groups, uint256[] memory votes) {
        if (specificGroupStrategies.length() == 0) {
            revert NoGroups();
        }

        groups = new address[](1);
        votes = new uint256[](1);
        groups[0] = strategy;
        votes[0] = withdrawal;

        if (stCeloWithdrawalAmount > specificGroupStrategyTotalStCeloVotes[strategy]) {
            revert CantWithdrawAccordingToStrategy(strategy);
        }

        subtractFromSpecificGroupStrategyTotalStCeloVotes(strategy, stCeloWithdrawalAmount);
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
        uint256 scheduledVotes = account.scheduledVotesForGroup(strategy);
        if (!getElection().canReceiveVotes(strategy, votes + scheduledVotes)) {
            revert StrategyCannotReceiveVote(strategy);
        }
        finalGroups = new address[](1);
        finalVotes = new uint256[](1);
        finalGroups[0] = strategy;
        finalVotes[0] = votes;

        addToSpecificGroupStrategyTotalStCeloVotes(strategy, stCeloAmount);
    }

    /**
     * @notice Returns is strategy is specific group strategy.
     * @return Whether or not is specific group strategy.
     */
    function isSpecificGroupStrategy(address strategy) external view returns (bool) {
        return specificGroupStrategies.contains(strategy);
    }

    /**
     * @notice Returns is strategy is valid specific group strategy.
     * @return Whether or not is valid specific group strategy.
     */
    function isValidSpecificGroupStrategy(address strategy) external view returns (bool) {
        return specificGroupStrategies.contains(strategy) && groupHealth.isValidGroup(strategy);
    }

    /**
     * @notice Returns the total stCELO locked in specific groups.
     * @return The total stCELO.
     */
    function getTotalStCeloInSpecificGroupStrategies() external view returns (uint256) {
        return totalStCeloInSpecificGroupStrategies;
    }

    /**
     * @notice Returns the length of specific group strategies.
     * @return The length of active groups.
     */
    function getSpecificGroupStrategiesLength() external view returns (uint256) {
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
     * @notice Adds value to totals of specific group strategy and
     * total stCELO in all specific group strategies.
     * @param strategy The validator group that we are adding to.
     * @param stCeloAmount The added amount of stCELO.
     */
    function addToSpecificGroupStrategyTotalStCeloVotes(address strategy, uint256 stCeloAmount)
        public
        onlyManager
    {
        specificGroupStrategyTotalStCeloVotes[strategy] += stCeloAmount;
        totalStCeloInSpecificGroupStrategies += stCeloAmount;
    }

    /**
     * @notice Subtracts value from totals of specific group strategy and
     * total stCELO in all specific group strategies.
     * @param strategy The validator group that we are adding to.
     * @param stCeloAmount The subtracted amount of stCELO.
     */
    function subtractFromSpecificGroupStrategyTotalStCeloVotes(
        address strategy,
        uint256 stCeloAmount
    ) public onlyManager {
        specificGroupStrategyTotalStCeloVotes[strategy] -= stCeloAmount;
        totalStCeloInSpecificGroupStrategies -= stCeloAmount;
    }

    /**
     * @notice Returns the specific group total stCELO
     * @return The total stCELO amount.
     */
    function getTotalStCeloVotesForStrategy(address strategy) public view returns (uint256) {
        return specificGroupStrategyTotalStCeloVotes[strategy];
    }
}
