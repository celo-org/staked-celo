//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../libraries/ExternalCall.sol";
import "./UsingRegistryNoStorage.sol";

/**
 * @title Multisignature wallet - Allows multiple parties to agree on proposals before
 * execution.
 * @author Stefan George - <stefan.george@consensys.net>
 * @dev NOTE: This contract has its limitations and is not viable for every
 * multi-signature setup. On a case by case basis, evaluate whether this is the
 * correct contract for your use case.
 * In particular, this contract doesn't have an atomic "add owners and increase
 * requirement" operation.
 * This can be tricky, for example, in a situation where a MultiSig starts out
 * owned by a single owner. Safely increasing the owner set and requirement at
 * the same time is not trivial. One way to work around this situation is to
 * first add a second address controlled by the original owner, increase the
 * requirement, and then replace the auxillary address with the intended second
 * owner.
 * Again, this is just one example, in general make sure to verify this contract
 * will support your intended usage. The goal of this contract is to offer a
 * simple, minimal multi-signature API that's easy to understand even for novice
 * Solidity users.
 * Forked from
 * github.com/celo-org/celo-monorepo/blob/master/packages/protocol/contracts/common/MultiSig.sol
 */
contract MultiSig is Initializable, UUPSUpgradeable, UsingRegistryNoStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice The maximum number of multisig owners.
     */
    uint256 public constant MAX_OWNER_COUNT = 50;

    /**
     * @notice The minimum time in seconds that must elapse before a proposal is executable.
     */
    uint256 public immutable minDelay;

    /**
     * @notice The value used to mark a proposal as executed.
     */
    uint256 internal constant DONE_TIMESTAMP = uint256(1);

    /**
     * @notice Used to keep track of a proposal.
     * @param destinations The addresses at which the proposal is directed to.
     * @param values The amounts of CELO involved.
     * @param payloads The payloads of the proposal.
     * @param timestampExecutable The timestamp at which a proposal becomes executable.
     * @dev timestampExecutable is 0 if proposal is not yet scheduled or 1 if the proposal
     * is executed.
     * @param confirmations The list of confirmations. Keyed by the address that
     * confirmed the proposal, whether or not the proposal is confirmed.
     */
    struct Proposal {
        address[] destinations;
        uint256[] values;
        bytes[] payloads;
        uint256 timestampExecutable;
        mapping(address => bool) confirmations;
    }

    /**
     * @notice The delay that must elapse to be able to execute a proposal.
     */
    uint256 public delay;

    /**
     * @notice Keyed by proposal ID, the Proposal record.
     */
    mapping(uint256 => Proposal) public proposals;

    /**
     * @notice The set of addresses which are owners of the multisig.
     */
    EnumerableSet.AddressSet private owners;

    /**
     * @notice The amount of confirmations required
     * for a proposal to be fully confirmed.
     */
    uint256 public required;

    /**
     * @notice The total count of proposals.
     */
    uint256 public proposalCount;

    /**
     * @notice Used when a proposal is successfully confirmed.
     * @param sender The address of the sender.
     * @param proposalId The ID of the proposal.
     */
    event ProposalConfirmed(address indexed sender, uint256 indexed proposalId);

    /**
     * @notice Used when a confirmation is successfully revoked.
     * @param sender The address of the sender.
     * @param proposalId The ID of the proposal.
     */
    event ConfirmationRevoked(address indexed sender, uint256 indexed proposalId);

    /**
     * @notice Used when a proposal is successfully added.
     * @param proposalId The ID of the proposal that was added.
     */
    event ProposalAdded(uint256 indexed proposalId);

    /**
     * @notice Emitted when one of the transactions that make up a proposal is successfully
     * executed.
     * @param index The index of the transaction within the proposal.
     * @param proposalId The ID of the proposal.
     * @param returnData The response that was recieved from the external call.
     */
    event TransactionExecuted(uint256 index, uint256 indexed proposalId, bytes returnData);

    /**
     * @notice Emitted when one of the transactions that make up a Governance proposal is successfully
     * executed.
     * @param index The index of the transaction within the proposal.
     * @param returnData The response that was recieved from the external call.
     */
    event GovernanceTransactionExecuted(uint256 index, bytes returnData);

    /**
     * @notice Emitted when CELO is sent to this contract.
     * @param sender The account which sent the CELO.
     * @param value The amount of CELO sent.
     */
    event CeloDeposited(address indexed sender, uint256 value);

    /**
     * @notice Emitted when an Owner is successfully added as part of the multisig.
     * @param owner The added owner.
     */
    event OwnerAdded(address indexed owner);

    /**
     * @notice Emitted when an Owner is successfully removed from the multisig.
     * @param owner The removed owner.
     */
    event OwnerRemoved(address indexed owner);

    /**
     * @notice Emitted when the minimum amount of required confirmations is
     * successfully changed.
     * @param required The new required amount.
     */
    event RequirementChanged(uint256 required);

    /**
     * @notice Emitted when a proposal is scheduled.
     * @param proposalId The ID of the proposal that is scheduled.
     */
    event ProposalScheduled(uint256 indexed proposalId);

    /**
     * @notice Used when `delay` is changed.
     * @param delay The current delay value.
     * @param newDelay The new delay value.
     */
    event DelayChanged(uint256 delay, uint256 newDelay);

    /**
     * @notice Used when sender is not this contract in an `onlyWallet` function.
     * @param account The sender which triggered the function.
     */
    error SenderMustBeMultisigWallet(address account);

    /**
     * @notice Used when attempting to add an already existing owner.
     * @param owner The address of the owner.
     */
    error OwnerAlreadyExists(address owner);

    /**
     * @notice Used when an owner does not exist.
     * @param owner The address of the owner.
     */
    error OwnerDoesNotExist(address owner);

    /**
     * @notice Used when a proposal does not exist.
     * @param proposalId The ID of the non-existent proposal.
     */
    error ProposalDoesNotExist(uint256 proposalId);

    /**
     * @notice Used when a proposal is not confirmed by a given owner.
     * @param proposalId The ID of the proposal that is not confirmed.
     * @param owner The address of the owner which did not confirm the proposal.
     */
    error ProposalNotConfirmed(uint256 proposalId, address owner);

    /**
     * @notice Used when a proposal is not fully confirmed.
     * @dev A proposal is fully confirmed when the `required` threshold
     * of confirmations has been met.
     * @param proposalId The ID of the proposal that is not fully confirmed.
     */
    error ProposalNotFullyConfirmed(uint256 proposalId);

    /**
     * @notice Used when a proposal is already confirmed by an owner.
     * @param proposalId The ID of the proposal that is already confirmed.
     * @param owner The address of the owner which confirmed the proposal.
     */
    error ProposalAlreadyConfirmed(uint256 proposalId, address owner);

    /**
     * @notice Used when a proposal has been executed.
     * @param proposalId The ID of the proposal that is already executed.
     */
    error ProposalAlreadyExecuted(uint256 proposalId);

    /**
     * @notice Used when a passed address is address(0).
     */
    error NullAddress();

    /**
     * @notice Used when the set threshold values for owner and minimum
     * required confirmations are not met.
     * @param ownerCount The count of owners.
     * @param required The number of required confirmations.
     */
    error InvalidRequirement(uint256 ownerCount, uint256 required);

    /**
     * @notice Used when attempting to remove the last owner.
     * @param owner The last owner.
     */
    error CannotRemoveLastOwner(address owner);

    /**
     * @notice Used when attempting to schedule an already scheduled proposal.
     * @param proposalId The ID of the proposal which is already scheduled.
     */
    error ProposalAlreadyScheduled(uint256 proposalId);

    /**
     * @notice Used when a proposal is not scheduled.
     * @param proposalId The ID of the proposal which is not scheduled.
     */
    error ProposalNotScheduled(uint256 proposalId);

    /**
     * @notice Used when a time lock delay is not reached.
     * @param proposalId The ID of the proposal whose time lock has not been reached yet.
     */
    error ProposalTimelockNotReached(uint256 proposalId);

    /**
     * @notice Used when a provided value is less than the minimum time lock delay.
     * @param delay The insufficient delay.
     */
    error InsufficientDelay(uint256 delay);

    /**
     * @notice Used when the sizes of the provided arrays params do not match
     * when submitting a proposal.
     */
    error ParamLengthsMismatch();

    error SenderNotGovernance(address sender);

    /**
     * @notice Checks that only the multisig contract can execute a function.
     */
    modifier onlyWallet() {
        if (msg.sender != address(this)) {
            revert SenderMustBeMultisigWallet(msg.sender);
        }
        _;
    }

    /**
     * @notice Checks that an address is not a multisig owner.
     * @param owner The address to check.
     */
    modifier ownerDoesNotExist(address owner) {
        if (owners.contains(owner)) {
            revert OwnerAlreadyExists(owner);
        }
        _;
    }

    /**
     * @notice Checks that an address is a multisig owner.
     * @param owner The address to check.
     */
    modifier ownerExists(address owner) {
        if (!owners.contains(owner)) {
            revert OwnerDoesNotExist(owner);
        }
        _;
    }

    /**
     * @notice Checks that a proposal exists.
     * @param proposalId The proposal ID to check.
     */
    modifier proposalExists(uint256 proposalId) {
        if (proposals[proposalId].destinations.length == 0) {
            revert ProposalDoesNotExist(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that a proposal has been confirmed by a multisig owner.
     * @param proposalId The proposal ID to check.
     * @param owner The owner to check.
     */
    modifier confirmed(uint256 proposalId, address owner) {
        if (!proposals[proposalId].confirmations[owner]) {
            revert ProposalNotConfirmed(proposalId, owner);
        }
        _;
    }

    /**
     * @notice Checks that a proposal has not been confirmed by a multisig owner.
     * @param proposalId The proposal ID to check.
     * @param owner The owner to check.
     */
    modifier notConfirmed(uint256 proposalId, address owner) {
        if (proposals[proposalId].confirmations[owner]) {
            revert ProposalAlreadyConfirmed(proposalId, owner);
        }
        _;
    }

    /**
     * @notice Checks that a proposal has not been executed.
     * @dev A proposal can only be executed after it is fully confirmed.
     * @param proposalId The proposal ID to check.
     */
    modifier notExecuted(uint256 proposalId) {
        if (proposals[proposalId].timestampExecutable == DONE_TIMESTAMP) {
            revert ProposalAlreadyExecuted(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that an address is not address(0).
     * @param addr The address to check.
     */
    modifier notNull(address addr) {
        if (addr == address(0)) {
            revert NullAddress();
        }
        _;
    }

    /**
     * @notice Checks that each address in a batch of addresses are not address(0).
     * @param _addresses The addresses to check.
     */
    modifier notNullBatch(address[] memory _addresses) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            if (_addresses[i] == address(0)) {
                revert NullAddress();
            }
        }
        _;
    }

    /**
     * @notice Checks that the values passed for number of multisig owners and required
     * confirmation are valid in comparison with the configured thresholds.
     * @param ownerCount The owners count to check.
     * @param requiredConfirmations The minimum number of confirmations required to consider
     * a proposal as fully confirmed.
     */
    modifier validRequirement(uint256 ownerCount, uint256 requiredConfirmations) {
        if (
            ownerCount > MAX_OWNER_COUNT ||
            requiredConfirmations > ownerCount ||
            requiredConfirmations == 0 ||
            ownerCount == 0
        ) {
            revert InvalidRequirement(ownerCount, requiredConfirmations);
        }
        _;
    }

    /**
     * @notice Checks that a proposal is scheduled.
     * @param proposalId The ID of the proposal to check.
     */
    modifier scheduled(uint256 proposalId) {
        if (!isScheduled(proposalId)) {
            revert ProposalNotScheduled(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that a proposal is not scheduled.
     * @param proposalId The ID of the proposal to check.
     */
    modifier notScheduled(uint256 proposalId) {
        if (isScheduled(proposalId)) {
            revert ProposalAlreadyScheduled(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that a proposal's time lock has elapsed.
     * @param proposalId The ID of the proposal to check.
     */
    modifier timeLockReached(uint256 proposalId) {
        if (!isProposalTimelockReached(proposalId)) {
            revert ProposalTimelockNotReached(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that a proposal is fully confirmed.
     * @param proposalId The ID of the proposal to check.
     */
    modifier fullyConfirmed(uint256 proposalId) {
        if (!isFullyConfirmed(proposalId)) {
            revert ProposalNotFullyConfirmed(proposalId);
        }
        _;
    }

    /**
     * @notice Sets `initialized` to  true on implementation contracts.
     * @param _minDelay The minimum time in seconds that must elapse before a
     * proposal is executable.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor(uint256 _minDelay) initializer {
        minDelay = _minDelay;
    }

    receive() external payable {
        if (msg.value > 0) {
            emit CeloDeposited(msg.sender, msg.value);
        }
    }

    /**
     * @notice Bootstraps this contract with initial data.
     * @dev This plays the role of a typical contract constructor. Sets initial owners and
     * required number of confirmations. The initializer modifier ensures that this function
     * is ONLY callable once.
     * @param initialOwners The list of initial owners.
     * @param requiredConfirmations The number of required confirmations for a proposal
     * to be fully confirmed.
     * @param _delay The delay that must elapse to be able to execute a proposal.
     */
    function initialize(
        address[] calldata initialOwners,
        uint256 requiredConfirmations,
        uint256 _delay
    ) external initializer validRequirement(initialOwners.length, requiredConfirmations) {
        for (uint256 i = 0; i < initialOwners.length; i++) {
            if (owners.contains(initialOwners[i])) {
                revert OwnerAlreadyExists(initialOwners[i]);
            }

            if (initialOwners[i] == address(0)) {
                revert NullAddress();
            }

            owners.add(initialOwners[i]);
            emit OwnerAdded(initialOwners[i]);
        }
        _changeRequirement(requiredConfirmations);
        _changeDelay(_delay);
    }

    /**
     * @notice Adds a new multisig owner.
     * @dev This call can only be made by this contract.
     * @param owner The owner to add.
     */
    function addOwner(address owner)
        external
        onlyWallet
        ownerDoesNotExist(owner)
        notNull(owner)
        validRequirement(owners.length() + 1, required)
    {
        owners.add(owner);
        emit OwnerAdded(owner);
    }

    /**
     * @notice Removes an existing owner.
     * @dev This call can only be made by this contract.
     * @param owner The owner to remove.
     */
    function removeOwner(address owner) external onlyWallet ownerExists(owner) {
        if (owners.length() == 1) {
            revert CannotRemoveLastOwner(owner);
        }

        owners.remove(owner);

        if (required > owners.length()) {
            // Readjust the required amount, since the list of total owners has reduced.
            changeRequirement(owners.length());
        }
        emit OwnerRemoved(owner);
    }

    /**
     * @notice Replaces an existing owner with a new owner.
     * @dev This call can only be made by this contract.
     * @param owner The owner to be replaced.
     */
    function replaceOwner(address owner, address newOwner)
        external
        onlyWallet
        ownerExists(owner)
        notNull(newOwner)
        ownerDoesNotExist(newOwner)
    {
        owners.remove(owner);
        owners.add(newOwner);
        emit OwnerRemoved(owner);
        emit OwnerAdded(newOwner);
    }

    /**
     * @notice Void a confirmation for a previously confirmed proposal.
     * @param proposalId The ID of the proposal to be revoked.
     */
    function revokeConfirmation(uint256 proposalId)
        external
        ownerExists(msg.sender)
        confirmed(proposalId, msg.sender)
        notExecuted(proposalId)
    {
        proposals[proposalId].confirmations[msg.sender] = false;
        emit ConfirmationRevoked(msg.sender, proposalId);
    }

    /**
     * @notice Creates a proposal and triggers the first confirmation on behalf of the
     * proposal creator.
     * @param destinations The addresses at which the proposal is target at.
     * @param values The CELO values involved in the proposal if any.
     * @param payloads The payloads of the proposal.
     * @return proposalId Returns the ID of the proposal that gets generated.
     */
    function submitProposal(
        address[] calldata destinations,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) external returns (uint256 proposalId) {
        if (destinations.length != values.length) {
            revert ParamLengthsMismatch();
        }

        if (destinations.length != payloads.length) {
            revert ParamLengthsMismatch();
        }
        proposalId = addProposal(destinations, values, payloads);
        confirmProposal(proposalId);
    }

    /**
     * @notice Get the list of multisig owners.
     * @return The list of owner addresses.
     */
    function getOwners() external view returns (address[] memory) {
        return owners.values();
    }

    /**
     * @notice Gets the list of owners' addresses which have confirmed a given proposal.
     * @param proposalId The ID of the proposal.
     * @return The list of owner addresses.
     */
    function getConfirmations(uint256 proposalId) external view returns (address[] memory) {
        address[] memory confirmationsTemp = new address[](owners.length());
        uint256 count = 0;
        for (uint256 i = 0; i < owners.length(); i++) {
            if (proposals[proposalId].confirmations[owners.at(i)]) {
                confirmationsTemp[count] = owners.at(i);
                count++;
            }
        }
        address[] memory confirmingOwners = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            confirmingOwners[i] = confirmationsTemp[i];
        }
        return confirmingOwners;
    }

    /**
     * @notice Gets the destinations, values and payloads of a proposal.
     * @param proposalId The ID of the proposal.
     * @param destinations The addresses at which the proposal is target at.
     * @param values The CELO values involved in the proposal if any.
     * @param payloads The payloads of the proposal.
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.destinations, proposal.values, proposal.payloads);
    }

    /**
     * @notice Changes the number of confirmations required to consider a proposal
     * fully confirmed.
     * @dev Proposal has to be sent by wallet.
     * @param newRequired The new number of confirmations required.
     */
    function changeRequirement(uint256 newRequired)
        public
        onlyWallet
        validRequirement(owners.length(), newRequired)
    {
        _changeRequirement(newRequired);
    }

    /**
     * @notice Changes the value of the delay that must
     * elapse before a proposal can become executable.
     * @dev Proposal has to be sent by wallet.
     * @param newDelay The new delay value.
     */
    function changeDelay(uint256 newDelay) public onlyWallet {
        _changeDelay(newDelay);
    }

    /**
     * @notice Confirms a proposal. A proposal is executed if this confirmation
     * makes it fully confirmed.
     * @param proposalId The ID of the proposal to confirm.
     */
    function confirmProposal(uint256 proposalId)
        public
        ownerExists(msg.sender)
        proposalExists(proposalId)
        notConfirmed(proposalId, msg.sender)
    {
        proposals[proposalId].confirmations[msg.sender] = true;
        emit ProposalConfirmed(msg.sender, proposalId);
        if (isFullyConfirmed(proposalId)) {
            scheduleProposal(proposalId);
        }
    }

    /**
     * @notice Schedules a proposal with a time lock.
     * @param proposalId The ID of the proposal to confirm.
     */
    function scheduleProposal(uint256 proposalId)
        public
        ownerExists(msg.sender)
        notExecuted(proposalId)
    {
        schedule(proposalId);
        emit ProposalScheduled(proposalId);
    }

    /**
     * @notice Executes a proposal. A proposal is only executetable if it is fully confirmed,
     * scheduled and the set delay has elapsed.
     * @dev Any of the multisig owners can execute a given proposal, even though they may
     * not have participated in its confirmation process.
     */
    function executeProposal(uint256 proposalId)
        public
        scheduled(proposalId)
        notExecuted(proposalId)
        timeLockReached(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];
        proposal.timestampExecutable = DONE_TIMESTAMP;

        for (uint256 i = 0; i < proposals[proposalId].destinations.length; i++) {
            bytes memory returnData = ExternalCall.execute(
                proposal.destinations[i],
                proposal.values[i],
                proposal.payloads[i]
            );
            emit TransactionExecuted(i, proposalId, returnData);
        }
    }

    /**
     * @notice Executes a proposal made by Celo Governance.
     * @dev Only callable by the Celo Governance contract, as defined in the
     * Celo Registry. Thus, this function may be called via a Governance
     * referendum or hotfix.
     */
    function governanceProposeAndExecute(
        address[] calldata destinations,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) external {
        address governanceAddress = address(getGovernance());

        if (msg.sender != governanceAddress) {
            revert SenderNotGovernance(msg.sender);
        }

        for (uint256 i = 0; i < destinations.length; i++) {
            bytes memory returnData = ExternalCall.execute(destinations[i], values[i], payloads[i]);
            emit GovernanceTransactionExecuted(i, returnData);
        }
    }

    /**
     * @notice Returns the timestamp at which a proposal becomes executable.
     * @param proposalId The ID of the proposal.
     * @return The timestamp at which the proposal becomes executable.
     */
    function getTimestamp(uint256 proposalId) public view returns (uint256) {
        return proposals[proposalId].timestampExecutable;
    }

    /**
     * @notice Returns whether a proposal is scheduled.
     * @param proposalId The ID of the proposal to check.
     * @return Whether or not the proposal is scheduled.
     */
    function isScheduled(uint256 proposalId) public view returns (bool) {
        return getTimestamp(proposalId) > DONE_TIMESTAMP;
    }

    /**
     * @notice Returns whether a proposal is executable or not.
     * A proposal is executable if it is scheduled, the delay has elapsed
     * and it is not yet executed.
     * @param proposalId The ID of the proposal to check.
     * @return Whether or not the time lock is reached.
     */
    function isProposalTimelockReached(uint256 proposalId) public view returns (bool) {
        uint256 timestamp = getTimestamp(proposalId);
        return
            timestamp <= block.timestamp &&
            proposals[proposalId].timestampExecutable > DONE_TIMESTAMP;
    }

    /**
     * @notice Checks that a proposal has been confirmed by at least the `required`
     * number of owners.
     * @param proposalId The ID of the proposal to check.
     * @return Whether or not the proposal is confirmed by the minimum set of owners.
     */
    function isFullyConfirmed(uint256 proposalId) public view returns (bool) {
        uint256 count = 0;
        for (uint256 i = 0; i < owners.length(); i++) {
            if (proposals[proposalId].confirmations[owners.at(i)]) {
                count++;
            }
            if (count == required) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Checks that a proposal is confirmed by an owner.
     * @param proposalId The ID of the proposal to check.
     * @param owner The address to check.
     * @return Whether or not the proposal is confirmed by the given owner.
     */
    function isConfirmedBy(uint256 proposalId, address owner) public view returns (bool) {
        return proposals[proposalId].confirmations[owner];
    }

    /**
     * @notice Checks that an address is a multisig owner.
     * @param owner The address to check.
     * @return Whether or not the address is a multisig owner.
     */
    function isOwner(address owner) public view returns (bool) {
        return owners.contains(owner);
    }

    /**
     * @notice Adds a new proposal to the proposals list.
     * @param destinations The addresses at which the proposal is directed to.
     * @param values The CELO valuse involved in the proposal if any.
     * @param payloads The payloads of the proposal.
     * @return proposalId Returns the ID of the proposal that gets generated.
     */
    function addProposal(
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory payloads
    ) internal notNullBatch(destinations) returns (uint256 proposalId) {
        proposalId = proposalCount;
        Proposal storage proposal = proposals[proposalId];

        proposal.destinations = destinations;
        proposal.values = values;
        proposal.payloads = payloads;

        proposalCount++;
        emit ProposalAdded(proposalId);
    }

    /**
     * @notice Schedules a proposal with a time lock.
     * @param proposalId The ID of the proposal to schedule.
     */
    function schedule(uint256 proposalId)
        internal
        notScheduled(proposalId)
        fullyConfirmed(proposalId)
    {
        proposals[proposalId].timestampExecutable = block.timestamp + delay;
    }

    /**
     * @notice Changes the value of the delay that must
     * elapse before a proposal can become executable.
     * @param newDelay The new delay value.
     */
    function _changeDelay(uint256 newDelay) internal {
        if (newDelay < minDelay) {
            revert InsufficientDelay(newDelay);
        }

        delay = newDelay;
        emit DelayChanged(delay, newDelay);
    }

    /**
     * @notice Changes the number of confirmations required to consider a proposal
     * fully confirmed.
     * @dev This method does not do any validation, see `changeRequirement`
     * for how it is used with the requirement validation modifier.
     * @param newRequired The new number of confirmations required.
     */
    function _changeRequirement(uint256 newRequired) internal {
        required = newRequired;
        emit RequirementChanged(newRequired);
    }

    /**
     * @notice Guard method for UUPS (Universal Upgradable Proxy Standard)
     * See: https://docs.openzeppelin.com/contracts/4.x/api/proxy#transparent-vs-uups
     * @dev This methods overrides the virtual one in UUPSUpgradeable and
     * adds the onlyWallet modifer.
     */
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyWallet {}

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
        return (1, 1, 1, 0);
    }
}
