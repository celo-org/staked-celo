// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

// ---- Celo core interfaces ----
import "../../contracts/interfaces/IRegistry.sol";
import "../../contracts/interfaces/IElection.sol";
import "../../contracts/interfaces/IAccounts.sol";
import "../../contracts/interfaces/ILockedGold.sol";
import "../../contracts/interfaces/IValidators.sol";
import "../../contracts/interfaces/IGovernance.sol";
import "../../contracts/interfaces/IGoldToken.sol";

// ---- Mock contracts ----
// NOTE: MockRegistry is NOT imported directly to avoid Initializable name collision
//       between @openzeppelin/contracts (used by MockRegistry/Ownable) and
//       @openzeppelin/contracts-upgradeable (used by project contracts).
//       Use IRegistry to interact with MockRegistry instances.
import "../../contracts/mock/MockElection.sol";
import "../../contracts/mock/MockLockedGold.sol";
import "../../contracts/mock/MockValidators.sol";
import "../../contracts/mock/MockGovernance.sol";
import "../../contracts/mock/MockAccount.sol";
import "../../contracts/mock/MockDefaultStrategy.sol";
import "../../contracts/mock/MockGroupHealth.sol";

// ---- Project contracts ----
import "../../contracts/DefaultStrategy.sol";
import "../../contracts/SpecificGroupStrategy.sol";
import "../../contracts/Manager.sol";
import "../../contracts/Account.sol";

/**
 * @dev Foundry VM cheatcode interface.
 *      Defined locally because forge-std/Test.sol requires pragma >=0.8.13
 *      while the project is locked to 0.8.11.
 *      Contains only the cheatcodes needed by CeloTestHelper.
 */
interface CeloTestVm {
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function deal(address who, uint256 newBalance) external;
    function roll(uint256 blockNumber) external;
    function warp(uint256 timestamp) external;
    function addr(uint256 privateKey) external pure returns (address);
    function label(address account, string calldata newLabel) external;
    function toString(uint256 value) external pure returns (string memory);
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function expectRevert(bytes memory revertData) external;

    function expectRevert() external;

    function load(address account, bytes32 slot) external view returns (bytes32);
}

/// @dev Minimal interface for contracts with a rebalance(address,address) function.
///      Both Manager and DefaultStrategy expose this signature.
interface IRebalanceable {
    function rebalance(address fromGroup, address toGroup) external;
}

/**
 * @title CeloTestHelper
 * @notice Shared abstract base contract for ALL Foundry tests.
 *         Ports every utility function from test-ts/utils.ts (651 LOC) to Solidity.
 * @dev Extend this contract in concrete test files and call _initNamedAccounts()
 *      inside setUp().
 *
 *      Because forge-std/Test.sol requires pragma >=0.8.13, this helper defines
 *      its own minimal CeloTestVm interface matching the cheatcode ABI. The VM
 *      address is the standard Foundry cheatcode address.
 */
