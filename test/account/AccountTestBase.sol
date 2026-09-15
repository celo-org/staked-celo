// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";
import "../helpers/deploy/TestAccountDeployHelper.sol";

/**
 * @dev Cheatcodes used by the Account suite that are not declared in CeloTestVm /
 *      DevchainVm. Cast onto the same cheatcode address.
 */
interface AccountTestVm {
    function snapshotState() external returns (uint256);

    function revertToState(uint256 snapshotId) external returns (bool);
}

/**
 * @dev The `expectEmit` overload that pins the expected event to a single emitter, mirroring
 *      the `.to.emit(contract, "Event")` assertion of the TypeScript suite. Cast onto the same
 *      cheatcode address.
 */
interface IVmExpectEmitFrom {
    function expectEmit(bool, bool, bool, bool, address) external;
}

/**
 * @title AccountTestBase
 * @notice Shared fixture for the port of legacy/test-ts/account.test.ts.
 * @dev Ports the `before()` hook of the TypeScript suite: three validator groups with one
 *      validator each are registered against the real Celo core contracts, the "TestAccount"
 *      Hardhat fixture (Manager + Account + MockGovernance) is deployed against the devchain
 *      registry and the Account gets an EOA manager and a pauser. `setUp()` runs before every
 *      test, which is what the `evm_snapshot` / `evm_revert` pair of the original did.
 *
 *      Deviation: the TypeScript suite hardcoded the `lesser` / `greater` neighbours passed to
 *      Election's `vote`, `revokePending` and `revokeActive`. On the ganache devchain the three
 *      test groups were the only ones holding votes, so `greater == address(0)` (i.e. "this
 *      group is the head of the list") was correct. The anvil devchain ships three validator
 *      groups that already hold 20 000 CELO of votes each, so those hardcoded neighbours make
 *      Celo's SortedLinkedList revert with "get lesser and greater failure". The helpers below
 *      therefore derive the neighbours from the chain state (the same way the original derived
 *      its hardcoded values), by replaying the Account bookkeeping that decides how much is
 *      voted / revoked from pending / revoked from active.
 */
