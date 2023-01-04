// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IGroupHealth.sol";
import "./interfaces/IManager.sol";
import "./Managed.sol";

contract AllowedStrategy is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Allowed strategies (validator groups) that can be chosen to voted on.
     */
    EnumerableSet.AddressSet private allowedStrategies;

    /**
     * @notice StCelo that was cast for allowed strategies
     * strategy => stCelo amount
     */
    mapping(address => uint256) private allowedStrategyTotalStCeloVotes;

    /**
     * @notice Total StCelo that was voted with on allowed strategy
     */
    uint256 private totalStCeloInAllowedStrategies;

    /**
     * @notice Contract used for checking group health and rebalancing.
     */
    IGroupHealth public groupHealthContract;

    /**
     * @notice An instance of the Account contract this Manager manages.
     */
    IAccount internal account;

    /**
     * @notice Emitted when a new group is allowed for voting.
     * @param group The group's address.
     */
    event StrategyAllowed(address indexed group);

    /**
     * @notice Used when strategy is blocked.
     * @param group The group's address.
     */
    event StrategyBlocked(address group);

    /**
     * @notice Used when attempting to disallow a strategy that is not allowed.
     * @param group The group's address.
     */
    error StrategyAlreadyBlocked(address group);

    /**
     * @notice Used when an attempt to add an allowed strategy to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddAllowedStrategy(address group);

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
     * @notice Used when attempting to withdraw from allowed strategy
     * but group does not have enough Celo. Group either doesn't have enough stCelo
     * or it is necessary to rebalance the group.
     * @param group The group's address.
     */
    error GroupNotBalancedOrNotEnoughStCelo(address group);

    /**
     * @notice Used when there isn't enough CELO voting for a account's strategy
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
     * @param _groupHealth The address of the Group health contract.
     */
    function setDependencies(address _account, address _groupHealth) external onlyOwner {
        require(_account != address(0), "account null address");
        require(_groupHealth != address(0), "validate group null address");

        account = IAccount(_account);
        groupHealthContract = IGroupHealth(_groupHealth);
    }

    /**
     * @notice Marks a group as allowed strategy for voting.
     * @param group The address of the group to add to the set of allowed
     * strategies.
     */
    function allowStrategy(address group) external onlyManager {
        if (!groupHealthContract.isValidGroup(group)) {
            revert StrategyNotEligible(group);
        }

        if (allowedStrategies.contains(group)) {
            revert StrategyAlreadyAdded(group);
        }

        if (!allowedStrategies.add(group)) {
            revert FailedToAddAllowedStrategy(group);
        }

        emit StrategyAllowed(group);
    }

    /**
     * @notice Marks a group as not allowed strategy for voting
     * and redistributes votes to default strategy.
     * @param group The address of the group to remove from the set of allowed
     * strategies.
     * @return total stCelo in blocked strategy
     */
    function blockStrategy(address group) external onlyManager returns (uint256) {
        if (IManager(manager).getGroupsLength() == 0) {
            revert NoActiveGroups();
        }

        if (!allowedStrategies.contains(group)) {
            revert StrategyAlreadyBlocked(group);
        }

        if (!allowedStrategies.remove(group)) {
            revert FailedToBlockStrategy(group);
        }

        emit StrategyBlocked(group);

        return getTotalStCeloVotesForStrategy(group);
    }

    /**
     * @notice Used to withdraw CELO from the system from allowed strategy
     * that account voted for previously. It is expected that strategy will be balanced.
     * For balancing use `rebalance` function
     * @param strategy The validator group that we want to withdraw from.
     * @param withdrawal The amount of stCELO to withdraw.
     * @return groups The groups to withdraw from.
     * @return votes The amount to withdraw from each group.
     */
    function withdrawFromAllowedStrategy(
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

        if (stCeloWithdrawalAmount > allowedStrategyTotalStCeloVotes[strategy]) {
            revert CantWithdrawAccordingToStrategy(strategy);
        }

        allowedStrategyTotalStCeloVotes[strategy] -= stCeloWithdrawalAmount;
        totalStCeloInAllowedStrategies -= stCeloWithdrawalAmount;
    }

    function addToTotalStCeloInAllowedStrategies(uint256 value) external onlyManager {
        totalStCeloInAllowedStrategies += value;
    }

    function subtractFromTotalStCeloInAllowedStrategies(uint256 value) external onlyManager {
        totalStCeloInAllowedStrategies -= value;
    }

    function addToAllowedStrategyTotalStCeloVotes(address strategy, uint256 value)
        external
        onlyManager
    {
        allowedStrategyTotalStCeloVotes[strategy] += value;
    }

    function subtractFromAllowedStrategyTotalStCeloVotes(address strategy, uint256 value)
        external
        onlyManager
    {
        allowedStrategyTotalStCeloVotes[strategy] -= value;
    }

    function isAllowedStrategy(address strategy) external view returns (bool) {
        return allowedStrategies.contains(strategy);
    }

    function getTotalStCeloVotesForStrategy(address strategy) public view returns (uint256) {
        return allowedStrategyTotalStCeloVotes[strategy];
    }

    function getTotalStCeloInAllowedStrategies() external view returns (uint256) {
        return totalStCeloInAllowedStrategies;
    }

    /**
     * @notice Returns the array of allowed strategies.
     * @return The array of allowed strategys.
     */
    function getAllowedStrategies() external view returns (address[] memory) {
        return allowedStrategies.values();
    }

    /**
     * @notice Returns the length of allowed strategies.
     * @return The length of active groups.
     */
    function getAllowedStrategiesLength() external view returns (uint256) {
        return allowedStrategies.length();
    }

    /**
     * @notice Returns the allowed strategy on index.
     * @return The active group.
     */
    function getAllowedStrategy(uint256 index) external view returns (address) {
        return allowedStrategies.at(index);
    }
}
