// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

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
     * @notice OBSOLETE
     */
    EnumerableSet.AddressSet private activeGroups;

    /**
     * @notice OBSOLETE
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
     * @notice address -> strategy used by an address
     * strategy: address(0) = default strategy
     * strategy: !address(0) = vote for the group at that address if allowed
     * by GroupHealth.isValidGroup, otherwise vote according to the default strategy
     */
    mapping(address => address) private strategies;

    /**
     * @notice Emitted when the vote contract is initially set or later modified.
     * @param voteContract The new vote contract address.
     */
    event VoteContractSet(address indexed voteContract);

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
     * @notice Used when attempting to pass in address zero where not allowed.
     */
    error AddressZeroNotAllowed();

    /**
     * @notice Used when an `onlyStCelo` function is called by a non-stCELO contract.
     * @param caller `msg.sender` that called the function.
     */
    error CallerNotStakedCelo(address caller);

    /**
     * @notice Used when an `onlyStrategy` function
     * is called by a non-strategy contract.
     * @param caller `msg.sender` that called the function.
     */
    error CallerNotStrategy(address caller);

    /**
     * @notice Used when rebalancing to not active nor specific group.
     * @param group The group's address.
     */
    error InvalidToGroup(address group);

    /**
     * @notice Used when rebalancing from address(0) group.
     * @param group The group's address.
     */
    error InvalidFromGroup(address group);

    /**
     * @notice Used when rebalancing and fromGroup doesn't have any extra CELO.
     * @param group The group's address.
     * @param actualCelo The actual CELO value.
     * @param expectedCelo The expected CELO value.
     */
    error RebalanceNoExtraCelo(address group, uint256 actualCelo, uint256 expectedCelo);

    /**
     * @notice Used when rebalancing and toGroup has enough CELO.
     * @param group The group's address.
     * @param actualCelo The actual CELO value.
     * @param expectedCelo The expected CELO value.
     */
    error RebalanceEnoughCelo(address group, uint256 actualCelo, uint256 expectedCelo);

    /**
     * @dev Throws if called by any address other than StakedCelo.
     */
    modifier onlyStakedCelo() {
        if (address(stakedCelo) != msg.sender) {
            revert CallerNotStakedCelo(msg.sender);
        }
        _;
    }

    /**
     * @dev Throws if called by any address other than strategy contracts.
     */
    modifier onlyStrategy() {
        if (
            address(defaultStrategy) != msg.sender && address(specificGroupStrategy) != msg.sender
        ) {
            revert CallerNotStrategy(msg.sender);
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
     * @param _defaultStrategy The address of the DefaultStrategy contract.
     */
    function setDependencies(
        address _stakedCelo,
        address _account,
        address _vote,
        address _groupHealth,
        address _specificGroupStrategy,
        address _defaultStrategy
    ) external onlyOwner {
        if (
            _stakedCelo == address(0) ||
            _account == address(0) ||
            _vote == address(0) ||
            _groupHealth == address(0) ||
            _specificGroupStrategy == address(0) ||
            _defaultStrategy == address(0)
        ) {
            revert AddressZeroNotAllowed();
        }

        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
        voteContract = _vote;
        groupHealth = IGroupHealth(_groupHealth);
        specificGroupStrategy = ISpecificGroupStrategy(_specificGroupStrategy);
        defaultStrategy = IDefaultStrategy(_defaultStrategy);
        emit VoteContractSet(_vote);
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
        distributeAndScheduleWithdrawals(stakedCeloAmount, msg.sender);
        stakedCelo.burn(msg.sender, stakedCeloAmount);
        console.log("withdraw end");
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
     * @notice Unlock balance of vote stCELO and update beneficiary vote history.
     * @param beneficiary The address to be unlocked.
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
     * The CELO will be distributed based on address strategy.
     */
    function deposit() external payable {
        console.log("Deposit start");
        address strategy = checkStrategy(strategies[msg.sender]);

        uint256 stCeloAmount = toStakedCelo(msg.value);
        if (strategy != address(0)) {
            if (!groupHealth.isValidGroup(strategy)) {
                // if invalid group vote for default strategy
                strategies[msg.sender] = address(0);
                strategy = address(0);
                uint256 stCeloBalance = stakedCelo.balanceOf(msg.sender);
                if (stCeloBalance != 0) {
                    _transfer(strategy, address(0), stCeloBalance);
                }
            }
        }

        address[] memory finalGroups;
        uint256[] memory finalVotes;
        (finalGroups, finalVotes) = distributeVotes(msg.value, stCeloAmount, strategy);

        stakedCelo.mint(msg.sender, stCeloAmount);

        account.scheduleVotes{value: msg.value}(finalGroups, finalVotes);
        console.log("deposit end");
    }

    /**
     * @notice Returns which strategy an address is using
     * address(0) = default strategy
     * !address(0) = voting for specific validator group.
     * Unhealthy and blocked strategies are reverted to default.
     * @param accountAddress The account address.
     * @return The strategy.
     */
    function getAddressStrategy(address accountAddress) external view returns (address) {
        return checkStrategy(strategies[accountAddress]);
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
     * @param stCeloAmount The stCELO amount.
     */
    function transfer(
        address from,
        address to,
        uint256 stCeloAmount
    ) public onlyStakedCelo {
        address fromStrategy = strategies[from];
        address toStrategy = strategies[to];
        _transfer(fromStrategy, toStrategy, stCeloAmount);
    }

    /**
     * @notice Schedules transfer of CELO between strategies.
     * @param fromStrategy The from strategy.
     * @param toStrategy The to strategy.
     * @param stCeloAmount The stCELO amount.
     */
    function transferBetweenStrategies(
        address fromStrategy,
        address toStrategy,
        uint256 stCeloAmount
    ) public onlyStrategy {
        _transferWithoutChecks(fromStrategy, toStrategy, stCeloAmount);
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
            _transfer(currentStrategy, newStrategy, stCeloAmount);
        }

        strategies[msg.sender] = checkStrategy(newStrategy);
    }

    /**
     * @notice Unlock vote balance of stCELO.
     * @param accountAddress The account to be unlocked.
     */
    function unlockBalance(address accountAddress) public {
        stakedCelo.unlockVoteBalance(accountAddress);
    }

    /**
     * @notice Rebalances CELO between groups that have incorrect CELO-stCELO ratio.
     * FromGroup is required to have more CELO than it should and ToGroup needs
     * to have less CELO than it should.
     * @param fromGroup The from group.
     * @param toGroup The to group.
     */
    function rebalance(address fromGroup, address toGroup) public {
        if (
            !defaultStrategy.groupsContain(toGroup) &&
            !specificGroupStrategy.isSpecificGroupStrategy(toGroup)
        ) {
            // rebalancing to deprecated/non-existent group is not allowed
            revert InvalidToGroup(toGroup);
        }

        (uint256 expectedFromCelo, uint256 actualFromCelo) = getExpectedAndActualCeloForGroup(
            fromGroup
        );
        if (actualFromCelo <= expectedFromCelo) {
            // fromGroup needs to have more CELO than it should
            revert RebalanceNoExtraCelo(fromGroup, actualFromCelo, expectedFromCelo);
        }

        (uint256 expectedToCelo, uint256 actualToCelo) = getExpectedAndActualCeloForGroup(toGroup);

        if (actualToCelo >= expectedToCelo) {
            // toGroup needs to have less CELO than it should
            revert RebalanceEnoughCelo(toGroup, actualToCelo, expectedToCelo);
        }

        scheduleRebalanceTransfer(
            fromGroup,
            toGroup,
            Math.min(actualFromCelo - expectedFromCelo, expectedToCelo - actualToCelo)
        );
    }

    /**
     * @notice Allows strategy to initiate transfer without any checks.
     * This method is supopsed to be used for transfers between groups
     * only within strategy
     * @param fromGroups The groups the deposited CELO is intended to be revoked from.
     * @param fromVotes The amount of CELO scheduled to be revoked from each respective group.
     * @param toGroups The groups the transferred CELO is intended to vote for.
     * @param toVotes The amount of CELO to schedule for each respective group
     * from `toGroups`.
     */
    function scheduleTransferWithinStrategy(
        address[] calldata fromGroups,
        address[] calldata toGroups,
        uint256[] calldata fromVotes,
        uint256[] calldata toVotes
    ) public onlyStrategy {
        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
    }

    /**
     * @notice Schedules transfer between 2 groups.
     * @param fromGroup The group the deposited CELO is intended to be revoked from.
     * @param toGroup The group the transferred CELO is intended to vote for.
     * @param votes The amount of CELO to be transfered.
     */
    function scheduleRebalanceTransfer(
        address fromGroup,
        address toGroup,
        uint256 votes
    ) private {
        address[] memory fromGroups = new address[](1);
        address[] memory toGroups = new address[](1);
        uint256[] memory fromVotes = new uint256[](1);
        uint256[] memory toVotes = new uint256[](1);

        fromGroups[0] = fromGroup;
        fromVotes[0] = votes;
        toGroups[0] = toGroup;
        toVotes[0] = fromVotes[0];
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
     * @notice Returns expected CELO amount voted for by Account contract
     * vs actual amount voted for by Account contract.
     * @param group The group.
     * @return expectedCelo The CELO which group should have.
     * @return actualCelo The CELO which group has.
     */
    function getExpectedAndActualCeloForGroup(address group)
        public
        view
        returns (uint256 expectedCelo, uint256 actualCelo)
    {
        bool isSpecificGroupStrategy = specificGroupStrategy.isSpecificGroupStrategy(group);
        bool isActiveGroup = defaultStrategy.groupsContain(group);
        actualCelo = account.getCeloForGroup(group);

        uint256 stCELOFromSpecificStrategy;
        uint256 stCELOFromDefaultStrategy;

        if (isSpecificGroupStrategy) {
            stCELOFromSpecificStrategy = specificGroupStrategy.getTotalStCeloVotesForStrategy(
                group
            );
        }

        if (isActiveGroup) {
            stCELOFromDefaultStrategy = defaultStrategy.stCELOInGroup(group);
        }

        expectedCelo = toCelo(stCELOFromSpecificStrategy + stCELOFromDefaultStrategy);
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
        console.log("stCeloSupply %s celoBalance %s", stCeloSupply, celoBalance);

        if (stCeloSupply == 0 || celoBalance == 0) {
            return stCeloAmount;
        }

        return (stCeloAmount * celoBalance) / stCeloSupply;
    }

    /**
     * @notice Checks if strategy is valid. Blocked strategy is reverted to default.
     * @param strategy The strategy.
     * @return Up to date strategy.
     */
    function checkStrategy(address strategy) public view returns (address) {
        if (strategy != address(0) && !specificGroupStrategy.isValidSpecificGroupStrategy(strategy)) {
            // strategy not allowed revert to default strategy
            return address(0);
        }

        return strategy;
    }

    /**
     * @notice Distributes votes according to chosen strategy.
     * @param votes The amount of votes to distribute.
     * @param stCeloAmount The amount of stCELO that was minted.
     * @param strategy The chosen strategy.
     */
    function distributeVotes(
        uint256 votes,
        uint256 stCeloAmount,
        address strategy
    ) private returns (address[] memory finalGroups, uint256[] memory finalVotes) {
        if (strategy != address(0)) {
            (finalGroups, finalVotes) = specificGroupStrategy.generateGroupVotesToDistributeTo(
                strategy,
                votes,
                stCeloAmount
            );
        } else {
            (finalGroups, finalVotes) = defaultStrategy.generateVoteDistribution(votes, false);
        }

        return (finalGroups, finalVotes);
    }

    /**
     * @notice Distributes withdrawals according to chosen strategy and schedules them.
     * @param stCeloAmount The amount of stCELO to be withdrawn.
     * @param beneficiary The address that should end up receiving the withdrawn
     * CELO.
     **/
    function distributeAndScheduleWithdrawals(uint256 stCeloAmount, address beneficiary) private {
        address strategy = checkStrategy(strategies[beneficiary]);
        (
            address[] memory groupsWithdrawn,
            uint256[] memory withdrawalsPerGroup
        ) = distributeWithdrawals(stCeloAmount, strategy, false);
        account.scheduleWithdrawals(beneficiary, groupsWithdrawn, withdrawalsPerGroup);
    }

    /**
     * @notice Distributes withdrawals according to chosen strategy.
     * @param stCeloAmount The amount of stCELO to be withdrawn.
     * @param strategy The strategy that will be used for withdrawal distribution
     * @param isTransfer Whether or not withdrawal is calculate for transfer
     * CELO.
     **/
    function distributeWithdrawals(
        uint256 stCeloAmount,
        address strategy,
        bool isTransfer
    ) private returns (address[] memory, uint256[] memory) {
        uint256 withdrawal = toCelo(stCeloAmount);
        console.log("withdrawal amount in stCelo %s  and Celo %s", stCeloAmount, withdrawal);
        if (withdrawal == 0) {
            revert ZeroWithdrawal();
        }

        address[] memory groupsWithdrawn;
        uint256[] memory withdrawalsPerGroup;

        if (strategy != address(0)) {
            (groupsWithdrawn, withdrawalsPerGroup) = isTransfer
                ? specificGroupStrategy.calculateAndUpdateForWithdrawalTransfer(
                    strategy,
                    withdrawal,
                    stCeloAmount
                )
                : specificGroupStrategy.calculateAndUpdateForWithdrawal(
                    strategy,
                    withdrawal,
                    stCeloAmount
                );
        } else {
            (groupsWithdrawn, withdrawalsPerGroup) = defaultStrategy.generateVoteDistribution(
                withdrawal,
                true
            );
        }

        return (groupsWithdrawn, withdrawalsPerGroup);
    }

    /**
     * @notice Schedules transfer of CELO between strategies.
     * @param fromStrategy The from validator group.
     * @param toStrategy The to validator group.
     * @param stCeloAmount The stCELO amount.
     */
    function _transfer(
        address fromStrategy,
        address toStrategy,
        uint256 stCeloAmount
    ) private {
        fromStrategy = checkStrategy(fromStrategy);
        toStrategy = checkStrategy(toStrategy);

        if (fromStrategy == toStrategy) {
            // either both addresses use default strategy
            // or both addresses use same specific strategy
            return;
        }

        _transferWithoutChecks(fromStrategy, toStrategy, stCeloAmount);
    }

    /**
     * @notice Schedules transfer of CELO between strategies.
     * @param fromStrategy The from validator group.
     * @param toStrategy The to validator group.
     * @param stCeloAmount The stCELO amount.
     */
    function _transferWithoutChecks(
        address fromStrategy,
        address toStrategy,
        uint256 stCeloAmount
    ) private {
        address[] memory fromGroups;
        uint256[] memory fromVotes;
        (fromGroups, fromVotes) = distributeWithdrawals(stCeloAmount, fromStrategy, true);

        address[] memory toGroups;
        uint256[] memory toVotes;
        (toGroups, toVotes) = distributeVotes(toCelo(stCeloAmount), stCeloAmount, toStrategy);

        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
    }
}
