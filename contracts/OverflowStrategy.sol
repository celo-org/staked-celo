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

contract OverflowStrategy is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Overflow strategies (validator groups) that can be chosen to be voted on.
     */
    EnumerableSet.AddressSet private overflowStrategies;

    /**
     * @notice stCelo that was cast for overflow strategies,
     * strategy => stCelo amount
     */
    mapping(address => uint256) private overflowStrategyTotalStCeloVotes;

    /**
     * @notice Total stCelo that was voted with on overflow strategies
     */
    uint256 private totalStCeloInOverflowStrategies;

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
     * @notice Emitted when a new group is overflow strategy for voting.
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
     * @notice Used when an attempt to add an overflow strategy to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddOverflowStrategy(address group);

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
     * @notice Used when attempting to withdraw from overflow strategy
     * but group does not have enough Celo. Group either doesn't have enough stCelo
     * or it is necessary to rebalance the group.
     * @param group The group's address.
     */
    error GroupNotBalancedOrNotEnoughStCelo(address group);

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
     * @notice Marks a group as overflow strategy for voting.
     * @param group The address of the group to add to the set of overflow strategy
     * strategies.
     */
    function allowStrategy(address group) external onlyOwner {
        if (!groupHealth.isValidGroup(group)) {
            revert StrategyNotEligible(group);
        }

        if (overflowStrategies.contains(group)) {
            revert StrategyAlreadyAdded(group);
        }

        if (!overflowStrategies.add(group)) {
            revert FailedToAddOverflowStrategy(group);
        }

        emit StrategyAllowed(group);
    }

    /**
     * @notice Marks a group as not overflow strategy for voting.
     * @param strategy The address of the group to remove from the set of overflow strategy
     * strategies.
     */
    function blockStrategy(address strategy) external onlyOwner {
        if (defaultStrategy.getGroupsLength() == 0) {
            revert NoActiveGroups();
        }

        if (!overflowStrategies.contains(strategy)) {
            revert StrategyAlreadyBlocked(strategy);
        }

        if (!overflowStrategies.remove(strategy)) {
            revert FailedToBlockStrategy(strategy);
        }

        emit StrategyBlocked(strategy);

        uint256 strategyTotalStCeloVotes = getTotalStCeloVotesForStrategy(strategy);

        if (strategyTotalStCeloVotes != 0) {
            IManager(manager).transferBetweenStrategies(
                strategy,
                address(0),
                strategyTotalStCeloVotes
            );
        }
    }

    /**
     * @notice Used to withdraw CELO from the system from overflow strategy
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
            revert GroupNotBalancedOrNotEnoughStCelo(strategy);
        }

        groups = new address[](1);
        votes = new uint256[](1);
        groups[0] = strategy;
        votes[0] = withdrawal;

        if (stCeloWithdrawalAmount > overflowStrategyTotalStCeloVotes[strategy]) {
            revert CantWithdrawAccordingToStrategy(strategy);
        }

        subtractFromOverflowStrategyTotalStCeloVotes(strategy, stCeloWithdrawalAmount);
    }

    /**
     * @notice Adds value to totals of overflow strategy and
     * total stCelo in all overflow strategy strategies.
     * @param strategy The validator group that we are adding to.
     * @param stCeloAmount The added amount of stCelo.
     */
    function addToOverflowStrategyTotalStCeloVotes(address strategy, uint256 stCeloAmount)
        external
        onlyManager
    {
        overflowStrategyTotalStCeloVotes[strategy] += stCeloAmount;
        totalStCeloInOverflowStrategies += stCeloAmount;
    }

    /**
     * @notice Returns is strategy is overflow strategy.
     * @return Whether or not is overflow strategy.
     */
    function isOverflowStrategy(address strategy) external view returns (bool) {
        return overflowStrategies.contains(strategy);
    }

    /**
     * @notice Returns the total stCelo locked in overflow strategies.
     * @return The total stCelo.
     */
    function getTotalStCeloInOverflowStrategies() external view returns (uint256) {
        return totalStCeloInOverflowStrategies;
    }

    /**
     * @notice Returns the length of overflow strategy strategies.
     * @return The length of active groups.
     */
    function getOverflowStrategiesLength() external view returns (uint256) {
        return overflowStrategies.length();
    }

    /**
     * @notice Returns the overflow strategy on index.
     * @return The overflow strategy.
     */
    function getOverflowStrategy(uint256 index) external view returns (address) {
        return overflowStrategies.at(index);
    }

    /**
     * @notice Returns the overflow strategy strategies
     * @return The overflow strategy strategies.
     */
    function getOverflowStrategies() external view returns (address[] memory) {
        return overflowStrategies.values();
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
     * @notice Subtracts value from totals of overflow strategy and
     * total stCelo in all overflow strategy strategies.
     * @param strategy The validator group that we are adding to.
     * @param stCeloAmount The subtracted amount of stCelo.
     */
    function subtractFromOverflowStrategyTotalStCeloVotes(address strategy, uint256 stCeloAmount)
        public
        onlyManager
    {
        overflowStrategyTotalStCeloVotes[strategy] -= stCeloAmount;
        totalStCeloInOverflowStrategies -= stCeloAmount;
    }

    /**
     * @notice Returns the overflow strategy total stCelo
     * @return The total stCelo amount.
     */
    function getTotalStCeloVotesForStrategy(address strategy) public view returns (uint256) {
        return overflowStrategyTotalStCeloVotes[strategy];
    }
}