abstract contract CeloTestHelper {
    // =========================================================================
    //                          FOUNDRY VM
    // =========================================================================

    /// @dev Foundry cheatcode VM (same address used by forge-std).
    CeloTestVm internal constant vm =
        CeloTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // =========================================================================
    //                              CONSTANTS
    // =========================================================================

    /// @notice The canonical Celo Registry address.
    address internal constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;

    /// @notice Blocks per epoch (hardcoded into ganache / test environment).
    uint256 internal constant BLOCKS_PER_EPOCH = 100;

    /// @notice Seconds in one hour.
    uint256 internal constant HOUR = 60 * 60;

    /// @notice Seconds in one day.
    uint256 internal constant DAY = 24 * HOUR;

    /// @notice LockedGold unlocking period (3 days).
    uint256 internal constant LOCKED_GOLD_UNLOCKING_PERIOD = 3 * DAY;

    /// @notice Minimum validator locked CELO (10 000 CELO).
    uint256 internal constant MIN_VALIDATOR_LOCKED_CELO = 10_000 ether;

    /// @notice Zero address constant.
    address internal constant ADDRESS_ZERO = address(0);

    // ---- Registry IDs (mirrors UsingRegistryUpgradeable) ----
    bytes32 internal constant ACCOUNTS_REGISTRY_ID = keccak256(abi.encodePacked("Accounts"));
    bytes32 internal constant ELECTION_REGISTRY_ID = keccak256(abi.encodePacked("Election"));
    bytes32 internal constant GOLD_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("GoldToken"));
    bytes32 internal constant LOCKED_GOLD_REGISTRY_ID = keccak256(abi.encodePacked("LockedGold"));
    bytes32 internal constant GOVERNANCE_REGISTRY_ID = keccak256(abi.encodePacked("Governance"));
    bytes32 internal constant VALIDATORS_REGISTRY_ID = keccak256(abi.encodePacked("Validators"));

    // =========================================================================
    //                          NAMED ACCOUNTS
    // =========================================================================
    //
    // Matches hardhat.config.ts namedAccounts (lines 36-59):
    //   deployer       = index 0
    //   multisigOwner0 = index 3
    //   multisigOwner1 = index 4
    //   multisigOwner2 = index 5
    //   multisigOwner3 = index 6
    //   multisigOwner4 = index 7
    //   owner          = index 6  (same as multisigOwner3)

    address internal deployer;
    address internal multisigOwner0;
    address internal multisigOwner1;
    address internal multisigOwner2;
    address internal multisigOwner3;
    address internal multisigOwner4;
    address internal owner; // same as multisigOwner3

    // =========================================================================
    //                            STRUCTS
    // =========================================================================
    //
    // Ported from test-ts/utils-interfaces.ts

    /// @dev Expected-vs-real comparison for a group (used by rebalance helpers).
    struct ExpectVsReal {
        address group;
        uint256 expected;
        uint256 real;
        int256 diff; // signed: real - expected
    }

    /// @dev A group together with its stCELO and CELO amounts.
    struct OrderedGroup {
        address group;
        uint256 stCelo;
        uint256 realCelo;
    }

    // =========================================================================
    //                         INTERNAL STATE
    // =========================================================================

    /// @dev Monotonic counter for randomAddress() uniqueness.
    uint256 private _randomAddrNonce;

    // =========================================================================
    //                   FORGE-STD REPLACEMENTS
    // =========================================================================
    //
    // Re-implements makeAddr / makeAddrAndKey from StdCheats since we cannot
    // import forge-std with pragma 0.8.11.

    /// @notice Create a deterministic address from a label string.
    /// @dev Mirrors forge-std StdCheats.makeAddr().
    function makeAddr(string memory name) internal returns (address addr) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
        vm.label(addr, name);
    }

    /// @notice Create a deterministic address and return its private key.
    /// @dev Mirrors forge-std StdCheats.makeAddrAndKey().
    function makeAddrAndKey(string memory name)
        internal
        returns (address addr, uint256 privateKey)
    {
        privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
        vm.label(addr, name);
    }

    // =========================================================================
    //                     NAMED ACCOUNT SETUP
    // =========================================================================

    /// @notice Initialise deterministic named accounts. Call in setUp().
    function _initNamedAccounts() internal {
        deployer = makeAddr("deployer");
        multisigOwner0 = makeAddr("multisigOwner0");
        multisigOwner1 = makeAddr("multisigOwner1");
        multisigOwner2 = makeAddr("multisigOwner2");
        multisigOwner3 = makeAddr("multisigOwner3");
        multisigOwner4 = makeAddr("multisigOwner4");
        owner = multisigOwner3; // same as multisigOwner3
    }

    // =========================================================================
    //                         ACCOUNT UTILS
    // =========================================================================

    /// @notice Generate a unique random address.
    /// @dev Uses an internal nonce to guarantee uniqueness across calls.
    function randomAddress() internal returns (address) {
        _randomAddrNonce++;
        return makeAddr(vm.toString(_randomAddrNonce));
    }

    /// @notice Create a random signer address with an optional initial balance.
    /// @return addr  The generated address.
    /// @return privateKey  The corresponding private key (usable with vm.sign).
    function randomSigner(uint256 initialBalance)
        internal
        returns (address addr, uint256 privateKey)
    {
        _randomAddrNonce++;
        (addr, privateKey) = makeAddrAndKey(vm.toString(_randomAddrNonce));
        if (initialBalance > 0) {
            vm.deal(addr, initialBalance);
        }
    }

    /// @notice Create a random signer with zero balance.
    function randomSigner() internal returns (address addr, uint256 privateKey) {
        return randomSigner(0);
    }

    /// @notice Prepare an address for impersonation by setting its balance.
    /// @dev In Foundry use vm.prank() / vm.startPrank() per-call; this helper
    ///      only ensures the target has funds.
    function getImpersonatedSigner(address target, uint256 initialBalance) internal {
        if (initialBalance > 0) {
            vm.deal(target, initialBalance);
        }
    }

    /// @notice Set the CELO balance of an address.
    function setBalance(address target, uint256 amount) internal {
        vm.deal(target, amount);
    }

    // NOTE: impersonateAccount() from utils.ts maps to vm.prank() / vm.startPrank()
    //       in Foundry. These are called inline at the test-site, so no wrapper is needed.

    // =========================================================================
    //                          EPOCH UTILS
    // =========================================================================

    /// @notice Mine blocks until the next epoch boundary (default epoch size).
    function mineToNextEpoch() internal {
        mineToNextEpoch(BLOCKS_PER_EPOCH);
    }

    /// @notice Mine blocks until the next epoch boundary (custom epoch size).
    function mineToNextEpoch(uint256 epochSize) internal {
        uint256 blockNumber = block.number;
        uint256 epochNumber = getEpochNumberOfBlock(blockNumber, epochSize);
        uint256 firstBlockOfNext = getFirstBlockNumberForEpoch(epochNumber + 1, epochSize);
        uint256 blocksToMine = firstBlockOfNext - blockNumber;
        mineBlocks(blocksToMine);
    }

    /// @notice Get the current epoch number (default epoch size).
    function currentEpochNumber() internal view returns (uint256) {
        return getEpochNumberOfBlock(block.number, BLOCKS_PER_EPOCH);
    }

    /// @notice Get the current epoch number (custom epoch size).
    function currentEpochNumber(uint256 epochSize) internal view returns (uint256) {
        return getEpochNumberOfBlock(block.number, epochSize);
    }

    /// @notice Get the epoch number for a given block number.
    /// @dev Follows GetEpochNumber from celo-blockchain consensus/istanbul/utils.go.
    function getEpochNumberOfBlock(uint256 blockNumber, uint256 epochSize)
        internal
        pure
        returns (uint256)
    {
        uint256 epochNumber = blockNumber / epochSize;
        if (blockNumber % epochSize == 0) {
            return epochNumber;
        } else {
            return epochNumber + 1;
        }
    }

    /// @notice Get the epoch number for a given block number (default epoch size).
    function getEpochNumberOfBlock(uint256 blockNumber) internal pure returns (uint256) {
        return getEpochNumberOfBlock(blockNumber, BLOCKS_PER_EPOCH);
    }

    /// @notice Get the first block number of a given epoch.
    /// @dev Follows GetEpochFirstBlockNumber from celo-blockchain consensus/istanbul/utils.go.
    function getFirstBlockNumberForEpoch(uint256 epochNumber, uint256 epochSize)
        internal
        pure
        returns (uint256)
    {
        if (epochNumber == 0) {
            return 0;
        }
        return (epochNumber - 1) * epochSize + 1;
    }

    /// @notice Get the first block number of a given epoch (default epoch size).
    function getFirstBlockNumberForEpoch(uint256 epochNumber) internal pure returns (uint256) {
        return getFirstBlockNumberForEpoch(epochNumber, BLOCKS_PER_EPOCH);
    }

    /// @notice Advance the block number by `blocks`.
    function mineBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }

    /// @notice Advance the block timestamp by `seconds_` and mine one block.
    function timeTravel(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    // =========================================================================
    //                         ADDRESS UTILS
    // =========================================================================

    /// @notice Convert a bytes32 (padded linked-list entry) to an address.
    /// @dev Solidity addresses are 20 bytes. This trims a zero-padded bytes32 value
    ///      (e.g. from a SortedLinkedList) to a proper address, matching the TS
    ///      `toAddress(hex.substring(0, 42))` helper.
    function toAddress(bytes32 value) internal pure returns (address) {
        return address(uint160(uint256(value)));
    }

    // =========================================================================
    //                        EPOCH REWARDS
    // =========================================================================

    /// @notice Distribute epoch rewards to a group via the Election contract.
    /// @dev Impersonates address(0) (the Celo VM caller for epoch rewards).
    ///      With MockElection, lesser/greater are unused so ADDRESS_ZERO is passed.
    function distributeEpochRewards(
        IElection election,
        address group,
        uint256 amount
    ) internal {
        vm.prank(ADDRESS_ZERO);
        election.distributeEpochRewards(group, amount, ADDRESS_ZERO, ADDRESS_ZERO);
    }

    // =========================================================================
    //                    DEFAULT STRATEGY HELPERS
    // =========================================================================

    /// @notice Walk the DefaultStrategy linked list and return all active groups.
    /// @dev Traverses from head following the "previous" link.
    function getDefaultGroups(DefaultStrategy defaultStrategy)
        internal
        view
        returns (address[] memory)
    {
        uint256 numGroups = defaultStrategy.getNumberOfGroups();
        address[] memory groups = new address[](numGroups);

        if (numGroups == 0) return groups;

        (address key, ) = defaultStrategy.getGroupsHead();

        for (uint256 i = 0; i < numGroups; i++) {
            groups[i] = key;
            (key, ) = defaultStrategy.getGroupPreviousAndNext(key);
        }

        return groups;
    }

    /// @notice Get all active groups with their stCELO amounts.
    function getDefaultGroupsWithStCelo(DefaultStrategy defaultStrategy)
        internal
        view
        returns (OrderedGroup[] memory)
    {
        address[] memory groups = getDefaultGroups(defaultStrategy);
        OrderedGroup[] memory result = new OrderedGroup[](groups.length);

        for (uint256 i = 0; i < groups.length; i++) {
            result[i] = OrderedGroup({
                group: groups[i],
                stCelo: defaultStrategy.stCeloInGroup(groups[i]),
                realCelo: 0
            });
        }

        return result;
    }

    // =========================================================================
    //                 SPECIFIC GROUP STRATEGY HELPERS
    // =========================================================================

    /// @notice Get all voted groups from SpecificGroupStrategy.
    function getSpecificGroups(SpecificGroupStrategy specificGroupStrategy)
        internal
        view
        returns (address[] memory)
    {
        uint256 numGroups = specificGroupStrategy.getNumberOfVotedGroups();
        address[] memory groups = new address[](numGroups);

        for (uint256 i = 0; i < numGroups; i++) {
            groups[i] = specificGroupStrategy.getVotedGroup(i);
        }

        return groups;
    }

    /// @notice Get all blocked groups from SpecificGroupStrategy.
    function getBlockedSpecificGroupStrategies(SpecificGroupStrategy specificGroupStrategy)
        internal
        view
        returns (address[] memory)
    {
        uint256 numBlocked = specificGroupStrategy.getNumberOfBlockedGroups();
        address[] memory groups = new address[](numBlocked);

        for (uint256 i = 0; i < numBlocked; i++) {
            groups[i] = specificGroupStrategy.getBlockedGroup(i);
        }

        return groups;
    }

    // =========================================================================
    //                    COMBINED STRATEGY HELPERS
    // =========================================================================

    /// @notice Get all groups across both strategies (union, no duplicates).
    function getGroupsOfAllStrategies(
        DefaultStrategy defaultStrategy,
        SpecificGroupStrategy specificGroupStrategy
    ) internal view returns (address[] memory) {
        address[] memory defaultGroups = getDefaultGroups(defaultStrategy);
        address[] memory specificGroups = getSpecificGroups(specificGroupStrategy);

        // Worst case: all groups are unique
        address[] memory temp = new address[](defaultGroups.length + specificGroups.length);
        uint256 count = 0;

        for (uint256 i = 0; i < defaultGroups.length; i++) {
            temp[count++] = defaultGroups[i];
        }

        for (uint256 i = 0; i < specificGroups.length; i++) {
            bool isDuplicate = false;
            for (uint256 j = 0; j < defaultGroups.length; j++) {
                if (specificGroups[i] == defaultGroups[j]) {
                    isDuplicate = true;
                    break;
                }
            }
            if (!isDuplicate) {
                temp[count++] = specificGroups[i];
            }
        }

        // Trim to actual size
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    // =========================================================================
    //                   EXPECTED VS REAL HELPERS
    // =========================================================================

    /// @notice Get expected-vs-actual CELO for each group from Manager.
    function getRealVsExpectedCeloForGroups(Manager manager, address[] memory groups)
        internal
        view
        returns (ExpectVsReal[] memory)
    {
        ExpectVsReal[] memory result = new ExpectVsReal[](groups.length);

        for (uint256 i = 0; i < groups.length; i++) {
            (uint256 expected, uint256 actual) = manager.getExpectedAndActualCeloForGroup(
                groups[i]
            );
            result[i] = ExpectVsReal({
                group: groups[i],
                expected: expected,
                real: actual,
                diff: int256(actual) - int256(expected)
            });
        }

        return result;
    }

    /// @notice Get expected-vs-actual stCELO for each group from DefaultStrategy.
    function getRealVsExpectedStCeloForGroupsDefaultStrategy(
        DefaultStrategy defaultStrategy,
        address[] memory groups
    ) internal view returns (ExpectVsReal[] memory) {
        ExpectVsReal[] memory result = new ExpectVsReal[](groups.length);

        for (uint256 i = 0; i < groups.length; i++) {
            (uint256 expected, uint256 actual) = defaultStrategy
                .getExpectedAndActualStCeloForGroup(groups[i]);
            result[i] = ExpectVsReal({
                group: groups[i],
                expected: expected,
                real: actual,
                diff: int256(actual) - int256(expected)
            });
        }

        return result;
    }

    // =========================================================================
    //                        REBALANCE HELPERS
    // =========================================================================

    /// @notice Rebalance all unbalanced groups using a two-pointer approach.
    /// @dev Works with any contract exposing rebalance(address,address) via IRebalanceable.
    ///      Ported from rebalanceInternal() in utils.ts.
    function _rebalanceInternal(
        IRebalanceable rebalanceContract,
        ExpectVsReal[] memory expectedVsReal
    ) internal {
        // Collect unbalanced entries
        uint256 unbalancedCount = 0;
        for (uint256 i = 0; i < expectedVsReal.length; i++) {
            if (expectedVsReal[i].diff != 0) {
                unbalancedCount++;
            }
        }

        if (unbalancedCount == 0) return;

        ExpectVsReal[] memory unbalanced = new ExpectVsReal[](unbalancedCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < expectedVsReal.length; i++) {
            if (expectedVsReal[i].diff != 0) {
                unbalanced[idx++] = expectedVsReal[i];
            }
        }

        // Sort descending by diff (insertion sort — matching TS sort comparator)
        for (uint256 i = 1; i < unbalanced.length; i++) {
            ExpectVsReal memory key = unbalanced[i];
            uint256 j = i;
            while (j > 0 && unbalanced[j - 1].diff < key.diff) {
                unbalanced[j] = unbalanced[j - 1];
                j--;
            }
            unbalanced[j] = key;
        }

        // Two-pointer rebalance
        uint256 first = 0;
        uint256 last = unbalanced.length - 1;

        while (first < last) {
            rebalanceContract.rebalance(unbalanced[first].group, unbalanced[last].group);

            int256 sumDiff = unbalanced[first].diff + unbalanced[last].diff;

            if (sumDiff < 0) {
                unbalanced[last].diff = sumDiff;
                first++;
            } else if (sumDiff > 0) {
                unbalanced[first].diff = sumDiff;
                last--;
            } else {
                unbalanced[first].diff = 0;
                unbalanced[last].diff = 0;
                first++;
                last--;
            }
        }
    }

    /// @notice Rebalance groups in the DefaultStrategy.
    function rebalanceDefaultGroups(DefaultStrategy defaultStrategy) internal {
        address[] memory activeGroups = getDefaultGroups(defaultStrategy);
        ExpectVsReal[] memory expectedVsReal = getRealVsExpectedStCeloForGroupsDefaultStrategy(
            defaultStrategy,
            activeGroups
        );
        _rebalanceInternal(IRebalanceable(address(defaultStrategy)), expectedVsReal);
    }

    /// @notice Rebalance groups across all strategies via Manager.
    function rebalanceGroups(
        Manager manager,
        SpecificGroupStrategy specificGroupStrategy,
        DefaultStrategy defaultStrategy
    ) internal {
        address[] memory allGroups = getGroupsOfAllStrategies(
            defaultStrategy,
            specificGroupStrategy
        );
        ExpectVsReal[] memory expectedVsReal = getRealVsExpectedCeloForGroups(manager, allGroups);
        _rebalanceInternal(IRebalanceable(address(manager)), expectedVsReal);
    }

    // =========================================================================
    //                         SORT HELPERS
    // =========================================================================

    /// @notice Get unsorted groups from DefaultStrategy.
    function getUnsortedGroups(DefaultStrategy defaultStrategy)
        internal
        view
        returns (address[] memory)
    {
        uint256 length = defaultStrategy.getNumberOfUnsortedGroups();
        address[] memory groups = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            groups[i] = defaultStrategy.getUnsortedGroupAt(i);
        }

        return groups;
    }

    /// @notice Sort all unsorted groups in the DefaultStrategy linked list.
    /// @dev Faithfully ports sortActiveGroups() from utils.ts (lines 567-600).
    ///      Processes unsorted groups from last to first (matching TS pop() order)
    ///      and walks the ordered list to find the correct insertion point.
    function sortActiveGroups(DefaultStrategy defaultStrategy) internal {
        address[] memory unsorted = getUnsortedGroups(defaultStrategy);

        // Process from end of array (TS uses pop() which takes the last element)
        for (uint256 u = unsorted.length; u > 0; u--) {
            address uGroup = unsorted[u - 1];
            uint256 uGroupStCelo = defaultStrategy.stCeloInGroup(uGroup);

            // Refresh the ordered list after each update
            OrderedGroup[] memory sorted = getDefaultGroupsWithStCelo(defaultStrategy);

            address prev = ADDRESS_ZERO;
            address next = ADDRESS_ZERO;
            uint256 i = 0;

            // Mirrors TS: while (i++ < defaultGroupsWithStCelo.length)
            // Body executes with i starting at 1 due to post-increment.
            while (i < sorted.length) {
                i++;

                prev = next;
                next = (i < sorted.length) ? sorted[i].group : ADDRESS_ZERO;

                // Out of bounds or found a group with more stCelo → insertion point
                if (i >= sorted.length || sorted[i].stCelo > uGroupStCelo) {
                    break;
                }

                // Skip self — adjust next to the element before it
                if (sorted[i].group == uGroup) {
                    next = (i > 0) ? sorted[i - 1].group : ADDRESS_ZERO;
                    continue;
                }
            }

            defaultStrategy.updateActiveGroupOrder(uGroup, prev, next);
        }
    }

    // =========================================================================
    //                     ORDERED GROUPS HELPERS
    // =========================================================================

    /// @notice Get ordered active groups with stCELO amounts.
    /// @dev Traverses the linked list from head via the "previous" link and
    ///      builds the result array in reverse order (matching TS unshift).
    function getOrderedActiveGroups(DefaultStrategy defaultStrategy)
        internal
        view
        returns (OrderedGroup[] memory)
    {
        return getOrderedActiveGroups(defaultStrategy, address(0));
    }

    /// @notice Get ordered active groups with stCELO and CELO amounts.
    function getOrderedActiveGroups(DefaultStrategy defaultStrategy, address accountAddr)
        internal
        view
        returns (OrderedGroup[] memory)
    {
        uint256 numGroups = defaultStrategy.getNumberOfGroups();
        OrderedGroup[] memory groups = new OrderedGroup[](numGroups);

        if (numGroups == 0) return groups;

        (address head, ) = defaultStrategy.getGroupsHead();

        for (uint256 i = 0; i < numGroups; i++) {
            (address prev, ) = defaultStrategy.getGroupPreviousAndNext(head);
            uint256 stCelo = defaultStrategy.stCeloInGroup(head);
            uint256 realCelo = 0;

            if (accountAddr != address(0)) {
                realCelo = Account(payable(accountAddr)).getCeloForGroup(head);
            }

            // Store in reverse order (matching TS unshift / prepend)
            groups[numGroups - 1 - i] = OrderedGroup({
                group: head,
                stCelo: stCelo,
                realCelo: realCelo
            });

            head = prev;
        }

        return groups;
    }

    // =========================================================================
    //                 MOCK VALIDATOR GROUP HELPERS
    // =========================================================================

    /// @notice Revoke election on mock validator groups and optionally update health.
    /// @dev Ports revokeElectionOnMockValidatorGroupsAndUpdate from utils.ts (lines 394-426).
    ///      Clears elected validators that belong to the specified groups.
    function revokeElectionOnMockValidatorGroupsAndUpdate(
        IValidators validators,
        IAccounts accounts,
        MockGroupHealth groupHealth,
        address[] memory validatorGroups,
        bool update
    ) internal {
        // Collect all validator signers for the given groups
        uint256 totalSigners = 0;
        for (uint256 i = 0; i < validatorGroups.length; i++) {
            (address[] memory members, , , , , , ) = validators.getValidatorGroup(
                validatorGroups[i]
            );
            totalSigners += members.length;
        }

        address[] memory allSigners = new address[](totalSigners);
        uint256 signerIdx = 0;
        for (uint256 i = 0; i < validatorGroups.length; i++) {
            (address[] memory members, , , , , , ) = validators.getValidatorGroup(
                validatorGroups[i]
            );
            for (uint256 j = 0; j < members.length; j++) {
                allSigners[signerIdx++] = accounts.getValidatorSigner(members[j]);
            }
        }

        // Clear elected validators that match any signer
        uint256 numValidators = groupHealth.numberOfValidators();
        for (uint256 i = 0; i < numValidators; i++) {
            address elected = groupHealth.electedValidators(i);
            for (uint256 j = 0; j < allSigners.length; j++) {
                if (elected == allSigners[j]) {
                    groupHealth.setElectedValidator(i, ADDRESS_ZERO);
                    break;
                }
            }
        }

        if (!update) return;

        for (uint256 i = 0; i < validatorGroups.length; i++) {
            groupHealth.updateGroupHealth(validatorGroups[i]);
        }
    }

    // =========================================================================
    //              UPDATE GROUP CELO BASED ON stCELO
    // =========================================================================

    /// @notice Updates MockAccount's CELO for each group based on protocol stCELO allocations.
    /// @dev Ports updateGroupCeloBasedOnProtocolStCelo from utils.ts (lines 602-651).
    ///      Combines stCELO from both DefaultStrategy and SpecificGroupStrategy,
    ///      converts to CELO via Manager.toCelo(), and sets MockAccount state.
    function updateGroupCeloBasedOnProtocolStCelo(
        MockDefaultStrategy defaultStrategy,
        SpecificGroupStrategy specificStrategy,
        MockAccount account,
        Manager manager
    ) internal {
        address[] memory defaultGroups = getDefaultGroups(
            DefaultStrategy(address(defaultStrategy))
        );
        address[] memory specificGroups = getSpecificGroups(specificStrategy);

        // Track unique groups and their combined stCELO amounts
        uint256 maxGroups = defaultGroups.length + specificGroups.length;
        address[] memory allGroupAddrs = new address[](maxGroups);
        uint256[] memory allGroupAmounts = new uint256[](maxGroups);
        uint256 groupCount = 0;

        // Add default groups
        for (uint256 i = 0; i < defaultGroups.length; i++) {
            allGroupAddrs[groupCount] = defaultGroups[i];
            allGroupAmounts[groupCount] = defaultStrategy.stCeloInGroup(defaultGroups[i]);
            groupCount++;
        }

        // Add specific groups (merge if already present from default)
        for (uint256 i = 0; i < specificGroups.length; i++) {
            (uint256 total, uint256 overflow, uint256 unhealthy) = specificStrategy
                .getStCeloInGroup(specificGroups[i]);
            uint256 amount = total - overflow - unhealthy;

            // Check if group already exists from default strategy
            bool found = false;
            for (uint256 j = 0; j < groupCount; j++) {
                if (allGroupAddrs[j] == specificGroups[i]) {
                    allGroupAmounts[j] += amount;
                    found = true;
                    break;
                }
            }

            if (!found) {
                allGroupAddrs[groupCount] = specificGroups[i];
                allGroupAmounts[groupCount] = amount;
                groupCount++;
            }
        }

        // Update MockAccount CELO for each group
        for (uint256 i = 0; i < groupCount; i++) {
            uint256 celoInGroup = manager.toCelo(allGroupAmounts[i]);
            account.setCeloForGroup(allGroupAddrs[i], celoInGroup);
            uint256 halfCelo = celoInGroup / 2;
            account.setScheduledVotes(allGroupAddrs[i], halfCelo);
            account.setVotesForGroup(allGroupAddrs[i], halfCelo);
        }
    }

    // =========================================================================
    //                       OVERFLOW HELPERS
    // =========================================================================

    /// @notice Set up an overflow test scenario.
    /// @dev Ports prepareOverflow from utils.ts (lines 480-521).
    ///      Requires at least 3 groups. The vote amounts are derived from a system
    ///      of linear equations such that, given 12 validators registered and elected,
    ///      the remaining receivable votes are [40, 100, 200] CELO respectively.
    ///      Caller must ensure DefaultStrategy.addActivatableGroup / activateGroup are
    ///      called from the contract owner context (use vm.startPrank before calling).
    function prepareOverflow(
        DefaultStrategy defaultStrategy,
        IElection election,
        ILockedGold lockedGold,
        address voter,
        address[] memory groupAddresses,
        bool activateGroups
    ) internal {
        require(groupAddresses.length >= 3, "Need at least 3 groups");

        // Derived vote amounts matching the TS test fixtures
        uint256[3] memory votes = [
            uint256(95_824 ether),
            uint256(143_697 ether),
            uint256(95_664 ether)
        ];

        // Lock CELO and optionally activate groups (reverse order matches TS)
        for (uint256 i = 3; i > 0; i--) {
            uint256 idx = i - 1;
            (address head, ) = defaultStrategy.getGroupsHead();

            if (activateGroups) {
                defaultStrategy.addActivatableGroup(groupAddresses[idx]);
                defaultStrategy.activateGroup(groupAddresses[idx], ADDRESS_ZERO, head);
            }

            vm.prank(voter);
            lockedGold.lock{value: votes[idx]}();
        }

        // Vote in a separate loop because voting limits depend on total locked CELO
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(voter);
            // MockElection.vote ignores lesser/greater
            election.vote(groupAddresses[i], votes[i], ADDRESS_ZERO, ADDRESS_ZERO);
        }
    }

    /// @notice Overload: prepareOverflow with activateGroups=true.
    function prepareOverflow(
        DefaultStrategy defaultStrategy,
        IElection election,
        ILockedGold lockedGold,
        address voter,
        address[] memory groupAddresses
    ) internal {
        prepareOverflow(defaultStrategy, election, lockedGold, voter, groupAddresses, true);
    }

    // =========================================================================
    //                        ASSERTION HELPERS
    // =========================================================================

    /// @notice Assert that two uint256 values are equal.
    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "Assertion failed: values not equal");
    }

    /// @notice Assert that a boolean is true.
    function assertTrue(bool condition) internal pure {
        require(condition, "Assertion failed: condition is false");
    }

    /// @notice Assert that a boolean is false.
    function assertFalse(bool condition) internal pure {
        require(!condition, "Assertion failed: condition is true");
    }

    /// @notice Assert that two addresses are equal.
    function assertEq(address a, address b) internal pure {
        require(a == b, "Assertion failed: addresses not equal");
    }

    /// @notice Assert that two addresses are not equal.
    function assertNotEq(address a, address b) internal pure {
        require(a != b, "Assertion failed: addresses are equal");
    }

    /// @notice Assert that two uint256 values are not equal.
    function assertNotEq(uint256 a, uint256 b) internal pure {
        require(a != b, "Assertion failed: values are equal");
    }

    // =========================================================================
    //               HARDHAT-TASK STUBS & GOVERNANCE
    // =========================================================================
    //
    // The following TS utility functions are wrappers around Hardhat tasks or
    // ContractKit APIs with no direct Foundry equivalent. They are documented
    // here for completeness. In Foundry tests, interact with the contracts
    // directly:
    //
    //   submitAndExecuteProposal  → use MultiSigHelper.submitAndExecuteMultiSigProposal()
    //   activateAndVoteTest       → call Account.activateAndVote() directly
    //   revokeTest                → call Account-level revoke functions directly
    //   resetNetwork              → use vm.createFork() / vm.selectFork()
    //   upgradeToMockGroupHealthE2E → deploy MockGroupHealth and upgradeTo() in setUp()
    //   updateMaxNumberOfGroups   → call election.setAllowedToVoteOverMaxNumberOfGroups()
    //                               directly after vm.prank(account)
    //   setGovernanceConcurrentProposals → setConcurrentProposals() is on the
    //                               real Celo Governance contract, not in our mock.
    //                               Impersonate the governance owner and call directly
    //                               when needed.
}
