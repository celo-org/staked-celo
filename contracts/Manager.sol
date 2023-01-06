// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IStakedCelo.sol";
import "./interfaces/IVote.sol";
import "./interfaces/IGroupHealth.sol";
import "./interfaces/ISpecificGroupStrategy.sol";
import "./interfaces/IDefaultStrategy.sol";
import "hardhat/console.sol";

/**
 * @title Manages the StakedCelo system, by controlling the minting and burning
 * of stCELO and implementing strategies for voting and unvoting of deposited or
 * withdrawn CELO.
 */
contract Manager is UUPSOwnableUpgradeable, UsingRegistryUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

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
     * @notice An instance of the GroupHealth contract for the StakedCelo protocol.
     */
    IGroupHealth public groupHealth;

    /**
     * @notice An instance of the SpecificGroupStrategy contract for the StakedCelo protocol.
     */
    ISpecificGroupStrategy public specificGroupStrategy;

    /**
     * @notice An instance of the DefaultGroupStrategy contract for the StakedCelo protocol.
     */
    IDefaultStrategy public defaultStrategy;

    /**
     * @notice address -> strategy
     * address(0) = default strategy
     * !address(0) = voting for allowed validator group
     */
    mapping(address => address) private strategies;
    /**
     * @notice Emitted when the vote contract is initially set or later modified.
     * @param voteContract The new vote contract address.
     */
    event VoteContractSet(address indexed voteContract);
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
     * @notice Emitted when a new group is activated for voting.
     * @param group The group's address.
     */
    event GroupActivated(address indexed group);

    /**
     * @notice Used when attempting to deprecate a group that is not active.
     * @param group The group's address.
     */
    error GroupNotActive(address group);

    /**
     * @notice Used when an attempt to add an active group to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddActiveGroup(address group);

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
     * @notice Used when an `onlyStCelo` function is called by a non-stCelo contract.
     * @param caller `msg.sender` that called the function.
     */
    error CallerNotStakedCelo(address caller);

    /**
     * @notice Used when an `onlyDefaultStrategy` function
     * is called by a non-defaultStrategy contract.
     * @param caller `msg.sender` that called the function.
     */
    error CallerNotDefaultStrategy(address caller);

    /**
     * @notice Used when attempting to change strategy to same strategy.
     */
    error SameStrategy();

    /**
     * @notice Used when attempting to deposit when there are not active groups
     * to vote for.
     */
    error NoActiveGroups();

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
     * @dev Throws if called by any account other than DefaultStrategy.
     */
    modifier onlyDefaultStrategy() {
        if (address(defaultStrategy) != msg.sender) {
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
     * @param _groupHealth The address of the GroupHealth contract.
     * @param _specificGroupStrategy The address of the SpecificGroupStrategy contract.
     * @param _defaultStrategy The address of the Default strategy contract.
     */
    function setDependencies(
        address _stakedCelo,
        address _account,
        address _vote,
        address _groupHealth,
        address _specificGroupStrategy,
        address _defaultStrategy
    ) external onlyOwner {
        require(_stakedCelo != address(0), "StakedCelo null");
        require(_account != address(0), "Account null");
        require(_vote != address(0), "Vote null address");
        require(_groupHealth != address(0), "GroupHealth null");
        require(_specificGroupStrategy != address(0), "SpecificGroupStrategy null");
        require(_defaultStrategy != address(0), "DefaultStrategy null");

        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
        voteContract = _vote;
        groupHealth = IGroupHealth(_groupHealth);
        specificGroupStrategy = ISpecificGroupStrategy(_specificGroupStrategy);
        defaultStrategy = IDefaultStrategy(_defaultStrategy);
        emit VoteContractSet(_vote);
    }

    /**
     * @notice Marks a group as votable as part of the default strategy.
     * @param group The address of the group to add to the set of votable
     * groups.
     * @dev Fails if the maximum number of groups are already being voted for by
     * the Account smart contract (as per the `maxNumGroupsVotedFor` in the
     * Election contract).
     */
    function activateGroup(address group) external onlyOwner {
        defaultStrategy.activateGroup(group);

        if (!activeGroups.add(group)) {
            revert FailedToAddActiveGroup(group);
        }

        emit GroupActivated(group);
    }

    /**
     * @notice Returns deprecated.
     */
    function removeDeprecatedGroup(address group) external onlyDefaultStrategy returns (bool) {
        return deprecatedGroups.remove(group);
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
     * @notice Marks a group as allowed strategy for voting.
     * @param strategy The address of the group to add to the set of allowed
     * strategies.
     */
    function allowStrategy(address strategy) external onlyOwner {
        specificGroupStrategy.allowStrategy(strategy);
    }

    /**
     * @notice Marks a group as not allowed strategy for voting
     * and redistributes votes to default strategy.
     * @param strategy The address of the group to remove from the set of allowed
     * strategies.
     */
    function blockStrategy(address strategy) external onlyOwner {
        uint256 strategyTotalStCeloVotes = specificGroupStrategy.blockStrategy(strategy);

        if (strategyTotalStCeloVotes != 0) {
            _transferWithoutChecks(strategy, address(0), strategyTotalStCeloVotes);
        }
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
        if (
            activeGroups.length() +
                deprecatedGroups.length() +
                specificGroupStrategy.getSpecificGroupStrategiesLength() ==
            0
        ) {
            revert NoGroups();
        }

        distributeWithdrawals(stakedCeloAmount, msg.sender);
        stakedCelo.burn(msg.sender, stakedCeloAmount);
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
            if (!groupHealth.isValidGroup(strategy)) {
                // if invalid group vote for default strategy
                strategies[msg.sender] = address(0);
                strategy = address(0);
                uint256 stCeloBalance = stakedCelo.balanceOf(msg.sender);
                if (stCeloBalance != 0) {
                    _transfer(strategy, address(0), stCeloBalance, msg.sender, msg.sender);
                }
            } else {
                specificGroupStrategy.addToSpecificGroupStrategyTotalStCeloVotes(
                    strategy,
                    stCeloValue
                );
            }
        }

        stakedCelo.mint(msg.sender, stCeloValue);

        address[] memory finalGroups;
        uint256[] memory finalVotes;
        (finalGroups, finalVotes) = distributeVotes(msg.value, strategy);
        account.scheduleVotes{value: msg.value}(finalGroups, finalVotes);
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
     * @notice Returns the active group on index.
     * @return The active group.
     */
    function getGroup(uint256 index) external view returns (address) {
        return activeGroups.at(index);
    }

    /**
     * @notice Returns whether active groups contain group.
     * @return The group.
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
     * @notice Returns the deprecated group on index.
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
        return (1, 3, 0, 0);
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
            (!specificGroupStrategy.isSpecificGroupStrategy(newStrategy) ||
                !groupHealth.isValidGroup(newStrategy))
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
     * @notice Unlock vote balance of stCelo.
     * @param accountAddress The account to be unlocked.
     */
    function unlockBalance(address accountAddress) public {
        stakedCelo.unlockVoteBalance(accountAddress);
    }

    /**
     * @notice Rebalances Celo between groups that have incorrect Celo-stCelo ratio.
     * FromGroup is required to have more Celo than it should and ToGroup needs
     * to have less Celo than it should.
     * @param fromGroup The from group.
     * @param toGroup The to group.
     */
    function rebalance(address fromGroup, address toGroup) public {
        address[] memory fromGroups;
        address[] memory toGroups;
        uint256[] memory fromVotes;
        uint256[] memory toVotes;
        (fromGroups, toGroups, fromVotes, toVotes) = groupHealth.rebalance(fromGroup, toGroup);
        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
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
     * @notice Checks if strategy was depracated. Not allowed strategy is reverted to default.
     * @param strategy The strategy.
     * @return Up to date strategy
     */
    function _checkStrategy(address strategy) public view returns (address) {
        if (strategy != address(0) && !specificGroupStrategy.isSpecificGroupStrategy(strategy)) {
            // strategy not allowed revert to default strategy
            return address(0);
        }

        return strategy;
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
            (finalGroups, finalVotes) = defaultStrategy.generateGroupVotesToDistributeTo(votes);
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

        address[] memory groupsWithdrawn;
        uint256[] memory withdrawalsPerGroup;

        if (strategy != address(0)) {
            (groupsWithdrawn, withdrawalsPerGroup) = specificGroupStrategy
                .calculateAndUpdateForWithdrawal(strategy, withdrawal, stCeloAmount);
        } else {
            (groupsWithdrawn, withdrawalsPerGroup) = defaultStrategy
                .calculateAndUpdateForWithdrawal(withdrawal);
        }

        account.scheduleWithdrawals(beneficiary, groupsWithdrawn, withdrawalsPerGroup);
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

        if (
            account.getCeloForGroup(group) -
                toCelo(specificGroupStrategy.getTotalStCeloVotesForStrategy(group)) >
            0
        ) {
            if (!deprecatedGroups.add(group)) {
                revert FailedToAddDeprecatedGroup(group);
            }
        } else {
            emit GroupRemoved(group);
        }
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

        if (fromStrategy != address(0)) {
            specificGroupStrategy.subtractFromSpecificGroupStrategyTotalStCeloVotes(
                fromStrategy,
                stCeloAmount
            );
        }
        if (toStrategy != address(0)) {
            specificGroupStrategy.addToSpecificGroupStrategyTotalStCeloVotes(
                toStrategy,
                stCeloAmount
            );
        }

        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
    }
}
