// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";
import "../helpers/deploy/FullTestManagerDeployHelper.sol";
import "../../contracts/mock/MockStakedCelo.sol";
import "../../contracts/mock/MockVote.sol";

/**
 * @dev `vm.toString(address)`, which CeloTestVm does not declare. Cast onto the same
 *      cheatcode address; used to render array assertion failures.
 */
interface ManagerTestVm {
    function toString(address value) external pure returns (string memory);
}

/**
 * @title ManagerTestBase
 * @notice Shared fixture of the ported `describe("Manager")` suite.
 * @dev Ports the `before()` block of test-ts/manager.test.ts. The Hardhat suite used
 *      `evm_snapshot` / `evm_revert` around every `it()`, which is what Foundry's per-test
 *      `setUp()` gives us for free.
 *
 *      Like the original, the FullTestManager fixture is deployed first and the Account,
 *      StakedCelo and Vote contracts are then replaced with MockAccount, MockStakedCelo and
 *      MockVote through `setDependencies`. The Celo core contracts are the real ones of the
 *      devchain, resolved through the registry at 0x...ce10.
 */
abstract contract ManagerTestBase is DevchainHelper, FullTestManagerDeployHelper {
    /// @dev `vm` widened with `toString(address)` (see ManagerTestVm).
    ManagerTestVm internal constant mvm =
        ManagerTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // =========================================================================
    //                       MANAGER EVENTS (vm.expectEmit)
    // =========================================================================

    event VoteContractSet(address indexed voteContract);
    event CeloDeposited(address indexed depositor, uint256 celoAmount, uint256 stCeloAmount);
    event CeloWithdrawn(address indexed withdrawer, uint256 stCeloAmount, uint256 celoAmount);
    event PauserSet(address pauser);
    event ContractPaused();
    event ContractUnpaused();

    // =========================================================================
    //                         FIXTURE CONTRACTS
    // =========================================================================

    /// @dev The `account` / `stakedCelo` / `voteContract` of the TypeScript suite.
    MockAccount internal mockAccount;
    MockStakedCelo internal mockStakedCelo;
    MockVote internal mockVote;

    // =========================================================================
    //                             ACCOUNTS
    // =========================================================================

    address internal nonOwner;
    address internal someone;
    address internal mockSlasher;
    address internal depositor;
    address internal depositor2;
    address internal voter;
    address internal nonVote;
    address internal nonStakedCelo;
    address internal nonAccount;
    address internal pauser;

    /// @dev The 11 validator groups registered by the fixture. Group 1 has two validators.
    address[] internal groupAddresses;

    // =========================================================================
    //                         OVERFLOW CAPACITIES
    // =========================================================================
    //
    // The TypeScript suite hardcoded the receivable votes left after prepareOverflow for the
    // ganache devchain (40.166666666666666666 / 99.25 / 200.166666666666666666 CELO). The
    // anvil devchain solves the vote amounts from the chain state instead, so the capacities
    // are read back from the Manager after prepareOverflow rather than hardcoded.

    uint256 internal firstGroupCapacity;
    uint256 internal secondGroupCapacity;
    uint256 internal thirdGroupCapacity;

    // =========================================================================
    //                                SETUP
    // =========================================================================

    /// @dev CeloTestHelper is reached through both bases, so the devchain epoch handling has
    ///      to be re-stated explicitly.
    function mineToNextEpoch() internal override(CeloTestHelper, DevchainHelper) {
        DevchainHelper.mineToNextEpoch();
    }

    /// @dev See `mineToNextEpoch`.
    function currentEpochNumber()
        internal
        view
        override(CeloTestHelper, DevchainHelper)
        returns (uint256)
    {
        return DevchainHelper.currentEpochNumber();
    }

    function setUp() public virtual {
        loadDevchain();
        deployFullTestManager(REGISTRY_ADDRESS);

        (nonOwner, ) = randomSigner(100 ether);
        (someone, ) = randomSigner(100 ether);
        (mockSlasher, ) = randomSigner(100 ether);
        (depositor, ) = randomSigner(500 ether);
        (depositor2, ) = randomSigner(500 ether);
        (voter, ) = randomSigner(10_000_000_000 ether);
        (nonVote, ) = randomSigner(100_000 ether);
        (nonStakedCelo, ) = randomSigner(100 ether);
        (nonAccount, ) = randomSigner(100 ether);
        pauser = owner;

        mockAccount = new MockAccount();
        mockStakedCelo = new MockStakedCelo();
        mockVote = new MockVote();

        _wireMocks();

        createCeloAccount(voter);
        createCeloAccount(someone);

        _registerGroups();

        electMockValidatorGroupsAndUpdate(mockGroupHealth, groupAddresses);

        vm.prank(owner);
        manager.setPauser();
    }

    /// @dev Replaces Account / StakedCelo / Vote of the fixture with their mocks.
    function _wireMocks() private {
        vm.startPrank(owner);
        manager.setDependencies(
            address(mockStakedCelo),
            address(mockAccount),
            address(mockVote),
            address(mockGroupHealth),
            address(specificGroupStrategy),
            address(mockDefaultStrategy)
        );
        specificGroupStrategy.setDependencies(
            address(mockAccount),
            address(mockGroupHealth),
            address(mockDefaultStrategy)
        );
        mockDefaultStrategy.setDependencies(
            address(mockAccount),
            address(mockGroupHealth),
            address(specificGroupStrategy)
        );
        vm.stopPrank();
    }

    /// @dev Registers 11 validator groups; group 1 gets a second validator so that it has a
    ///      higher voting limit.
    function _registerGroups() private {
        for (uint256 i = 0; i < 11; i++) {
            (address group, ) = randomSigner(21_000 ether);
            groupAddresses.push(group);
        }
        for (uint256 i = 0; i < 11; i++) {
            if (i == 1) {
                registerValidatorGroup(groupAddresses[i], 2);
                registerValidatorAndAddToGroupMembers(
                    groupAddresses[i],
                    createWallet(11_000 ether)
                );
            } else {
                registerValidatorGroup(groupAddresses[i], 1);
            }
            registerValidatorAndAddToGroupMembers(groupAddresses[i], createWallet(11_000 ether));
        }
    }

    // =========================================================================
    //                        FIXTURE SHORTHANDS
    // =========================================================================

    /// @notice `defaultStrategyContract` typed as the base contract for the shared helpers.
    function defaultStrategy() internal view returns (DefaultStrategy) {
        return DefaultStrategy(address(mockDefaultStrategy));
    }

    /// @notice Activates the first `count` groups, each inserted in front of the current head.
    function activateGroups(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            (address head, ) = mockDefaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
    }

    /// @notice `activateGroups` plus `account.setCeloForGroup(group, celoPerGroup)`.
    function activateGroupsWithCelo(uint256 count, uint256 celoPerGroup) internal {
        for (uint256 i = 0; i < count; i++) {
            (address head, ) = mockDefaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            mockAccount.setCeloForGroup(groupAddresses[i], celoPerGroup);
        }
    }

    /// @notice `activateGroups` with a per-group CELO amount.
    function activateGroupsWithCeloList(uint256[] memory celoPerGroup) internal {
        for (uint256 i = 0; i < celoPerGroup.length; i++) {
            (address head, ) = mockDefaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            mockAccount.setCeloForGroup(groupAddresses[i], celoPerGroup[i]);
        }
    }

    /// @notice Activates the first `count` groups and splits `celoPerGroup` between the votes
    ///         already cast and the votes still scheduled.
    function activateGroupsWithSplitCelo(uint256 count, uint256 celoPerGroup) internal {
        for (uint256 i = 0; i < count; i++) {
            (address head, ) = mockDefaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            mockAccount.setVotesForGroup(groupAddresses[i], celoPerGroup / 2);
            mockAccount.setScheduledVotes(groupAddresses[i], celoPerGroup / 2);
        }
    }

    /// @notice Runs prepareOverflow against the real Election and reads back the resulting
    ///         receivable votes of the first three groups.
    function prepareOverflowAndReadCapacities(bool activateGroups_) internal {
        prepareOverflow(defaultStrategy(), voter, groupAddresses, activateGroups_);
        firstGroupCapacity = electionReceivableVotes(groupAddresses[0]);
        secondGroupCapacity = electionReceivableVotes(groupAddresses[1]);
        thirdGroupCapacity = electionReceivableVotes(groupAddresses[2]);
    }

    /// @notice Votes `group` can still receive according to the Election contract.
    function electionReceivableVotes(address group) internal view returns (uint256) {
        return
            celoElection.getNumVotesReceivable(group) - celoElection.getTotalVotesForGroup(group);
    }

    /// @notice Ports `updateGroupCeloBasedOnProtocolStCelo(...)` with the fixture contracts.
    function updateGroupCelo() internal {
        updateGroupCeloBasedOnProtocolStCelo(
            mockDefaultStrategy,
            specificGroupStrategy,
            mockAccount,
            manager
        );
    }

    /// @notice Halves the slashing multiplier of `group` using `mockSlasher`.
    function slashGroup(address group) internal {
        updateGroupSlashingMultiplier(group, mockSlasher);
    }

    /// @notice Marks `group` as no longer elected on MockGroupHealth and updates its health.
    function revokeElection(address group) internal {
        address[] memory groups = new address[](1);
        groups[0] = group;
        revokeElectionOnMockValidatorGroupsAndUpdate(mockGroupHealth, groups, true);
    }

    /// @notice Re-runs `electMockValidatorGroupsAndUpdate` for a single group.
    function electAndUpdate(address group) internal {
        address[] memory groups = new address[](1);
        groups[0] = group;
        electMockValidatorGroupsAndUpdate(mockGroupHealth, groups);
    }

    // =========================================================================
    //                        ACCOUNT READ SHORTHANDS
    // =========================================================================

    function lastScheduledVotes()
        internal
        view
        returns (address[] memory groups, uint256[] memory votes)
    {
        return mockAccount.getLastScheduledVotes();
    }

    function lastScheduledWithdrawals()
        internal
        view
        returns (address[] memory groups, uint256[] memory withdrawals)
    {
        (groups, withdrawals, ) = mockAccount.getLastScheduledWithdrawals();
    }

    // =========================================================================
    //                          ARRAY BUILDERS
    // =========================================================================

    function arr(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    function arr(address a, address b) internal pure returns (address[] memory out) {
        out = new address[](2);
        out[0] = a;
        out[1] = b;
    }

    function arr(
        address a,
        address b,
        address c
    ) internal pure returns (address[] memory out) {
        out = new address[](3);
        out[0] = a;
        out[1] = b;
        out[2] = c;
    }

    function arr(
        address a,
        address b,
        address c,
        address d
    ) internal pure returns (address[] memory out) {
        out = new address[](4);
        out[0] = a;
        out[1] = b;
        out[2] = c;
        out[3] = d;
    }

    function arr(uint256 a) internal pure returns (uint256[] memory out) {
        out = new uint256[](1);
        out[0] = a;
    }

    function arr(uint256 a, uint256 b) internal pure returns (uint256[] memory out) {
        out = new uint256[](2);
        out[0] = a;
        out[1] = b;
    }

    function arr(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256[] memory out) {
        out = new uint256[](3);
        out[0] = a;
        out[1] = b;
        out[2] = c;
    }

    function arr(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) internal pure returns (uint256[] memory out) {
        out = new uint256[](4);
        out[0] = a;
        out[1] = b;
        out[2] = c;
        out[3] = d;
    }

    /// @notice The first `count` group addresses (ports `groupAddresses.slice(0, count)`).
    function groupSlice(uint256 count) internal view returns (address[] memory out) {
        out = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = groupAddresses[i];
        }
    }

    // =========================================================================
    //                         ARRAY ASSERTIONS
    // =========================================================================

    /// @dev "<prefix> length: <aLength> != <bLength>".
    function _lengthMessage(
        string memory prefix,
        uint256 aLength,
        uint256 bLength
    ) private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    prefix,
                    " length: ",
                    vm.toString(aLength),
                    " != ",
                    vm.toString(bLength)
                )
            );
    }

    /// @dev "<prefix> [<index>]: <a> != <b>".
    function _elementMessage(
        string memory prefix,
        uint256 index,
        string memory a,
        string memory b
    ) private pure returns (string memory) {
        return string(abi.encodePacked(prefix, " [", vm.toString(index), "]: ", a, " != ", b));
    }

    /// @notice `expect(a).to.deep.equal(b)` for address arrays (order matters).
    function assertEq(address[] memory a, address[] memory b) internal pure {
        if (a.length != b.length) {
            revert(_lengthMessage("Assertion failed: address array", a.length, b.length));
        }
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                revert(
                    _elementMessage(
                        "Assertion failed: address array element",
                        i,
                        mvm.toString(a[i]),
                        mvm.toString(b[i])
                    )
                );
            }
        }
    }

    /// @notice `expect(a).to.deep.equal(b)` for uint arrays (order matters).
    function assertEq(uint256[] memory a, uint256[] memory b) internal pure {
        if (a.length != b.length) {
            revert(_lengthMessage("Assertion failed: uint array", a.length, b.length));
        }
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                revert(
                    _elementMessage(
                        "Assertion failed: uint array element",
                        i,
                        vm.toString(a[i]),
                        vm.toString(b[i])
                    )
                );
            }
        }
    }

    /// @notice `expect(a).to.have.deep.members(b)` for address arrays (order agnostic).
    function assertMembers(address[] memory a, address[] memory b) internal pure {
        if (a.length != b.length) {
            revert(_lengthMessage("Assertion failed: address members", a.length, b.length));
        }
        bool[] memory used = new bool[](b.length);
        for (uint256 i = 0; i < a.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < b.length; j++) {
                if (!used[j] && a[i] == b[j]) {
                    used[j] = true;
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert(
                    string(
                        abi.encodePacked(
                            "Assertion failed: address members mismatch, a[",
                            vm.toString(i),
                            "] = ",
                            mvm.toString(a[i]),
                            " is not in b"
                        )
                    )
                );
            }
        }
    }

    /// @notice `expect(a).to.have.deep.members(b)` for uint arrays (order agnostic).
    function assertMembers(uint256[] memory a, uint256[] memory b) internal pure {
        if (a.length != b.length) {
            revert(_lengthMessage("Assertion failed: uint members", a.length, b.length));
        }
        bool[] memory used = new bool[](b.length);
        for (uint256 i = 0; i < a.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < b.length; j++) {
                if (!used[j] && a[i] == b[j]) {
                    used[j] = true;
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert(
                    string(
                        abi.encodePacked(
                            "Assertion failed: uint members mismatch, a[",
                            vm.toString(i),
                            "] = ",
                            vm.toString(a[i]),
                            " is not in b"
                        )
                    )
                );
            }
        }
    }

    /// @notice Asserts that no transfer was scheduled on the MockAccount.
    function assertNoTransferScheduled() internal view {
        (
            address[] memory fromGroups,
            uint256[] memory fromVotes,
            address[] memory toGroups,
            uint256[] memory toVotes
        ) = mockAccount.getLastTransferValues();
        assertEq(fromGroups.length, 0);
        assertEq(fromVotes.length, 0);
        assertEq(toGroups.length, 0);
        assertEq(toVotes.length, 0);
    }
}
