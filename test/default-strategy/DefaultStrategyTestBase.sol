// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/deploy/FullTestManagerDeployHelper.sol";
import "../helpers/DevchainHelper.sol";
import "../../contracts/mock/MockStakedCelo.sol";
import "../../contracts/mock/MockVote.sol";

/// @dev `expectEmit` overload that also checks the emitter. `CeloTestVm` only declares the
///      four-argument form.
interface IVmExpectEmitFrom {
    function expectEmit(
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData,
        address emitter
    ) external;
}

/**
 * @title DefaultStrategyTestBase
 * @notice Shared fixture for the ported `test-ts/default-strategy.test.ts` suite.
 * @dev Ports the `before()` block of the TypeScript suite. The Hardhat suite forked a ganache
 *      Celo devchain and used ContractKit against the real Election / LockedGold / Validators /
 *      Accounts contracts, so the fixture is built on top of `DevchainHelper`. The
 *      `FullTestManager` hardhat-deploy fixture is reproduced by
 *      `deployFullTestManager(REGISTRY_ADDRESS)`; the Account, StakedCelo and Vote contracts it
 *      deploys are then replaced by `MockAccount`, `MockStakedCelo` and `MockVote` exactly like
 *      the TypeScript `before()` does.
 *
 *      `beforeEach` + `evm_snapshot` / `evm_revert` of the original maps to Foundry's `setUp()`,
 *      which runs before every test. Nested `beforeEach` blocks become `_setUp...()` helpers that
 *      the tests of that block call first.
 *
 *      Deviation: the Hardhat `FullTestManager` fixture never called
 *      `SpecificGroupStrategy.setDependencies`, so its `account`, `groupHealth` and
 *      `defaultStrategy` stayed address(0) throughout the original default-strategy suite.
 *      `deployFullTestManager` wires them. Nothing in this suite reaches a SpecificGroupStrategy
 *      path that reads those dependencies, so the extra wiring is inert here.
 */
