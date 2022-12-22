// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IStakedCelo.sol";
import "./interfaces/IVote.sol";

/**
 * @title Manages the StakedCelo system, by controlling the minting and burning
 * of stCELO and implementing strategies for voting and unvoting of deposited or
 * withdrawn CELO.
 */
contract Manager is UUPSOwnableUpgradeable, UsingRegistryUpgradeable {
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
     * @notice An instance of the StakedCelo contract this Manager manages.
     */
    IStakedCelo internal stakedCelo;

    /**
     * @notice An instance of the Account contract this Manager manages.
     */
    IAccount internal account;

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
     * @notice Contract used during Governance voting.
     */
    address public voteContract;

    /**
     * @notice address -> strategy
     * address(0) = default strategy
     * !address(0) = voting for allowed validator group
     */
    mapping(address => address) private strategies;

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
     * @notice Emitted when the vote contract is initially set or later modified.
     * @param voteContract The new vote contract address.
     */
    event VoteContractSet(address indexed voteContract);

    /**
     * @notice Emitted when a new group is activated for voting.
     * @param group The group's address.
     */
    event GroupActivated(address indexed group);
    /**
     * @notice Emitted when a new group is allowed for voting.
     * @param group The group's address.
     */
    event GroupAllowed(address indexed group);
    /**
     * @notice Emitted when a group is deprecated.
     * @param group The group's address.
     */
    event GroupDeprecated(address indexed group);
    /**
     * @notice Emitted when a deprecated group is no longer being voted for and
     * the contract forgets about it entirely.
     * @param group The group's address.
     */
    event GroupRemoved(address indexed group);

    /**
     * @notice Used when strategy is disallow.
     * @param group The group's address.
     */
    event StrategyDisallowed(address group);

    /**
     * @notice Used when attempting to activate a group that is already active.
     * @param group The group's address.
     */
    error GroupAlreadyAdded(address group);

    /**
     * @notice Used when attempting to deprecate a group that is not active.
     * @param group The group's address.
     */
    error GroupNotActive(address group);

    /**
     * @notice Used when attempting to disallow a strategy that is not allowed.
     * @param group The group's address.
     */
    error StrategyNotAllowed(address group);

    /**
     * @notice Used when attempting to disallow a strategy failed.
     * @param group The group's address.
     */
    error FailedToDisallowStrategy(address group);

    /**
     * @notice Used when an attempt to add an active group to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddActiveGroup(address group);

    /**
     * @notice Used when an attempt to add an allowed strategy to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddAllowedStrategy(address group);

    /**
     * @notice Used when an attempt to add a deprecated group to the
     * EnumerableSet fails.
     * @param group The group's address.
     */
    error FailedToAddDeprecatedGroup(address group);

    /**
     * @notice Used when an attempt to remove a deprecated group from the
     * EnumerableSet fails.
     * @param group The group's address.
     */
    error FailedToRemoveDeprecatedGroup(address group);

    /**
     * @notice Used when attempting to activate a group when the maximum number
     * of groups voted (as allowed by the Election contract) is already being
     * voted for.
     */
    error MaxGroupsVotedForReached();

    /**
     * @notice Used when attempting to deposit when there are not active groups
     * to vote for.
     */
    error NoActiveGroups();

    /**
     * @notice Used when attempting to deposit when the total deposit amount
     * would tip each active group over the voting limit as defined in
     * Election.sol.
     */
    error NoVotableGroups();

    /**
     * @notice Used when attempting to withdraw but there are no groups being
     * voted for.
     */
    error NoGroups();

    /**
     * @notice Used when attempting to withdraw 0 value.
     */
    error ZeroWithdrawal();

    /**
     * @notice Used when a group does not meet the validator group health requirements.
     * @param group The group's address.
     */
    error GroupNotEligible(address group);

    /**
     * @notice Used when attempting to deprecated a healthy group using deprecateUnhealthyGroup().
     * @param group The group's address.
     */
    error HealthyGroup(address group);

    /**
     * @notice Used when there isn't enough CELO voting for a account's strategy
     * to fulfill a withdrawal.
     * @param group The group's address.
     */
    error CantWithdrawAccordingToStrategy(address group);

    /**
     * @notice Used when attempting to change strategy when sender has no stCelo.
     */
    error NoStakedCelo();

    /**
     *  @notice Used when an `onlyStCelo` function is called by a non-stCelo contract.
     *  @param caller `msg.sender` that called the function.
     */
    error CallerNotStakedCelo(address caller);

    /**
     * @notice Used when attempting to change strategy to same strategy.
     */
    error SameStrategy();

    /**
     * @notice Used when attempting to withdraw from allowed strategy
     * but group does not have enough Celo. Group either doesn't have enough stCelo
     * or it is necessary to rebalance the group.
     * @param group The group's address.
     */
    error GroupNotBalancedOrNotEnoughStCelo(address group);

    /**
     * @dev Throws if called by any account other than StakedCelo.
     */
    modifier onlyStakedCelo() {
        if (address(stakedCelo) != msg.sender) {
            revert CallerNotStakedCelo(msg.sender);
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
     * @param _registry The address of the Celo registry.
     * @param _owner The address of the contract owner.
     */
    function initialize(address _registry, address _owner) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @dev Manager, Account and StakedCelo all reference each other
     * so we need a way of setting these after all contracts are
     * deployed and initialized.
     * @param _stakedCelo the address of the StakedCelo contract.
     * @param _account The address of the Account contract.
     * @param _vote The address of the Vote contract.
     */
    function setDependencies(
        address _stakedCelo,
        address _account,
        address _vote
    ) external onlyOwner {
        require(_stakedCelo != address(0), "stakedCelo null address");
        require(_account != address(0), "account null address");
        require(_vote != address(0), "vote null address");

        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
        voteContract = _vote;
        emit VoteContractSet(_vote);
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
        if (!isValidGroup(group)) {
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
            getElection().maxNumGroupsVotedFor()
        ) {
            revert MaxGroupsVotedForReached();
        }

        if (!activeGroups.add(group)) {
            revert FailedToAddActiveGroup(group);
        }

        emit GroupActivated(group);
    }

    /**
     * @notice Marks a group as allowed strategy for voting.
     * @param group The address of the group to add to the set of allowed
     * strategies.
     */
    function allowStrategy(address group) external onlyOwner {
        if (!isValidGroup(group)) {
            revert GroupNotEligible(group);
        }

        if (allowedStrategies.contains(group)) {
            revert GroupAlreadyAdded(group);
        }

        if (deprecatedGroups.contains(group)) {
            if (!deprecatedGroups.remove(group)) {
                revert FailedToRemoveDeprecatedGroup(group);
            }
        }

        if (!allowedStrategies.add(group)) {
            revert FailedToAddAllowedStrategy(group);
        }

        emit GroupAllowed(group);
    }

    /**
     * @notice Marks a group as not allowed strategy for voting
     * and redistributes votes to default strategy.
     * @param group The address of the group to remove from the set of allowed
     * strategies.
     */
    function disallowStrategy(address group) external onlyOwner {
        if (!allowedStrategies.contains(group)) {
            revert StrategyNotAllowed(group);
        }

        if (activeGroups.length() == 0) {
            revert NoActiveGroups();
        }

        if (!allowedStrategies.remove(group)) {
            revert FailedToDisallowStrategy(group);
        }

        uint256 strategyTotalStCeloVotes = allowedStrategyTotalStCeloVotes[group];

        if (strategyTotalStCeloVotes != 0) {
            _transferWithoutChecks(group, address(0), strategyTotalStCeloVotes);
        }

        emit StrategyDisallowed(group);
    }

    /**
     * @notice Returns the array of active groups.
     * @return The array of active groups.
     */
    function getGroups() external view returns (address[] memory) {
        return activeGroups.values();
    }

    /**
     * @notice Returns the array of allowed strategies.
     * @return The array of allowed strategys.
     */
    function getAllowedStrategies() external view returns (address[] memory) {
        return allowedStrategies.values();
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
     * @notice Checks if a group meets the validator group health requirements.
     * @param group The group to check for.
     * @return Whether or not the group is valid.
     */
    function isValidGroup(address group) public view returns (bool) {
        IValidators validators = getValidators();

        // add check if group is !registered
        if (!validators.isValidatorGroup(group)) {
            return false;
        }

        (address[] memory members, , , , , uint256 slashMultiplier, ) = validators
            .getValidatorGroup(group);

        // check if group has no members
        if (members.length == 0) {
            return false;
        }
        // check for recent slash
        if (slashMultiplier < 10**24) {
            return false;
        }
        // check that at least one member is elected.
        for (uint256 i = 0; i < members.length; i++) {
            if (isGroupMemberElected(members[i])) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Marks an unhealthy group as deprecated.
     * @param group The group to deprecate if unhealthy.
     * @dev A deprecated group will remain in the `deprecatedGroups` array as
     * long as it is still being voted for by the Account contract. Deprecated
     * groups will be the first to have their votes withdrawn.
     */
    function deprecateUnhealthyGroup(address group) external {
        if (isValidGroup(group)) {
            revert HealthyGroup(group);
        }
        _deprecateGroup((group));
    }

    /**
     * @notice Returns the list of deprecated groups.
     * @return The list of deprecated groups.
     */
    function getDeprecatedGroups() external view returns (address[] memory) {
        return deprecatedGroups.values();
    }

    /**
     * @notice Used to deposit CELO into the StakedCelo system. The user will
     * receive an amount of stCELO proportional to their contribution. The CELO
     * will be scheduled to be voted for with the Account contract.
     * The CELO will be distributed based on accoutn strategy.
     */
    function deposit() external payable {
        address strategy = _checkAndUpdateStrategy(msg.sender, strategies[msg.sender]);

        uint256 stCeloValue = toStakedCelo(msg.value);

        if (strategy == address(0)) {
            if (activeGroups.length() == 0) {
                revert NoActiveGroups();
            }
        } else {
            if (!isValidGroup(strategy)) {
                // if invalid group vote for default strategy
                strategies[msg.sender] = address(0);
                strategy = address(0);
                uint256 stCeloBalance = stakedCelo.balanceOf(msg.sender);
                if (stCeloBalance != 0) {
                    _transfer(strategy, address(0), stCeloBalance, msg.sender, msg.sender);
                }
            } else {
                allowedStrategyTotalStCeloVotes[strategy] += stCeloValue;
                totalStCeloInAllowedStrategies += stCeloValue;
            }
        }

        stakedCelo.mint(msg.sender, stCeloValue);
        distributeAndScheduleVotes(msg.value, strategy);
    }

    /**
     * @notice Used to withdraw CELO from the system, in exchange for burning
     * stCELO.
     * @param stakedCeloAmount The amount of stCELO to burn.
     * @dev Calculates the CELO amount based on the ratio of outstanding stCELO
     * and the total amount of CELO owned and used for voting by Account. See
     * `toCelo`.
     * @dev The funds need to be withdrawn using calls to `Account.withdraw` and
     * `Account.finishPendingWithdrawal`.
     */
    function withdraw(uint256 stakedCeloAmount) external {
        if (activeGroups.length() + deprecatedGroups.length() + allowedStrategies.length() == 0) {
            revert NoGroups();
        }

        distributeWithdrawals(stakedCeloAmount, msg.sender);
        stakedCelo.burn(msg.sender, stakedCeloAmount);
    }

    /**
     * @notice Computes the amount of stCELO that should be minted for a given
     * amount of CELO deposited.
     * @param celoAmount The amount of CELO deposited.
     * @return The amount of stCELO that should be minted.
     */
    function toStakedCelo(uint256 celoAmount) public view returns (uint256) {
        uint256 stCeloSupply = stakedCelo.totalSupply();
        uint256 celoBalance = account.getTotalCelo();

        if (stCeloSupply == 0 || celoBalance == 0) {
            return celoAmount;
        }

        return (celoAmount * stCeloSupply) / celoBalance;
    }

    /**
     * @notice Computes the amount of CELO that should be withdrawn for a given
     * amount of stCELO burned.
     * @param stCeloAmount The amount of stCELO burned.
     * @return The amount of CELO that should be withdrawn.
     */
    function toCelo(uint256 stCeloAmount) public view returns (uint256) {
        uint256 stCeloSupply = stakedCelo.totalSupply();
        uint256 celoBalance = account.getTotalCelo();

        if (stCeloSupply == 0 || celoBalance == 0) {
            return stCeloAmount;
        }

        return (stCeloAmount * celoBalance) / stCeloSupply;
    }

    /**
     * @notice Distributes votes corresponding groups and schedules them for vote.
     * @param votes The amount of votes to distribute.
     * @param strategy The chosen strategy.
     */
    function distributeAndScheduleVotes(uint256 votes, address strategy) internal {
        address[] memory finalGroups;
        uint256[] memory finalVotes;
        (finalGroups, finalVotes) = distributeVotes(votes, strategy);
        account.scheduleVotes{value: votes}(finalGroups, finalVotes);
    }

    /**
     * @notice Distributes votes according to chosen strategy.
     * @param votes The amount of votes to distribute.
     * @param strategy The chosen strategy.
     */
    function distributeVotes(uint256 votes, address strategy)
        private
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
        if (strategy != address(0)) {
            finalGroups = new address[](1);
            finalVotes = new uint256[](1);
            finalGroups[0] = strategy;
            finalVotes[0] = votes;
        } else {
            (finalGroups, finalVotes) = generateDefaultStrategyGroupsVotesToDistributeTo(votes);
        }

        return (finalGroups, finalVotes);
    }

    /**
     * @notice Distributes votes by computing the number of votes each active
     * group should receive, then calling out to `Account.scheduleVotes`.
     * @param votes The amount of votes to distribute.
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
    function generateDefaultStrategyGroupsVotesToDistributeTo(uint256 votes)
        internal
        returns (address[] memory finalGroups, uint256[] memory finalVotes)
    {
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

        for (uint256 i = 0; i < groupsVoted; i++) {
            finalGroups[i] = sortedGroups[i].group;
            finalVotes[i] = votesPerGroup[i];
        }

        return (finalGroups, finalVotes);
    }

    /**
     * @notice Distributes withdrawals according to chosend strategy.
     * @param stCeloAmount The amount of stCelo to be withdrawn.
     * @param beneficiary The address that should end up receiving the withdrawn
     * CELO.
     **/
    function distributeWithdrawals(uint256 stCeloAmount, address beneficiary) private {
        uint256 withdrawal = toCelo(stCeloAmount);
        if (withdrawal == 0) {
            revert ZeroWithdrawal();
        }

        address strategy = _checkAndUpdateStrategy(beneficiary, strategies[beneficiary]);

        if (strategy != address(0)) {
            distributeWithdrawalsSpecificStrategy(withdrawal, stCeloAmount, beneficiary, strategy);
        } else {
            distributeWithdrawalsDefaultStrategy(withdrawal, beneficiary);
        }
    }

    /**
     * @notice Distributes withdrawals from allowed strategy.
     * @param withdrawal The amount of votes to withdraw.
     * @param stCeloWithdrawalAmount The amount of stCelo to be withdrawn.
     * @param beneficiary The address that should end up receiving the withdrawn
     * CELO.
     * @param strategy The validator group that we want to withdraw from.
     **/
    function distributeWithdrawalsSpecificStrategy(
        uint256 withdrawal,
        uint256 stCeloWithdrawalAmount,
        address beneficiary,
        address strategy
    ) private {
        address[] memory specificGroupsWithdrawn;
        uint256[] memory specificWithdrawalsPerGroup;

        (specificGroupsWithdrawn, specificWithdrawalsPerGroup) = withdrawFromSpecificGroup(
            strategy,
            withdrawal,
            stCeloWithdrawalAmount
        );

        account.scheduleWithdrawals(
            beneficiary,
            specificGroupsWithdrawn,
            specificWithdrawalsPerGroup
        );
    }

    /**
     * @notice Distributes withdrawals from default strategy by computing the number of votes that
     * should be withdrawn from each group, then calling out to
     * `Account.scheduleWithdrawals`.
     * @param withdrawal The amount of votes to withdraw.
     * @param beneficiary The address that should end up receiving the withdrawn
     * CELO.
     * @dev The withdrawal distribution strategy is to:
     * 1. Withdraw as much as possible from any deprecated groups.
     * 2. If more votes still need to be withdrawn, try and have each validator
     * group end up receiving the same amount of votes from the system. If a
     * group already has less votes than the average of the total remaining
     * votes, it will not be withdrawn from, and instead we'll try to evenly
     * distribute between the remaining groups.
     */
    function distributeWithdrawalsDefaultStrategy(uint256 withdrawal, address beneficiary)
        internal
    {
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

        address[] memory finalGroups = new address[](
            groupsWithdrawn.length + numberDeprecatedGroupsWithdrawn
        );
        uint256[] memory finalVotes = new uint256[](
            groupsWithdrawn.length + numberDeprecatedGroupsWithdrawn
        );

        for (uint256 i = 0; i < numberDeprecatedGroupsWithdrawn; i++) {
            finalGroups[i] = deprecatedGroupsWithdrawn[i];
            finalVotes[i] = deprecatedWithdrawalsPerGroup[i];
        }

        for (uint256 i = 0; i < groupsWithdrawn.length; i++) {
            finalGroups[i + numberDeprecatedGroupsWithdrawn] = groupsWithdrawn[i];
            finalVotes[i + numberDeprecatedGroupsWithdrawn] = withdrawalsPerGroup[i];
        }

        account.scheduleWithdrawals(beneficiary, finalGroups, finalVotes);
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
    function withdrawFromSpecificGroup(
        address strategy,
        uint256 withdrawal,
        uint256 stCeloWithdrawalAmount
    ) private returns (address[] memory groups, uint256[] memory votes) {
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

        if (allowedStrategyTotalStCeloVotes[strategy] == 0) {
            if (allowedStrategies.remove(strategy)) {
                allowedStrategyTotalStCeloVotes[strategy] = 0;
                emit GroupRemoved(strategy);
            }
        }
    }

    /**
     * @notice Whenever stCELO is being transferd we will check whether origin and target
     * account use same strategy. If strategy differs we will schedule votes for transfer.
     * @param from The from account.
     * @param to The to account.
     * @param stCeloAmount The stCelo amount.
     */
    function transfer(
        address from,
        address to,
        uint256 stCeloAmount
    ) public onlyStakedCelo {
        address fromStrategy = strategies[from];
        address toStrategy = strategies[to];
        _transfer(fromStrategy, toStrategy, stCeloAmount, from, to);
    }

    /**
     * @notice Allows account to change strategy.
     * address(0) = default strategy
     * !address(0) = voting for allowed validator group. Group needs to be in allowed
     * @param newStrategy The from account.
     */
    function changeStrategy(address newStrategy) public {
        if (
            newStrategy != address(0) &&
            (!allowedStrategies.contains(newStrategy) || !isValidGroup(newStrategy))
        ) {
            revert GroupNotEligible(newStrategy);
        }

        uint256 stCeloAmount = stakedCelo.balanceOf(msg.sender);
        if (stCeloAmount != 0) {
            address currentStrategy = strategies[msg.sender];
            _transfer(currentStrategy, newStrategy, stCeloAmount, msg.sender, msg.sender);
        }

        strategies[msg.sender] = _checkStrategy(newStrategy);
    }

    /**
     * @notice Rebalances Celo between groups that have incorrect Celo-stCelo ratio.
     * FromGroup is required to have more Celo than it should and ToGroup needs
     * to have less Celo than it should.
     * @param fromGroup The from group.
     * @param toGroup The to group.
     */
    function rebalance(address fromGroup, address toGroup) public {
        uint256 expectedFromCelo;
        uint256 realFromCelo;

        if (toGroup != _checkStrategy(toGroup)) {
            // rebalancinch to deprecated/non-existant group is not allowed
            revert GroupNotEligible(toGroup);
        }

        (expectedFromCelo, realFromCelo) = getExpectedAndRealCeloForGroup(fromGroup);

        if (realFromCelo <= expectedFromCelo) {
            // fromGroup needs to have more Celo than it should
            revert GroupNotEligible(fromGroup);
        }

        uint256 expectedToCelo;
        uint256 realToCelo;

        (expectedToCelo, realToCelo) = getExpectedAndRealCeloForGroup(toGroup);

        if (realToCelo >= expectedToCelo) {
            // toGroup needs to have less Celo than it should
            revert GroupNotEligible(toGroup);
        }

        address[] memory fromGroups = new address[](1);
        address[] memory toGroups = new address[](1);
        uint256[] memory fromVotes = new uint256[](1);
        uint256[] memory toVotes = new uint256[](1);

        fromGroups[0] = fromGroup;
        fromVotes[0] = Math.min(realFromCelo - expectedFromCelo, expectedToCelo - realToCelo);

        toGroups[0] = toGroup;
        toVotes[0] = fromVotes[0];

        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
    }

    /**
     * @notice Returns expected Celo amount voted for by Account contract
     * vs actual amount voted for by Acccount contract
     * @param group The group.
     */
    function getExpectedAndRealCeloForGroup(address group) public view returns (uint256, uint256) {
        bool isAllowedStrategy = allowedStrategies.contains(group);
        bool isActiveGroup = activeGroups.contains(group);
        uint256 realCelo = account.getCeloForGroup(group);

        if (!isAllowedStrategy && !isActiveGroup) {
            return (0, realCelo);
        }

        if (isAllowedStrategy && !isActiveGroup) {
            return (toCelo(allowedStrategyTotalStCeloVotes[group]), realCelo);
        }

        if (!isAllowedStrategy && isActiveGroup) {
            uint256 stCeloSupply = stakedCelo.totalSupply();
            uint256 stCeloInDefaultStrategy = stCeloSupply - totalStCeloInAllowedStrategies;
            uint256 supposedStCeloInActiveGroup = stCeloInDefaultStrategy / activeGroups.length();

            return (toCelo(supposedStCeloInActiveGroup), realCelo);
        }

        if (isAllowedStrategy && isActiveGroup) {
            uint256 stCeloSupply = stakedCelo.totalSupply();
            uint256 stCeloInDefaultStrategy = stCeloSupply - totalStCeloInAllowedStrategies;
            uint256 supposedStCeloInActiveGroup = stCeloInDefaultStrategy / activeGroups.length();
            uint256 supposedCeloInSpecificGroup = toCelo(allowedStrategyTotalStCeloVotes[group]);

            return (toCelo(supposedStCeloInActiveGroup + supposedCeloInSpecificGroup), realCelo);
        }

        revert GroupNotEligible(group);
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
            uint256 currentVotes = account.getCeloForGroup(deprecatedGroupsWithdrawn[i]);
            deprecatedWithdrawalsPerGroup[i] = Math.min(remainingWithdrawal, currentVotes);
            remainingWithdrawal -= deprecatedWithdrawalsPerGroup[i];

            if (currentVotes == deprecatedWithdrawalsPerGroup[i]) {
                if (!deprecatedGroups.remove(deprecatedGroupsWithdrawn[i])) {
                    revert FailedToRemoveDeprecatedGroup(deprecatedGroupsWithdrawn[i]);
                }
                emit GroupRemoved(deprecatedGroupsWithdrawn[i]);
            }

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
        view
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
            if (availableVotes % numberGroupsWithdrawn > i) {
                withdrawalsPerGroup[i]--;
            }
        }

        return (groupsWithdrawn, withdrawalsPerGroup);
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
            uint256 votes = allowedStrategies.contains(groups[i])
                ? account.getCeloForGroup(groups[i]) -
                    toCelo(allowedStrategyTotalStCeloVotes[groups[i]])
                : account.getCeloForGroup(groups[i]);
            totalVotes += votes;
            groupsWithVotes[i] = GroupWithVotes(groups[i], votes);
        }

        sortGroupsWithVotes(groupsWithVotes);
        return (groupsWithVotes, totalVotes);
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
     * @notice Votes on a proposal in the referendum stage.
     * @param proposalId The ID of the proposal to vote on.
     * @param index The index of the proposal ID in `dequeued`.
     * @param yesVotes The yes votes weight.
     * @param noVotes The no votes weight.
     * @param abstainVotes The abstain votes weight.
     */
    function voteProposal(
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) public {
        IVote vote = IVote(voteContract);

        (
            uint256 stCeloUsedForVoting,
            uint256 totalYesVotes,
            uint256 totalNoVotes,
            uint256 totalAbstainVotes
        ) = vote.voteProposal(msg.sender, proposalId, yesVotes, noVotes, abstainVotes);

        stakedCelo.lockVoteBalance(msg.sender, stCeloUsedForVoting);
        account.votePartially(proposalId, index, totalYesVotes, totalNoVotes, totalAbstainVotes);
    }

    /**
     * @notice Revokes votes on already voted proposal.
     * @param proposalId The ID of the proposal to vote on.
     * @param index The index of the proposal ID in `dequeued`.
     */
    function revokeVotes(uint256 proposalId, uint256 index) external {
        IVote vote = IVote(voteContract);

        (uint256 totalYesVotes, uint256 totalNoVotes, uint256 totalAbstainVotes) = vote.revokeVotes(
            msg.sender,
            proposalId
        );

        account.votePartially(proposalId, index, totalYesVotes, totalNoVotes, totalAbstainVotes);
    }

    /**
     * @notice Unlock balance of vote stCelo and update beneficiary vote history.
     * @param beneficiary The account to be unlocked.
     */
    function updateHistoryAndReturnLockedStCeloInVoting(address beneficiary)
        external
        returns (uint256)
    {
        IVote vote = IVote(voteContract);
        return vote.updateHistoryAndReturnLockedStCeloInVoting(beneficiary);
    }

    /**
     * @notice Unlock vote balance of stCelo.
     * @param accountAddress The account to be unlocked.
     */
    function unlockBalance(address accountAddress) public {
        stakedCelo.unlockVoteBalance(accountAddress);
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

        if (account.getCeloForGroup(group) - toCelo(allowedStrategyTotalStCeloVotes[group]) > 0) {
            if (!deprecatedGroups.add(group)) {
                revert FailedToAddDeprecatedGroup(group);
            }
        } else {
            emit GroupRemoved(group);
        }
    }

    /**
     * @notice Checks if a group member is elected.
     * @param groupMember The member of the group to check election status for.
     * @return Whether or not the group member is elected.
     */
    function isGroupMemberElected(address groupMember) private view returns (bool) {
        IElection election = getElection();

        address[] memory electedValidatorSigners = election.electValidatorSigners();

        for (uint256 i = 0; i < electedValidatorSigners.length; i++) {
            if (electedValidatorSigners[i] == groupMember) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Checks if strategy was depracated. Depracated strategy is reverted to default.
     * Updates the strategies.
     * @param accountAddress The account.
     * @param strategy The strategy.
     * @return Up to date strategy
     */
    function _checkAndUpdateStrategy(address accountAddress, address strategy)
        private
        returns (address)
    {
        address checkedStrategy = _checkStrategy(strategy);
        if (checkedStrategy != strategy) {
            strategies[accountAddress] = checkedStrategy;
        }
        return checkedStrategy;
    }

    /**
     * @notice Checks if strategy was depracated. Depracated strategy is reverted to default.
     * @param strategy The strategy.
     * @return Up to date strategy
     */
    function _checkStrategy(address strategy) private view returns (address) {
        if (strategy != address(0) && !allowedStrategies.contains(strategy)) {
            // strategy deprecated revert to default strategy
            return address(0);
        }

        return strategy;
    }

    /**
     * @notice Schedules transfer of Celo between strategies.
     * @param fromStrategy The from validator group.
     * @param toStrategy The to validator group.
     * @param stCeloAmount The stCelo amount.
     * @param from The from address.
     * @param to The to address.
     */
    function _transfer(
        address fromStrategy,
        address toStrategy,
        uint256 stCeloAmount,
        address from,
        address to
    ) private {
        fromStrategy = _checkAndUpdateStrategy(from, fromStrategy);
        toStrategy = _checkAndUpdateStrategy(to, toStrategy);

        if (fromStrategy == toStrategy) {
            // either both addresses use default strategy
            // or both addresses use same allowed strategy
            return;
        }

        _transferWithoutChecks(fromStrategy, toStrategy, stCeloAmount);
    }

    /**
     * @notice Schedules transfer of Celo between strategies.
     * @param fromStrategy The from validator group.
     * @param toStrategy The to validator group.
     * @param stCeloAmount The stCelo amount.
     */
    function _transferWithoutChecks(
        address fromStrategy,
        address toStrategy,
        uint256 stCeloAmount
    ) private {
        address[] memory fromGroups;
        uint256[] memory fromVotes;
        (fromGroups, fromVotes) = distributeVotes(toCelo(stCeloAmount), fromStrategy);

        address[] memory toGroups;
        uint256[] memory toVotes;
        (toGroups, toVotes) = distributeVotes(toCelo(stCeloAmount), toStrategy);

        if (fromStrategy == address(0)) {
            totalStCeloInAllowedStrategies += stCeloAmount;
        } else if (toStrategy == address(0)) {
            totalStCeloInAllowedStrategies -= stCeloAmount;
        }

        if (fromStrategy != address(0)) {
            allowedStrategyTotalStCeloVotes[fromStrategy] -= stCeloAmount;
        }
        if (toStrategy != address(0)) {
            allowedStrategyTotalStCeloVotes[toStrategy] += stCeloAmount;
        }

        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
    }

    /**
     * @notice Returns which strategy is account using
     * address(0) = default strategy
     * !address(0) = voting for allowed validator group
     * @param accountAddress The account.
     * @return The strategy.
     */
    function getAccountStrategy(address accountAddress) external view returns (address) {
        return _checkStrategy(strategies[accountAddress]);
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
        return (1, 2, 1, 0);
    }
}
