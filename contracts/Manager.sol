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
     * @notice An instance of the DefaultStrategy contract for the StakedCelo protocol.
     */
    IDefaultStrategy public defaultStrategy;

    /**
     * @notice address -> strategy used by an address
     * strategy: address(0) = default strategy
     * strategy: !address(0) = vote for the group at that address if allowed
     * by GroupHealth.isGroupValid, otherwise vote according to the default strategy
     */
    mapping(address => address) public strategies;

    /**
     * @notice Emitted when the vote contract is initially set or later modified.
     * @param voteContract The new vote contract address.
     */
    event VoteContractSet(address indexed voteContract);

    /**
     * @notice Emitted when the voting strategy changes.
     * @param group The group's address.
     */
    event StrategyChanged(address indexed group);

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
     * @notice Used when rebalancing to non-active nor specific group.
     * @param group The group's address.
     */
    error InvalidToGroup(address group);

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
     * @notice Used when trying to overflow rebalance group that is not overflowing.
     * @param group The group's address.
     */
    error FromGroupNotOverflowing(address group);

    /**
     * @notice Used when trying to rebalance to a group that is overflowing.
     * @param group The group's address.
     */
    error ToGroupOverflowing(address group);

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
     * @dev Throws if called by any address other than one of the strategy contracts.
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
     * @param _registry The address of the Celo Registry.
     * @param _owner The address of the contract owner.
     */
    function initialize(address _registry, address _owner) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @dev The StakedCelo contracts all reference each other
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
     * @param stCeloAmount The amount of stCELO to burn.
     * @dev Calculates the CELO amount based on the ratio of outstanding stCELO
     * and the total amount of CELO owned and used for voting by Account. See
     * `toCelo`.
     * @dev The funds need to be withdrawn using calls to `Account.withdraw` and
     * `Account.finishPendingWithdrawal`.
     */
    function withdraw(uint256 stCeloAmount) external {
        (
            address[] memory groupsWithdrawn,
            uint256[] memory withdrawalsPerGroup
        ) = distributeWithdrawals(stCeloAmount, strategies[msg.sender], false);
        account.scheduleWithdrawals(msg.sender, groupsWithdrawn, withdrawalsPerGroup);

        stakedCelo.burn(msg.sender, stCeloAmount);
    }

    /**
     * @notice Revokes votes on already voted proposal.
     * @param proposalId The ID of the proposal to revoke from.
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
        uint256 stCeloAmount = toStakedCelo(msg.value);
        (address[] memory finalGroups, uint256[] memory finalVotes) = distributeVotes(
            msg.value,
            stCeloAmount,
            strategies[msg.sender]
        );

        stakedCelo.mint(msg.sender, stCeloAmount);
        account.scheduleVotes{value: msg.value}(finalGroups, finalVotes);
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
        address strategy = strategies[accountAddress];
        if (
            strategy != address(0) &&
            (specificGroupStrategy.isBlockedGroup(strategy) || !groupHealth.isGroupValid(strategy))
        ) {
            // strategy not allowed revert to default strategy
            return address(0);
        }

        return strategy;
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
        _transfer(strategies[from], strategies[to], stCeloAmount);
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
            (specificGroupStrategy.isBlockedGroup(newStrategy) ||
                !groupHealth.isGroupValid(newStrategy))
        ) {
            revert GroupNotEligible(newStrategy);
        }

        uint256 stCeloAmount = stakedCelo.balanceOf(msg.sender);
        if (stCeloAmount != 0) {
            _transfer(strategies[msg.sender], newStrategy, stCeloAmount);
        }

        strategies[msg.sender] = newStrategy;
        emit StrategyChanged(newStrategy);
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
     * `fromGroup` is required to have more CELO than it should and `toGroup` needs
     * to have less CELO than it should.
     * @param fromGroup The from group.
     * @param toGroup The to group.
     */
    function rebalance(address fromGroup, address toGroup) public {
        if (!defaultStrategy.isActive(toGroup) && specificGroupStrategy.isBlockedGroup(toGroup)) {
            // rebalancing to deactivated/non-existent group is not allowed
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

        uint256 receivableVotes = getReceivableVotesForGroup(toGroup);

        if (receivableVotes == 0) {
            revert ToGroupOverflowing(toGroup);
        }

        uint256 toMove = Math.min(
            Math.min(actualFromCelo - expectedFromCelo, expectedToCelo - actualToCelo),
            receivableVotes
        );

        scheduleRebalanceTransfer(fromGroup, toGroup, toMove);
    }

    /**
     * @notice Rebalance according to CELO overflow rather than stCELO ratio.
     * If one of the groups is overflowing and there are still some votes that
     * are scheduled for the group, this function allows to transfer these
     * votes to any active group in protocol that is not overflowing yet.
     * @param fromGroup The group to unschedule votes from.
     * @param toGroup The group to schedule votes to.
     */
    function rebalanceOverflow(address fromGroup, address toGroup) public {
        if (!defaultStrategy.isActive(toGroup)) {
            revert InvalidToGroup(toGroup);
        }

        uint256 fromReceivableVotesByElection = getElectionReceivableVotes(fromGroup);

        uint256 scheduledVotesToCancel = account.scheduledRevokeForGroup(fromGroup) +
            account.scheduledWithdrawalsForGroup(fromGroup);
        uint256 scheduledVotes = account.scheduledVotesForGroup(fromGroup);

        uint256 protocolScheduledVotes = scheduledVotes > scheduledVotesToCancel
            ? scheduledVotes - scheduledVotesToCancel
            : 0;

        uint256 overflowingCelo = protocolScheduledVotes > fromReceivableVotesByElection
            ? protocolScheduledVotes - fromReceivableVotesByElection
            : 0;

        if (overflowingCelo == 0) {
            revert FromGroupNotOverflowing(fromGroup);
        }

        uint256 toReceivableVotes = getReceivableVotesForGroup(toGroup);
        if (toReceivableVotes == 0) {
            revert ToGroupOverflowing(toGroup);
        }

        uint256 toMove = Math.min(overflowingCelo, toReceivableVotes);
        scheduleRebalanceTransfer(fromGroup, toGroup, toMove);
    }

    /**
     * @notice Allows strategy to initiate transfer without any checks.
     * This method is supposed to be used for transfers between groups
     * only within strategy
     * @param fromGroups The groups the deposited CELO is intended to be revoked from.
     * @param fromVotes The amount of CELO scheduled to be revoked from each respective group.
     * @param toGroups The groups the transferred CELO is intended to vote for.
     * @param toVotes The amount of CELO to schedule for each respective `toGroups`.
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
        actualCelo = account.getCeloForGroup(group);

        bool isSpecificGroupStrategy = !specificGroupStrategy.isBlockedGroup(group);
        bool isActiveGroup = defaultStrategy.isActive(group);

        uint256 stCeloFromSpecificStrategy;
        uint256 stCeloFromDefaultStrategy;

        if (isSpecificGroupStrategy) {
            uint256 overflow;
            uint256 unhealthy;
            (stCeloFromSpecificStrategy, overflow, unhealthy) = specificGroupStrategy
                .getStCeloInGroup(group);

            stCeloFromSpecificStrategy -= overflow + unhealthy;
        }

        if (isActiveGroup) {
            stCeloFromDefaultStrategy = defaultStrategy.stCeloInGroup(group);
        }

        expectedCelo = toCelo(stCeloFromSpecificStrategy + stCeloFromDefaultStrategy);
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
     * Returns votes count that can be received by group through stCELO protocol.
     * @param group The group that can receive votes.
     * @return The amount of CELO that can be received by group though stCELO protocol.
     */
    function getReceivableVotesForGroup(address group) public view returns (uint256) {
        uint256 receivableVotes = getElectionReceivableVotes(group);
        if (receivableVotes == 0) {
            return 0;
        }

        uint256 totalVotesForGroupByAccount = getElection().getTotalVotesForGroupByAccount(
            group,
            address(account)
        );
        uint256 votesForGroupByAccountInProtocol = account.getCeloForGroup(group);

        receivableVotes += totalVotesForGroupByAccount;

        if (receivableVotes < votesForGroupByAccountInProtocol) {
            return 0;
        }

        return receivableVotes - votesForGroupByAccountInProtocol;
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
            (finalGroups, finalVotes) = specificGroupStrategy.generateDepositVoteDistribution(
                strategy,
                votes,
                stCeloAmount
            );
        } else {
            (finalGroups, finalVotes) = defaultStrategy.generateDepositVoteDistribution(
                votes,
                address(0)
            );
        }

        return (finalGroups, finalVotes);
    }

    /**
     * @notice Distributes withdrawals according to chosen strategy.
     * @param stCeloAmount The amount of stCELO to be withdrawn.
     * @param strategy The strategy that will be used for withdrawal distribution.
     * @param isTransfer Whether or not withdrawal is calculated for transfer.
     **/
    function distributeWithdrawals(
        uint256 stCeloAmount,
        address strategy,
        bool isTransfer
    ) private returns (address[] memory, uint256[] memory) {
        uint256 celoAmount = toCelo(stCeloAmount);
        if (celoAmount == 0) {
            revert ZeroWithdrawal();
        }

        address[] memory groupsWithdrawn;
        uint256[] memory withdrawalsPerGroup;

        if (strategy != address(0)) {
            (groupsWithdrawn, withdrawalsPerGroup) = specificGroupStrategy
                .generateWithdrawalVoteDistribution(strategy, celoAmount, stCeloAmount, isTransfer);
        } else {
            (groupsWithdrawn, withdrawalsPerGroup) = defaultStrategy
                .generateWithdrawalVoteDistribution(celoAmount);
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
     * Returns votes count that can be received by group directly in Election contract.
     * @param group The group that can receive votes.
     */
    function getElectionReceivableVotes(address group) private view returns (uint256) {
        uint256 receivable = getElection().getNumVotesReceivable(group);
        uint256 totalVotes = getElection().getTotalVotesForGroup(group);

        if (receivable < totalVotes) {
            return 0;
        }

        return receivable - totalVotes;
    }
}
