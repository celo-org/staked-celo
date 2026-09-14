// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";
import "../helpers/deploy/FullTestManagerDeployHelper.sol";
import "../../contracts/mock/MockStakedCelo.sol";
import "../../contracts/mock/MockVote.sol";

/**
 * @title SpecificGroupStrategyTestBase
 * @notice Shared fixture for the Foundry port of test-ts/specific_group_strategy.test.ts.
 * @dev Mirrors the `before()` block of the TypeScript suite:
 *        - deploys the `FullTestManager` fixture (Manager, SpecificGroupStrategy,
 *          MockGroupHealth, MockDefaultStrategy) against the real Celo core registry of the
 *          devchain,
 *        - replaces StakedCelo / Account / Vote with MockStakedCelo / MockAccount / MockVote
 *          and re-wires every `setDependencies`,
 *        - registers 11 validator groups (groups[1] gets two validators so it has a higher
 *          voting limit) and elects them on MockGroupHealth,
 *        - hands the pauser role to the owner.
 *
 *      `setUp()` of the concrete test contracts runs this once per test, which is what the
 *      original achieved with `before()` plus `evm_snapshot` / `evm_revert` in
 *      `beforeEach` / `afterEach`. Nested `beforeEach` blocks of the original are ported as
 *      `_when...()` helpers that the tests of that block call first.
 */