abstract contract DefaultStrategyTestBase is DevchainHelper, FullTestManagerDeployHelper {
    // =========================================================================
    //                  EVENTS (mirrored for vm.expectEmit)
    // =========================================================================

    event DependenciesSet(
        address indexed account,
        address indexed groupHealth,
        address indexed specificGroupStrategy
    );
    event SortingParamsSet(
        uint256 maxGroupsToDistributeTo,
        uint256 maxGroupsToWithdrawFrom,
        uint256 sortingLoopLimit
    );
    event MinCountOfActiveGroupsSet(uint256 minCount);
    event ActivatableGroupAdded(address indexed group);
    event GroupActivated(address indexed group);
    event GroupRemoved(address indexed group);
    event GroupStCeloUpdated(address indexed group, uint256 stCeloAmount, bool add);
    event Rebalanced(address indexed fromGroup, address indexed toGroup, uint256 stCeloAmount);
    event DepositVoteDistributionGenerated(address[] groups, uint256[] votes);
    event WithdrawalVoteDistributionGenerated(address[] groups, uint256[] votes);
    event PauserSet(address pauser);
    event ContractPaused();
    event ContractUnpaused();

    // =========================================================================
    //                              FIXTURE STATE
    // =========================================================================

    /// @dev The mocks that replace the deployed Account / StakedCelo / Vote contracts.
    MockAccount internal mockAccount;
    MockStakedCelo internal mockStakedCelo;
    MockVote internal mockVoteContract;

    /// @dev `mockDefaultStrategy` seen through the production interface.
    DefaultStrategy internal defaultStrategy;

    address internal nonOwner;
    address internal nonVote;
    address internal nonStakedCelo;
    address internal nonAccount;
    address internal nonManager;
    address internal voter;
    address internal someone;
    address internal mockSlasher;
    address internal pauser;

    /// @dev The 11 validator groups registered by the fixture.
    address[] internal groupAddresses;

    // =========================================================================
    //                       DIAMOND RESOLUTION
    // =========================================================================
    //
    // `FullTestManagerDeployHelper` and `DevchainHelper` both derive from `CeloTestHelper`, so
    // the epoch helpers have to be disambiguated explicitly. The devchain implementations win:
    // this suite runs against the real Celo core contracts.

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
    //                        EVENT ASSERTION HELPER
    // =========================================================================

    /// @dev `.to.emit(contract, name)` of the original: checks every topic, the event data and
    ///      the contract that emitted it.
    function _expectEmitFrom(address emitter) internal {
        IVmExpectEmitFrom(address(vm)).expectEmit(true, true, true, true, emitter);
    }

    // =========================================================================
    //                              FIXTURE
    // =========================================================================

    /// @notice Ports the `before()` block of `test-ts/default-strategy.test.ts`.
    function _deployDefaultStrategyFixture() internal {
        loadDevchain();
        deployFullTestManager(REGISTRY_ADDRESS);
        defaultStrategy = DefaultStrategy(address(mockDefaultStrategy));

        _createNamedTestAccounts();
        _deployProtocolMocks();
        _wireProtocolMocks();

        createCeloAccount(voter);
        createCeloAccount(someone);

        _registerValidatorGroups();
        electMockValidatorGroupsAndUpdate(mockGroupHealth, groupAddresses);

        vm.prank(owner);
        mockDefaultStrategy.setPauser();

        // The Hardhat suite deposited from the (well funded) deployer signer; here the test
        // contract itself is the depositor.
        vm.deal(address(this), 1_000_000 ether);
    }

    function _createNamedTestAccounts() private {
        (nonOwner, ) = randomSigner(100 ether);
        pauser = owner;
        (nonVote, ) = randomSigner(100_000 ether);
        (nonStakedCelo, ) = randomSigner(100 ether);
        (nonAccount, ) = randomSigner(100 ether);
        (nonManager, ) = randomSigner(100 ether);
        (voter, ) = randomSigner(10_000_000_000 ether);
        (someone, ) = randomSigner(100 ether);
        (mockSlasher, ) = randomSigner(100 ether);
    }

    function _deployProtocolMocks() private {
        vm.startPrank(owner);
        mockAccount = new MockAccount();
        mockStakedCelo = new MockStakedCelo();
        mockVoteContract = new MockVote();
        vm.stopPrank();
    }

    function _wireProtocolMocks() private {
        vm.startPrank(owner);
        manager.setDependencies(
            address(mockStakedCelo),
            address(mockAccount),
            address(mockVoteContract),
            address(mockGroupHealth),
            address(specificGroupStrategy),
            address(mockDefaultStrategy)
        );
        mockDefaultStrategy.setDependencies(
            address(mockAccount),
            address(mockGroupHealth),
            address(specificGroupStrategy)
        );
        vm.stopPrank();
    }

    /// @dev Registers 11 validator groups. Group 1 gets a second validator so that it has a
    ///      higher voting limit, matching the original fixture.
    function _registerValidatorGroups() private {
        for (uint256 i = 0; i < 11; i++) {
            (address group, ) = randomSigner(21_000 ether);
            groupAddresses.push(group);
        }
        for (uint256 i = 0; i < 11; i++) {
            if (i == 1) {
                registerValidatorGroup(groupAddresses[i], 2);
                registerValidatorAndAddToGroupMembers(groupAddresses[i], createWallet(11_000 ether));
            } else {
                registerValidatorGroup(groupAddresses[i], 1);
            }
            registerValidatorAndAddToGroupMembers(groupAddresses[i], createWallet(11_000 ether));
        }
    }

    // =========================================================================
    //                        ACTIVATION HELPERS
    // =========================================================================

    /// @dev Activates the first `count` groups, always passing the current head as `greater`.
    function _activateGroupsFromHead(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            (address head, ) = defaultStrategy.getGroupsHead();
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
    }

    /// @dev Activates the first `count` groups, passing the previously activated group as
    ///      `greater` (the `nextGroup` pattern of the original suite).
    function _activateGroupsFromPrevious(uint256 count) internal {
        address nextGroup = ADDRESS_ZERO;
        for (uint256 i = 0; i < count; i++) {
            vm.prank(owner);
            mockDefaultStrategy.addActivatableGroup(groupAddresses[i]);
            mockDefaultStrategy.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
            nextGroup = groupAddresses[i];
        }
    }

    /// @dev Shorthand for `updateGroupCeloBasedOnProtocolStCelo` with this fixture's contracts.
    function _updateGroupCelo() internal {
        updateGroupCeloBasedOnProtocolStCelo(
            mockDefaultStrategy,
            specificGroupStrategy,
            mockAccount,
            manager
        );
    }

    /// @dev Wraps a single address into a memory array.
    function _toArray(address addr) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = addr;
    }

    // =========================================================================
    //                        ASSERTION HELPERS
    // =========================================================================

    /// @dev `expect(a).to.deep.eq(b)` — same elements in the same order.
    function _assertArrayEq(address[] memory a, address[] memory b) internal pure {
        require(a.length == b.length, "array length mismatch");
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] == b[i], "array element mismatch");
        }
    }

    /// @dev `expect(a).to.have.deep.members(b)` — same elements, order insensitive.
    ///      A matched entry of `b` is consumed, so this compares multisets: a duplicate in `a`
    ///      cannot be satisfied twice by the same element of `b`.
    function _assertSameMembers(address[] memory a, address[] memory b) internal pure {
        if (a.length != b.length) {
            revert(
                string(
                    abi.encodePacked(
                        "members length mismatch: actual ",
                        vm.toString(a.length),
                        ", expected ",
                        vm.toString(b.length)
                    )
                )
            );
        }
        bool[] memory matched = new bool[](b.length);
        for (uint256 i = 0; i < a.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < b.length; j++) {
                if (!matched[j] && a[i] == b[j]) {
                    matched[j] = true;
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert(
                    string(
                        abi.encodePacked(
                            "members mismatch: actual[",
                            vm.toString(i),
                            "] = ",
                            vm.toString(a[i]),
                            " has no unmatched counterpart in the expected members"
                        )
                    )
                );
            }
        }
    }

    /// @dev `expect(arr).contain(value)`.
    function _assertContains(address[] memory arr, address value) internal pure {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                return;
            }
        }
        revert("array does not contain value");
    }

    /// @dev Asserts the active groups are ordered by non-decreasing stCELO (tail to head).
    function _assertCorrectOrder() internal view {
        OrderedGroup[] memory ordered = getOrderedActiveGroups(defaultStrategy);
        uint256 previous = 0;
        for (uint256 i = 0; i < ordered.length; i++) {
            require(previous <= ordered[i].stCelo, "active groups not ordered");
            previous = ordered[i].stCelo;
        }
    }

    /// @dev Ascending insertion sort by stCELO, mirroring the TypeScript comparator.
    function _sortByStCelo(OrderedGroup[] memory groups)
        internal
        pure
        returns (OrderedGroup[] memory)
    {
        for (uint256 i = 1; i < groups.length; i++) {
            OrderedGroup memory key = groups[i];
            uint256 j = i;
            while (j > 0 && groups[j - 1].stCelo > key.stCelo) {
                groups[j] = groups[j - 1];
                j--;
            }
            groups[j] = key;
        }
        return groups;
    }
}
