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
        require(_stakedCelo != address(0), "StakedCelo null");
        require(_account != address(0), "Account null");
        require(_vote != address(0), "Vote null");
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
        address strategy = checkAndUpdateStrategy(msg.sender, strategies[msg.sender]);

        uint256 stCeloAmount = toStakedCelo(msg.value);
        if (strategy != address(0)) {
            if (!groupHealth.isValidGroup(strategy)) {
                // if invalid group vote for default strategy
                strategies[msg.sender] = address(0);
                strategy = address(0);
                uint256 stCeloBalance = stakedCelo.balanceOf(msg.sender);
                if (stCeloBalance != 0) {
                    _transfer(strategy, address(0), stCeloBalance, msg.sender, msg.sender);
                }
            }
        }

        stakedCelo.mint(msg.sender, stCeloAmount);

        address[] memory finalGroups;
        uint256[] memory finalVotes;
        (finalGroups, finalVotes) = distributeVotes(msg.value, stCeloAmount, strategy, true);
        account.scheduleVotes{value: msg.value}(finalGroups, finalVotes);
    }

    /**
     * @notice Returns which strategy an address is using
     * address(0) = default strategy
     * !address(0) = voting for allowed validator group
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
        _transfer(fromStrategy, toStrategy, stCeloAmount, from, to);
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
            _transfer(currentStrategy, newStrategy, stCeloAmount, msg.sender, msg.sender);
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
     * @notice Checks if strategy is valid. Blocked strategy is reverted to default.
     * @param strategy The strategy.
     * @return Up to date strategy.
     */
    function checkStrategy(address strategy) public view returns (address) {
        if (strategy != address(0) && !specificGroupStrategy.isSpecificGroupStrategy(strategy)) {
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
     * @param add Whether funds are being added or removed.
     */
    function distributeVotes(
        uint256 votes,
        uint256 stCeloAmount,
        address strategy,
        bool add
    ) private returns (address[] memory finalGroups, uint256[] memory finalVotes) {
        if (strategy != address(0)) {
            (finalGroups, finalVotes) = specificGroupStrategy.generateGroupVotesToDistributeTo(
                strategy,
                votes,
                stCeloAmount,
                add
            );
        } else {
            (finalGroups, finalVotes) = defaultStrategy.generateGroupVotesToDistributeTo(
                votes,
                stCeloAmount,
                add
            );
        }

        return (finalGroups, finalVotes);
    }

    /**
     * @notice Distributes withdrawals according to chosen strategy.
     * @param stCeloAmount The amount of stCELO to be withdrawn.
     * @param beneficiary The address that should end up receiving the withdrawn
     * CELO.
     **/
    function distributeWithdrawals(uint256 stCeloAmount, address beneficiary) private {
        uint256 withdrawal = toCelo(stCeloAmount);
        if (withdrawal == 0) {
            revert ZeroWithdrawal();
        }

        address strategy = checkAndUpdateStrategy(beneficiary, strategies[beneficiary]);

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
     * @notice Checks if strategy was deprecated. Deprecated strategy is reverted to default.
     * Updates the strategies.
     * @param accountAddress The account.
     * @param strategy The strategy.
     * @return Up to date strategy
     */
    function checkAndUpdateStrategy(address accountAddress, address strategy)
        private
        returns (address)
    {
        address checkedStrategy = checkStrategy(strategy);
        if (checkedStrategy != strategy) {
            strategies[accountAddress] = checkedStrategy;
        }
        return checkedStrategy;
    }

    /**
     * @notice Schedules transfer of CELO between strategies.
     * @param fromStrategy The from validator group.
     * @param toStrategy The to validator group.
     * @param stCeloAmount The stCELO amount.
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
        fromStrategy = checkAndUpdateStrategy(from, fromStrategy);
        toStrategy = checkAndUpdateStrategy(to, toStrategy);

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
        (fromGroups, fromVotes) = distributeVotes(
            toCelo(stCeloAmount),
            stCeloAmount,
            fromStrategy,
            false
        );

        address[] memory toGroups;
        uint256[] memory toVotes;
        (toGroups, toVotes) = distributeVotes(toCelo(stCeloAmount), stCeloAmount, toStrategy, true);

        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
    }
}