abstract contract SpecificGroupStrategyTestBase is FullTestManagerDeployHelper, DevchainHelper {
    // =========================================================================
    //                       EVENTS (for vm.expectEmit)
    // =========================================================================

    event DependenciesSet(address account, address groupHealth, address defaultStrategy);
    event GroupBlocked(address group);
    event PauserSet(address pauser);
    event ContractPaused();
    event ContractUnpaused();
    event DepositVoteDistributionGenerated(
        address indexed group,
        address[] groups,
        uint256[] votes
    );
    event WithdrawalVoteDistributionGenerated(
        address indexed group,
        address[] groups,
        uint256[] votes
    );

    // =========================================================================
    //                               STRUCTS
    // =========================================================================

    /// @dev The four arrays returned by MockAccount.getLastTransferValues(), kept in one
    ///      stack slot so the tests compile without via_ir.
    struct TransferValues {
        address[] fromGroups;
        uint256[] fromVotes;
        address[] toGroups;
        uint256[] toVotes;
    }

    /// @dev The triple returned by SpecificGroupStrategy.getStCeloInGroup().
    struct GroupStCelo {
        uint256 total;
        uint256 overflow;
        uint256 unhealthy;
    }

    // =========================================================================
    //                            TEST FIXTURE
    // =========================================================================

    /// @dev The mocks the original `before()` deploys on top of the FullTestManager fixture.
    MockAccount internal mockAccount;
    MockStakedCelo internal mockStakedCelo;
    MockVote internal mockVote;

    address internal nonVote;
    address internal nonStakedCelo;
    address internal nonAccount;
    address internal nonManager;
    address internal nonOwner;
    address internal depositor;
    address internal voter;
    address internal someone;
    address internal pauser;

    /// @notice The 11 validator groups registered by the fixture.
    address[] internal groupAddresses;

    // =========================================================================
    //                      DIAMOND INHERITANCE RESOLUTION
    // =========================================================================
    //
    // CeloTestHelper is reached through both bases, so the epoch helpers have to be
    // resolved explicitly to the devchain (EpochManager based) implementations.

    function mineToNextEpoch() internal override(CeloTestHelper, DevchainHelper) {
        DevchainHelper.mineToNextEpoch();
    }

    function currentEpochNumber()
        internal
        view
        override(CeloTestHelper, DevchainHelper)
        returns (uint256)
    {
        return DevchainHelper.currentEpochNumber();
    }

    // =========================================================================
    //                                SETUP
    // =========================================================================

    function _setUpSpecificGroupStrategy() internal {
        loadDevchain();
        deployFullTestManager(REGISTRY_ADDRESS);
        _deployMocksAndSetDependencies();
        _createTestAccounts();
        _registerGroups();
        electMockValidatorGroupsAndUpdate(mockGroupHealth, groupAddresses);

        vm.prank(owner);
        specificGroupStrategy.setPauser();
    }

    /// @dev Deploys MockStakedCelo / MockVote / MockAccount and re-wires the protocol to them.
    function _deployMocksAndSetDependencies() private {
        vm.startPrank(owner);
        mockStakedCelo = new MockStakedCelo();
        mockVote = new MockVote();
        mockAccount = new MockAccount();

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

    function _createTestAccounts() private {
        pauser = owner;
        (nonOwner, ) = randomSigner(100 ether);
        (nonVote, ) = randomSigner(100_000 ether);
        (nonStakedCelo, ) = randomSigner(100 ether);
        (nonAccount, ) = randomSigner(100 ether);
        (nonManager, ) = randomSigner(100 ether);
        (voter, ) = randomSigner(10_000_000_000 ether);
        (someone, ) = randomSigner(100 ether);
        (depositor, ) = randomSigner(500 ether);

        createCeloAccount(voter);
        createCeloAccount(someone);
    }

    /// @dev Registers 11 groups; groups[1] has two members so its voting limit is higher.
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
    //                         FIXTURE SHORTHANDS
    // =========================================================================

    /// @dev Activates the first `count` groups in the DefaultStrategy, mirroring the
    ///      `for (let i = 0; i < count; i++)` loops of the original `beforeEach` blocks.
    function _activateGroups(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            (address head, ) = mockDefaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
    }

    /// @dev prepareOverflow over the fixture groups (activating the first three).
    function _prepareOverflow() internal {
        prepareOverflow(DefaultStrategy(address(mockDefaultStrategy)), voter, groupAddresses);
    }

    /// @dev updateGroupCeloBasedOnProtocolStCelo over the fixture contracts.
    function _updateGroupCelo() internal {
        updateGroupCeloBasedOnProtocolStCelo(
            mockDefaultStrategy,
            specificGroupStrategy,
            mockAccount,
            manager
        );
    }

    /// @dev The votes `group` can still receive from the Election contract.
    ///      Replaces the hardcoded ganache capacities of the original suite.
    function _receivableVotes(address group) internal view returns (uint256) {
        return
            celoElection.getNumVotesReceivable(group) -
            celoElection.getTotalVotesForGroup(group);
    }

    /// @dev Ports ElectionWrapper.revokePending: resolves index and neighbours, then revokes.
    function _revokePending(
        address voterAddress,
        address group,
        uint256 value
    ) internal {
        address[] memory votedFor = celoElection.getGroupsVotedForByAccount(voterAddress);
        uint256 index = type(uint256).max;
        for (uint256 i = 0; i < votedFor.length; i++) {
            if (votedFor[i] == group) {
                index = i;
                break;
            }
        }
        require(index != type(uint256).max, "voter did not vote for group");

        (address lesser, address greater) = findLesserAndGreaterAfterVote(group, -int256(value));
        vm.prank(voterAddress);
        celoElection.revokePending(group, value, lesser, greater, index);
    }

    function _lastTransferValues() internal view returns (TransferValues memory values) {
        (
            values.fromGroups,
            values.fromVotes,
            values.toGroups,
            values.toVotes
        ) = mockAccount.getLastTransferValues();
    }

    function _stCeloInGroup(address group) internal view returns (GroupStCelo memory amounts) {
        (amounts.total, amounts.overflow, amounts.unhealthy) = specificGroupStrategy
            .getStCeloInGroup(group);
    }

    // =========================================================================
    //                          ARRAY CONSTRUCTORS
    // =========================================================================

    function _addresses(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _addresses(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _uints(uint256 a) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = a;
    }

    // =========================================================================
    //                          ARRAY ASSERTIONS
    // =========================================================================

    /// @dev chai `to.deep.eq` on an address array: same length, same order.
    function _assertEqAddresses(address[] memory actual, address[] memory expected)
        internal
        pure
    {
        require(actual.length == expected.length, "address array length mismatch");
        for (uint256 i = 0; i < actual.length; i++) {
            require(actual[i] == expected[i], "address array mismatch");
        }
    }

    /// @dev chai `to.deep.eq` on a uint array: same length, same order.
    function _assertEqUints(uint256[] memory actual, uint256[] memory expected) internal pure {
        require(actual.length == expected.length, "uint array length mismatch");
        for (uint256 i = 0; i < actual.length; i++) {
            require(actual[i] == expected[i], "uint array mismatch");
        }
    }

    /// @dev chai `to.have.deep.members`: same length, same elements in any order.
    function _assertMembersAddresses(address[] memory actual, address[] memory expected)
        internal
        pure
    {
        require(actual.length == expected.length, "address members length mismatch");
        for (uint256 i = 0; i < expected.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < actual.length; j++) {
                if (actual[j] == expected[i]) {
                    found = true;
                    break;
                }
            }
            require(found, "address members mismatch");
        }
    }

    /// @dev chai `to.have.deep.members` for uint arrays.
    function _assertMembersUints(uint256[] memory actual, uint256[] memory expected)
        internal
        pure
    {
        require(actual.length == expected.length, "uint members length mismatch");
        for (uint256 i = 0; i < expected.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < actual.length; j++) {
                if (actual[j] == expected[i]) {
                    found = true;
                    break;
                }
            }
            require(found, "uint members mismatch");
        }
    }
}