abstract contract AccountTestBase is TestAccountDeployHelper, DevchainHelper {
    AccountTestVm internal constant avm =
        AccountTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // =========================================================================
    //                     EVENTS (for vm.expectEmit)
    // =========================================================================

    event VotesScheduled(address indexed group, uint256 amount);
    event CeloWithdrawalScheduled(
        address indexed beneficiary, address indexed group, uint256 withdrawalAmount
    );
    event CeloWithdrawalStarted(
        address indexed beneficiary, address indexed group, uint256 withdrawalAmount
    );
    event AllowedToVoteOverMaxNumberOfGroupsSet(bool flag);
    event VotedPartially(
        uint256 indexed proposalId, uint256 yesVotes, uint256 noVotes, uint256 abstainVotes
    );
    event PauserSet(address newPauser);
    event ContractPaused();
    event ContractUnpaused();

    /// @dev Expects the next emitted event to come from `emitter`, checking every topic and
    ///      the data. The emitter is what the TypeScript `.to.emit(contract, "Event")` pinned;
    ///      without it any contract emitting the same event would satisfy the assertion.
    function _expectEmitFrom(address emitter) internal {
        IVmExpectEmitFrom(address(vm)).expectEmit(true, true, true, true, emitter);
    }

    // =========================================================================
    //                            TEST STATE
    // =========================================================================

    /// @dev The EOA the Account contract accepts as its Manager (`manager` in the TS suite;
    ///      `manager` itself is the Manager contract of the deploy fixture).
    address internal managerSigner;
    address internal nonManager;
    address internal pauser;
    address internal beneficiary;
    address internal otherBeneficiary;
    address internal nonBeneficiary;

    address[] internal groupAddresses;
    address[] internal validatorAddresses;

    /// @dev Neighbours of a group in the eligible groups list for a revoke of pending votes
    ///      (`p`) and the subsequent revoke of active votes (`a`).
    struct RevokeNeighbours {
        address lesserAfterPending;
        address greaterAfterPending;
        address lesserAfterActive;
        address greaterAfterActive;
    }

    // =========================================================================
    //                              SETUP
    // =========================================================================

    function setUp() public virtual {
        loadDevchain();
        _initNamedAccounts();

        (managerSigner,) = randomSigner(100 ether);
        (nonManager,) = randomSigner(100 ether);
        (beneficiary,) = randomSigner(100 ether);
        (otherBeneficiary,) = randomSigner(100 ether);
        (nonBeneficiary,) = randomSigner(100 ether);

        for (uint256 i = 0; i < 3; i++) {
            groupAddresses.push(registerNewValidatorGroup());
        }

        deployTestAccount(REGISTRY_ADDRESS);

        vm.startPrank(owner);
        account.setManager(managerSigner);
        account.setPauser();
        vm.stopPrank();

        pauser = owner;
    }

    /// @dev Ambiguous because both CeloTestHelper and DevchainHelper define it.
    function mineToNextEpoch() internal virtual override(CeloTestHelper, DevchainHelper) {
        super.mineToNextEpoch();
    }

    /// @dev Ambiguous because both CeloTestHelper and DevchainHelper define it.
    function currentEpochNumber()
        internal
        view
        virtual
        override(CeloTestHelper, DevchainHelper)
        returns (uint256)
    {
        return super.currentEpochNumber();
    }

    /// @notice Registers a validator group with one validator, as the `before()` hook did.
    function registerNewValidatorGroup() internal returns (address group) {
        (group,) = randomSigner(11_000 ether);
        address validator = createWallet(11_000 ether);
        validatorAddresses.push(validator);
        registerValidatorGroup(group);
        registerValidatorAndAddToGroupMembers(group, validator);
    }

    // =========================================================================
    //                          ARRAY BUILDERS
    // =========================================================================

    function _addrs(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _addrs(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _addrs(address a, address b, address c) internal pure returns (address[] memory arr) {
        arr = new address[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _amounts(uint256 a) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = a;
    }

    function _amounts(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _amounts(uint256 a, uint256 b, uint256 c)
        internal
        pure
        returns (uint256[] memory arr)
    {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    /// @notice The three registered groups, in registration order.
    function _allGroups() internal view returns (address[] memory) {
        return _addrs(groupAddresses[0], groupAddresses[1], groupAddresses[2]);
    }

    // =========================================================================
    //                       MANAGER-ONLY CALLS
    // =========================================================================

    function _scheduleVotes(address[] memory groups, uint256[] memory votes, uint256 value)
        internal
    {
        vm.prank(managerSigner);
        account.scheduleVotes{value: value}(groups, votes);
    }

    /// @notice Schedules `amount` for a single group, sending exactly `amount`.
    function _scheduleVotes(address group, uint256 amount) internal {
        _scheduleVotes(_addrs(group), _amounts(amount), amount);
    }

    function _scheduleTransfer(
        address[] memory fromGroups,
        uint256[] memory fromVotes,
        address[] memory toGroups,
        uint256[] memory toVotes
    ) internal {
        vm.prank(managerSigner);
        account.scheduleTransfer(fromGroups, fromVotes, toGroups, toVotes);
    }

    function _scheduleTransfer(address fromGroup, address toGroup, uint256 amount) internal {
        _scheduleTransfer(_addrs(fromGroup), _amounts(amount), _addrs(toGroup), _amounts(amount));
    }

    function _scheduleWithdrawals(
        address forBeneficiary,
        address[] memory groups,
        uint256[] memory withdrawals
    ) internal {
        vm.prank(managerSigner);
        account.scheduleWithdrawals(forBeneficiary, groups, withdrawals);
    }

    function _scheduleWithdrawals(address forBeneficiary, address group, uint256 amount) internal {
        _scheduleWithdrawals(forBeneficiary, _addrs(group), _amounts(amount));
    }

    // =========================================================================
    //                     ACCOUNT BOOKKEEPING MIRRORS
    // =========================================================================

    /// @dev Mirrors `getAndUpdateToVoteAndToRevoke(group, 0, 0)`: the CELO still to be voted.
    function _celoToVote(address group) internal view returns (uint256) {
        uint256 toVote = account.scheduledVotesForGroup(group);
        uint256 toRevoke = account.scheduledRevokeForGroup(group);
        return toVote > toRevoke ? toVote - toRevoke : 0;
    }

    /// @dev Mirrors `getAndUpdateToVoteAndToRevoke(group, 0, 0)`: the CELO still to be revoked.
    function _celoToRevoke(address group) internal view returns (uint256) {
        uint256 toVote = account.scheduledVotesForGroup(group);
        uint256 toRevoke = account.scheduledRevokeForGroup(group);
        return toRevoke > toVote ? toRevoke - toVote : 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev The amount `activateAndVote` will cast as new votes for `group`.
    function _voteAmount(address group) internal view returns (uint256) {
        uint256 celoToVote = _celoToVote(group);
        uint256 nonvoting = celoLockedGold.getAccountNonvotingLockedGold(address(account));
        uint256 toLock = nonvoting >= celoToVote ? 0 : celoToVote - nonvoting;
        uint256 availableToLock = _min(address(account).balance, toLock);
        return celoToVote - (toLock - availableToLock);
    }

    /// @dev The neighbours Election needs for a revoke of `revokeAmount` from `group`.
    function _revokeNeighbours(address group, uint256 revokeAmount)
        internal
        view
        returns (RevokeNeighbours memory n)
    {
        uint256 pending = celoElection.getPendingVotesForGroupByAccount(group, address(account));
        uint256 fromPending = _min(revokeAmount, pending);
        (n.lesserAfterPending, n.greaterAfterPending) =
            findLesserAndGreaterAfterVote(group, -int256(fromPending));
        (n.lesserAfterActive, n.greaterAfterActive) =
            findLesserAndGreaterAfterVote(group, -int256(revokeAmount));
    }

    // =========================================================================
    //                       ACCOUNT ENTRY POINTS
    // =========================================================================

    /// @notice `account.activateAndVote(group, ...)` with neighbours derived from chain state.
    /// @dev The original called this through `.connect(manager)`, but `activateAndVote` is
    ///      permissionless (`onlyWhenNotPaused` only), so no prank is needed.
    function _activateAndVote(address group) internal {
        (address lesser, address greater) =
            findLesserAndGreaterAfterVote(group, int256(_voteAmount(group)));
        account.activateAndVote(group, lesser, greater);
    }

    /// @notice `account.revokeVotes(group, ...)` with neighbours derived from chain state.
    /// @dev The original called this through `.connect(manager)`, but `revokeVotes` is
    ///      permissionless (`onlyWhenNotPaused` only), so no prank is needed.
    function _revokeVotesForGroup(address group) internal {
        uint256 revokable = _min(account.votesForGroup(group), _celoToRevoke(group));
        RevokeNeighbours memory n = _revokeNeighbours(group, revokable);
        account.revokeVotes(
            group,
            n.lesserAfterPending,
            n.greaterAfterPending,
            n.lesserAfterActive,
            n.greaterAfterActive,
            0
        );
    }

    /// @dev The part of a withdrawal that `withdraw` pays out of the contract balance.
    function _immediateWithdrawalAmount(address forBeneficiary, address group)
        internal
        view
        returns (uint256)
    {
        uint256 withdrawalAmount =
            account.scheduledWithdrawalsForGroupAndBeneficiary(group, forBeneficiary);
        uint256 immediate = _min(address(account).balance, _celoToVote(group));
        return immediate > withdrawalAmount ? withdrawalAmount : immediate;
    }

    /// @notice `account.withdraw(...)` as the manager, neighbours derived from chain state.
    function _withdraw(address forBeneficiary, address group) internal {
        uint256 withdrawalAmount =
            account.scheduledWithdrawalsForGroupAndBeneficiary(group, forBeneficiary);
        RevokeNeighbours memory n = _revokeNeighbours(
            group, withdrawalAmount - _immediateWithdrawalAmount(forBeneficiary, group)
        );
        vm.prank(managerSigner);
        account.withdraw(
            forBeneficiary,
            group,
            n.lesserAfterPending,
            n.greaterAfterPending,
            n.lesserAfterActive,
            n.greaterAfterActive,
            0
        );
    }

    // =========================================================================
    //                        ASSERTION HELPERS
    // =========================================================================

    function _pendingVotes(address group) internal view returns (uint256) {
        return celoElection.getPendingVotesForGroupByAccount(group, address(account));
    }

    function _activeVotes(address group) internal view returns (uint256) {
        return celoElection.getActiveVotesForGroupByAccount(group, address(account));
    }

    function _totalVotes(address group) internal view returns (uint256) {
        return celoElection.getTotalVotesForGroupByAccount(group, address(account));
    }
}
