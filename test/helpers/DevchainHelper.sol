// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./MultiSigHelper.sol";

/**
 * @dev Additional Foundry cheatcodes used by the devchain helper. CeloTestVm (defined in
 *      CeloTestHelper) only declares the basics; this interface is cast onto the same
 *      cheatcode address.
 */
interface DevchainVm {
    struct Wallet {
        address addr;
        uint256 publicKeyX;
        uint256 publicKeyY;
        uint256 privateKey;
    }

    function loadAllocs(string calldata pathToAllocsJson) external;

    function readFile(string calldata path) external view returns (string memory);

    function parseJsonUint(string calldata json, string calldata key)
        external
        pure
        returns (uint256);

    function mockCall(
        address callee,
        bytes calldata data,
        bytes calldata returnData
    ) external;

    function clearMockedCalls() external;

    function createWallet(string calldata walletLabel) external returns (Wallet memory);

    function sign(uint256 privateKey, bytes32 digest)
        external
        pure
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        );

    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

// ---------------------------------------------------------------------------
// Minimal interfaces for the Celo L2 core contracts that live in the devchain.
// Only the functions the tests need are declared. Function selectors were
// verified against @celo/devchain-anvil/selectors/*.json.
// ---------------------------------------------------------------------------

interface ICeloRegistry {
    function getAddressForStringOrDie(string calldata identifier) external view returns (address);

    function getAddressForString(string calldata identifier) external view returns (address);

    function setAddressFor(string calldata identifier, address addr) external;

    function owner() external view returns (address);
}

interface ICeloValidators {
    function registerValidatorGroup(uint256 commission) external returns (bool);

    /// @dev registerValidator(bytes) wraps this with a second reentrancy guard and reverts.
    function registerValidatorNoBls(bytes calldata ecdsaPublicKey) external returns (bool);

    function affiliate(address group) external returns (bool);

    function deaffiliate() external returns (bool);

    function addFirstMember(
        address validator,
        address lesser,
        address greater
    ) external returns (bool);

    function addMember(address validator) external returns (bool);

    function removeMember(address validator) external returns (bool);

    function deregisterValidatorGroup(uint256 index) external returns (bool);

    function deregisterValidator(uint256 index) external returns (bool);

    function halveSlashingMultiplier(address group) external;

    function updateEcdsaPublicKey(
        address account,
        address signer,
        bytes calldata ecdsaPublicKey
    ) external returns (bool);

    function isValidatorGroup(address account) external view returns (bool);

    function isValidator(address account) external view returns (bool);

    function getValidatorGroup(address account)
        external
        view
        returns (
            address[] memory,
            uint256,
            uint256,
            uint256,
            uint256[] memory,
            uint256,
            uint256
        );

    function getValidator(address account)
        external
        view
        returns (
            bytes memory ecdsaPublicKey,
            bytes memory blsPublicKey,
            address affiliation,
            uint256 score,
            address signer
        );

    function getValidatorGroupSlashingMultiplier(address account) external view returns (uint256);

    function getValidatorLockedGoldRequirements() external view returns (uint256, uint256);

    function getGroupLockedGoldRequirements() external view returns (uint256, uint256);

    function getAccountLockedGoldRequirement(address account) external view returns (uint256);

    function getRegisteredValidatorGroups() external view returns (address[] memory);

    function getRegisteredValidators() external view returns (address[] memory);

    function getNumRegisteredValidators() external view returns (uint256);

    function getGroupNumMembers(address account) external view returns (uint256);

    function getMembershipInLastEpoch(address account) external view returns (address);

    function meetsAccountLockedGoldRequirements(address account) external view returns (bool);

    function owner() external view returns (address);
}

interface ICeloLockedGold is ILockedGold {
    function setUnlockingPeriod(uint256 period) external;

    function addSlasher(string calldata slasherIdentifier) external;

    function getAccountTotalGovernanceVotingPower(address account) external view returns (uint256);
}

interface ICeloEpochManager {
    function getCurrentEpochNumber() external view returns (uint256);

    function getEpochNumberOfBlock(uint256 blockNumber) external view returns (uint256);

    function epochDuration() external view returns (uint256);

    function isOnEpochProcess() external view returns (bool);

    function isTimeForNextEpoch() external view returns (bool);

    function getElectedAccounts() external view returns (address[] memory);

    function numberOfElectedInCurrentSet() external view returns (uint256);

    function getElectedSignerByIndex(uint256 index) external view returns (address);
}

interface ICeloGovernance is IGovernance {
    function owner() external view returns (address);

    function approver() external view returns (address);

    function minDeposit() external view returns (uint256);

    function concurrentProposals() external view returns (uint256);

    function setConcurrentProposals(uint256 count) external;

    function propose(
        uint256[] calldata values,
        address[] calldata destinations,
        bytes calldata data,
        uint256[] calldata dataLengths,
        string calldata descriptionUrl
    ) external payable returns (uint256);

    function upvote(
        uint256 proposalId,
        uint256 lesser,
        uint256 greater
    ) external returns (bool);

    function approve(uint256 proposalId, uint256 index) external returns (bool);

    function dequeueProposalsIfReady() external;

    function getDequeue() external view returns (uint256[] memory);

    function getQueue() external view returns (uint256[] memory, uint256[] memory);

    function getVoteTotals(uint256 proposalId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function getVoteRecord(address account, uint256 index)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function getProposalStage(uint256 proposalId) external view returns (uint8);

    function dequeueFrequency() external view returns (uint256);

    function isQueued(uint256 proposalId) external view returns (bool);

    function isDequeuedProposal(uint256 proposalId, uint256 index) external view returns (bool);

    function getMostRecentReferendumProposal(address account) external view returns (uint256);
}

/**
 * @title DevchainHelper
 * @notice Base contract for tests that run against the real Celo core contracts.
 * @dev Loads the state of `@celo/devchain-anvil` (see scripts/prepare-devchain.sh) into
 *      the test EVM with `vm.loadAllocs` and ports the ContractKit based utilities of
 *      test-ts/utils.ts and test-ts/utils-validators.ts to Solidity.
 *
 *      The Hardhat suite forked a ganache based Celo L1 devchain. The anvil devchain is a
 *      Celo L2 devchain, which differs in two places that matter for tests:
 *        - epochs are tracked by the EpochManager contract instead of block numbers, so
 *          `mineToNextEpoch()` bumps a mocked epoch number on EpochManager;
 *        - `Election.distributeEpochRewards` is callable by EpochManager instead of the
 *          zero address, so `distributeEpochRewards()` pranks EpochManager.
 */
abstract contract DevchainHelper is MultiSigHelper {
    string internal constant DEVCHAIN_ALLOCS_PATH = "test/devchain/allocs.json";
    string internal constant DEVCHAIN_META_PATH = "test/devchain/meta.json";

    DevchainVm internal constant dvm =
        DevchainVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Celo core contracts resolved from the Registry at 0x...ce10.
    ICeloRegistry internal celoRegistry;
    IAccounts internal celoAccounts;
    ICeloLockedGold internal celoLockedGold;
    IElection internal celoElection;
    ICeloValidators internal celoValidators;
    ICeloEpochManager internal celoEpochManager;
    IGoldToken internal celoGoldToken;
    ICeloGovernance internal celoGovernance;

    /// @dev Locked CELO required per validator / per group member on this devchain.
    uint256 internal validatorLockedGoldRequirement;
    uint256 internal groupLockedGoldRequirement;

    /// @dev Epoch number reported to core contracts (mocked on EpochManager).
    uint256 internal devchainEpochNumber;

    /// @dev Wallets created through createWallet(): public key and private key by address.
    mapping(address => bytes) internal walletPublicKey;
    mapping(address => uint256) internal walletPrivateKey;
    uint256 private _walletNonce;

    // =========================================================================
    //                              LOADING
    // =========================================================================

    /// @notice Load the devchain state and resolve the core contracts. Call in setUp().
    function loadDevchain() internal {
        dvm.loadAllocs(DEVCHAIN_ALLOCS_PATH);

        string memory meta = dvm.readFile(DEVCHAIN_META_PATH);
        uint256 blockNumber = dvm.parseJsonUint(meta, ".blockNumber");
        uint256 timestamp = dvm.parseJsonUint(meta, ".timestamp");
        vm.roll(blockNumber + 1);
        vm.warp(timestamp + 1);

        celoRegistry = ICeloRegistry(REGISTRY_ADDRESS);
        celoAccounts = IAccounts(celoRegistry.getAddressForStringOrDie("Accounts"));
        celoLockedGold = ICeloLockedGold(celoRegistry.getAddressForStringOrDie("LockedGold"));
        celoElection = IElection(celoRegistry.getAddressForStringOrDie("Election"));
        celoValidators = ICeloValidators(celoRegistry.getAddressForStringOrDie("Validators"));
        celoEpochManager = ICeloEpochManager(
            celoRegistry.getAddressForStringOrDie("EpochManager")
        );
        celoGoldToken = IGoldToken(celoRegistry.getAddressForStringOrDie("GoldToken"));
        celoGovernance = ICeloGovernance(celoRegistry.getAddressForStringOrDie("Governance"));

        vm.label(address(celoAccounts), "Celo:Accounts");
        vm.label(address(celoLockedGold), "Celo:LockedGold");
        vm.label(address(celoElection), "Celo:Election");
        vm.label(address(celoValidators), "Celo:Validators");
        vm.label(address(celoEpochManager), "Celo:EpochManager");
        vm.label(address(celoGoldToken), "Celo:GoldToken");
        vm.label(address(celoGovernance), "Celo:Governance");

        (validatorLockedGoldRequirement, ) = celoValidators.getValidatorLockedGoldRequirements();
        (groupLockedGoldRequirement, ) = celoValidators.getGroupLockedGoldRequirements();

        devchainEpochNumber = celoEpochManager.getCurrentEpochNumber();
        syncEpochMock();
    }

    // =========================================================================
    //                               EPOCHS
    // =========================================================================

    /// @notice Re-apply the mocked epoch number so that EpochManager reports
    ///         `devchainEpochNumber` again.
    /// @dev Core contracts read the epoch number through EpochManager; pin it so tests
    ///      can advance epochs without running the (oracle dependent) epoch process.
    ///
    ///      Cheatcode state lives outside the EVM state a snapshot captures, so reverting to
    ///      a snapshot restores `devchainEpochNumber` (a storage variable) but leaves the
    ///      `vm.mockCall` installed by the last `mineToNextEpoch()` in place. A test that
    ///      reverts to a snapshot taken before `mineToNextEpoch()` must therefore call this
    ///      afterwards, otherwise the core contracts keep reporting the advanced epoch while
    ///      `devchainEpochNumber` says otherwise.
    function syncEpochMock() internal {
        dvm.mockCall(
            address(celoEpochManager),
            abi.encodeWithSelector(ICeloEpochManager.getCurrentEpochNumber.selector),
            abi.encode(devchainEpochNumber)
        );
        dvm.mockCall(
            address(celoEpochManager),
            abi.encodeWithSelector(ICeloEpochManager.getEpochNumberOfBlock.selector),
            abi.encode(devchainEpochNumber)
        );
    }

    /// @notice Advance to the next epoch (ports mineToNextEpoch from utils.ts).
    /// @dev Also mines BLOCKS_PER_EPOCH blocks with one second per block, which is what the
    ///      ganache devchain did when the Hardhat tests mined to the next epoch.
    function mineToNextEpoch() internal virtual override {
        devchainEpochNumber += 1;
        syncEpochMock();
        vm.roll(block.number + BLOCKS_PER_EPOCH);
        vm.warp(block.timestamp + BLOCKS_PER_EPOCH);
    }

    /// @notice Current epoch number as seen by the core contracts.
    function currentEpochNumber() internal view virtual override returns (uint256) {
        return devchainEpochNumber;
    }

    // =========================================================================
    //                           EPOCH REWARDS
    // =========================================================================

    /// @notice Distribute epoch rewards to `group` (ports distributeEpochRewards from utils.ts).
    /// @dev On L2 the caller must be EpochManager. The CELO backing the rewards is normally
    ///      released to LockedGold by the epoch process, so the same amount is credited here.
    function distributeEpochRewards(address group, uint256 amount) internal {
        (address lesser, address greater) = findLesserAndGreaterAfterVote(group, int256(amount));
        vm.deal(address(celoLockedGold), address(celoLockedGold).balance + amount);
        vm.prank(address(celoEpochManager));
        celoElection.distributeEpochRewards(group, amount, lesser, greater);
    }

    /// @notice Find the neighbours of `group` in the eligible groups list after changing its
    ///         votes by `delta` (ports ElectionWrapper.findLesserAndGreaterAfterVote).
    function findLesserAndGreaterAfterVote(address group, int256 delta)
        internal
        view
        returns (address lesser, address greater)
    {
        (address[] memory groups, uint256[] memory votes) = celoElection
            .getTotalVotesForEligibleValidatorGroups();

        // Signed on purpose: the account tasks ask for neighbours after revoking more
        // than the group currently holds, which ContractKit handled with BigNumber math.
        int256 total = delta;
        for (uint256 i = 0; i < groups.length; i++) {
            if (groups[i] == group) {
                total = int256(votes[i]) + delta;
                break;
            }
        }

        // The list is ordered from most to least votes.
        for (uint256 i = 0; i < groups.length; i++) {
            if (groups[i] == group) continue;
            if (int256(votes[i]) <= total) {
                lesser = groups[i];
                break;
            }
            greater = groups[i];
        }
    }

    // =========================================================================
    //                              WALLETS
    // =========================================================================

    /// @notice Create a wallet whose public key is known (needed for validator registration).
    function createWallet(uint256 initialBalance) internal returns (address addr) {
        _walletNonce++;
        DevchainVm.Wallet memory wallet = dvm.createWallet(
            string(abi.encodePacked("devchain-wallet-", vm.toString(_walletNonce)))
        );
        addr = wallet.addr;
        walletPublicKey[addr] = abi.encodePacked(wallet.publicKeyX, wallet.publicKeyY);
        walletPrivateKey[addr] = wallet.privateKey;
        if (initialBalance > 0) {
            vm.deal(addr, initialBalance);
        }
    }

    /// @notice Create a wallet with zero balance.
    function createWallet() internal returns (address) {
        return createWallet(0);
    }

    // =========================================================================
    //                         ACCOUNTS / LOCKED GOLD
    // =========================================================================

    /// @notice Register `account` on the core Accounts contract if not registered yet.
    function createCeloAccount(address account) internal {
        if (celoAccounts.isAccount(account)) return;
        vm.prank(account);
        celoAccounts.createAccount();
    }

    /// @notice Lock `amount` CELO for `account` (creating the Celo account if needed).
    function lockCelo(address account, uint256 amount) internal {
        createCeloAccount(account);
        if (account.balance < amount) {
            vm.deal(account, amount);
        }
        vm.prank(account);
        celoLockedGold.lock{value: amount}();
    }

    // =========================================================================
    //                    VALIDATOR REGISTRATION (utils-validators.ts)
    // =========================================================================

    /// @notice Locks the required CELO and registers `group` as a validator group.
    function registerValidatorGroup(address group, uint256 members) internal {
        createCeloAccount(group);
        lockCelo(group, groupLockedGoldRequirement * members);
        vm.prank(group);
        celoValidators.registerValidatorGroup(0);
    }

    /// @notice Locks the required CELO and registers `group` with a single member requirement.
    function registerValidatorGroup(address group) internal {
        registerValidatorGroup(group, 1);
    }

    /// @notice Registers `validator` (created with createWallet) and affiliates it to `group`.
    function registerValidatorAndOnlyAffiliateToGroup(address group, address validator) internal {
        bytes memory publicKey = walletPublicKey[validator];
        require(publicKey.length == 64, "validator must be created with createWallet()");

        createCeloAccount(validator);
        lockCelo(validator, validatorLockedGoldRequirement);

        vm.startPrank(validator);
        celoValidators.registerValidatorNoBls(publicKey);
        celoValidators.affiliate(group);
        vm.stopPrank();
    }

    /// @notice Registers `validator`, affiliates it and adds it to the members of `group`.
    function registerValidatorAndAddToGroupMembers(address group, address validator) internal {
        registerValidatorAndOnlyAffiliateToGroup(group, validator);
        addValidatorToGroupMembers(group, validator);
    }

    /// @notice Adds an affiliated validator to the members of `group`
    ///         (ports ValidatorsWrapper.addMember).
    function addValidatorToGroupMembers(address group, address validator) internal {
        uint256 numMembers = celoValidators.getGroupNumMembers(group);
        if (numMembers == 0) {
            // Resolve neighbours before pranking: a prank applies to the next call, which
            // would otherwise be the Election view call.
            (address lesser, address greater) = findLesserAndGreaterAfterVote(group, 0);
            vm.prank(group);
            celoValidators.addFirstMember(validator, lesser, greater);
        } else {
            vm.prank(group);
            celoValidators.addMember(validator);
        }
    }

    /// @notice Removes all members from `group`.
    function removeMembersFromGroup(address group) internal {
        (address[] memory members, , , , , , ) = celoValidators.getValidatorGroup(group);
        for (uint256 i = 0; i < members.length; i++) {
            vm.prank(group);
            celoValidators.removeMember(members[i]);
        }
    }

    /// @notice Removes members, waits out the locked gold requirement and deregisters `group`.
    function deregisterValidatorGroup(address group) internal {
        removeMembersFromGroup(group);
        (, uint256 duration) = celoValidators.getGroupLockedGoldRequirements();
        timeTravel(duration + 2 * DAY);

        address[] memory registered = celoValidators.getRegisteredValidatorGroups();
        uint256 index = type(uint256).max;
        for (uint256 i = 0; i < registered.length; i++) {
            if (registered[i] == group) {
                index = i;
                break;
            }
        }
        require(index != type(uint256).max, "group not registered");
        vm.prank(group);
        celoValidators.deregisterValidatorGroup(index);
    }

    /// @notice Authorizes a fresh validator signer for `validator`
    ///         (ports makeValidatorUseSigner from utils-validators.ts).
    function makeValidatorUseSigner(address validator) internal returns (address signer) {
        signer = createWallet();
        bytes32 message = keccak256(abi.encodePacked(validator));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        (uint8 v, bytes32 r, bytes32 s) = dvm.sign(walletPrivateKey[signer], digest);
        vm.prank(validator);
        celoAccounts.authorizeValidatorSignerWithPublicKey(
            signer,
            v,
            r,
            s,
            walletPublicKey[signer]
        );
    }

    // =========================================================================
    //                               VOTING
    // =========================================================================

    /// @notice Lock 1 CELO and vote for `group` (ports voteForGroup).
    function voteForGroup(address group, address voter) internal {
        voteForGroup(group, voter, 1 ether);
    }

    /// @notice Lock `amount` CELO and vote for `group`.
    function voteForGroup(
        address group,
        address voter,
        uint256 amount
    ) internal {
        lockCelo(voter, amount);
        (address lesser, address greater) = findLesserAndGreaterAfterVote(group, int256(amount));
        vm.prank(voter);
        celoElection.vote(group, amount, lesser, greater);
    }

    /// @notice Activate all activatable pending votes of `voter` (ports activateVotesForGroup).
    function activateVotesForGroup(address voter) internal {
        address[] memory groups = celoElection.getGroupsVotedForByAccount(voter);
        for (uint256 i = 0; i < groups.length; i++) {
            if (celoElection.hasActivatablePendingVotes(voter, groups[i])) {
                vm.prank(voter);
                celoElection.activate(groups[i]);
            }
        }
    }

    /// @notice Vote for `group`, move to the next epoch and activate (ports electGroup).
    function electGroup(address group, address voter) internal {
        voteForGroup(group, voter);
        mineToNextEpoch();
        activateVotesForGroup(voter);
    }

    // =========================================================================
    //                              SLASHING
    // =========================================================================

    /// @notice Halves the slashing multiplier of `group` through a mock slasher
    ///         (ports updateGroupSlashingMultiplier).
    function updateGroupSlashingMultiplier(address group, address mockSlasher) internal {
        vm.prank(celoRegistry.owner());
        celoRegistry.setAddressFor("MockSlasher", mockSlasher);

        vm.prank(celoLockedGold.owner());
        celoLockedGold.addSlasher("MockSlasher");

        vm.prank(mockSlasher);
        celoValidators.halveSlashingMultiplier(group);

        mineToNextEpoch();
    }

    // =========================================================================
    //                        MOCK GROUP HEALTH ELECTION
    // =========================================================================

    /// @notice Marks the members of `validatorGroups` as elected on MockGroupHealth
    ///         (ports electMockValidatorGroupsAndUpdate).
    function electMockValidatorGroupsAndUpdate(
        MockGroupHealth groupHealth,
        address[] memory validatorGroups,
        bool revoke,
        bool update,
        bool makeOneValidatorGroupUseSigner
    ) internal returns (uint256[] memory mockedIndexes) {
        uint256 validatorsProcessed = 0;
        uint256 total = 0;
        for (uint256 j = 0; j < validatorGroups.length; j++) {
            if (celoValidators.isValidatorGroup(validatorGroups[j])) {
                total += celoValidators.getGroupNumMembers(validatorGroups[j]);
            }
        }
        mockedIndexes = new uint256[](total);

        for (uint256 j = 0; j < validatorGroups.length; j++) {
            address validatorGroup = validatorGroups[j];
            if (celoValidators.isValidatorGroup(validatorGroup)) {
                (address[] memory members, , , , , , ) = celoValidators.getValidatorGroup(
                    validatorGroup
                );
                for (uint256 i = 0; i < members.length; i++) {
                    address signer = makeOneValidatorGroupUseSigner
                        ? makeValidatorUseSigner(members[i])
                        : members[i];
                    uint256 mockIndex = validatorsProcessed++;
                    groupHealth.setElectedValidator(mockIndex, revoke ? ADDRESS_ZERO : signer);
                    mockedIndexes[mockIndex] = mockIndex;
                }
            }
            if (update) {
                groupHealth.updateGroupHealth(validatorGroup);
            }
            makeOneValidatorGroupUseSigner = false;
        }
    }

    /// @notice electMockValidatorGroupsAndUpdate with revoke=false, update=true,
    ///         makeOneValidatorGroupUseSigner=true (the TS defaults).
    function electMockValidatorGroupsAndUpdate(
        MockGroupHealth groupHealth,
        address[] memory validatorGroups
    ) internal returns (uint256[] memory) {
        return electMockValidatorGroupsAndUpdate(groupHealth, validatorGroups, false, true, true);
    }

    /// @notice Revoke the election of the members of `validatorGroups` on MockGroupHealth.
    function revokeElectionOnMockValidatorGroupsAndUpdate(
        MockGroupHealth groupHealth,
        address[] memory validatorGroups,
        bool update
    ) internal {
        revokeElectionOnMockValidatorGroupsAndUpdate(
            IValidators(address(celoValidators)),
            celoAccounts,
            groupHealth,
            validatorGroups,
            update
        );
    }

    // =========================================================================
    //                              OVERFLOW
    // =========================================================================

    /// @notice Lock and vote with `voter` so that the first three groups have exactly
    ///         40, 100 and 200 CELO of receivable votes left (ports prepareOverflow).
    /// @dev The Hardhat version hardcoded vote amounts derived for the ganache devchain. The
    ///      receivable votes of a group are `totalLockedGold * (members + 1) / N` where N is
    ///      the number of electable validators, so the amounts are solved for the current
    ///      chain state instead.
    function prepareOverflow(
        DefaultStrategy defaultStrategy,
        address voter,
        address[] memory groupAddresses,
        bool activateGroups
    ) internal {
        require(groupAddresses.length >= 3, "It is necessary to provide at least 3 groups");
        uint256[3] memory remaining = [uint256(40 ether), uint256(100 ether), uint256(200 ether)];

        if (activateGroups) {
            address dsOwner = defaultStrategy.owner();
            for (uint256 i = 3; i > 0; i--) {
                (address head, ) = defaultStrategy.getGroupsHead();
                vm.startPrank(dsOwner);
                defaultStrategy.addActivatableGroup(groupAddresses[i - 1]);
                defaultStrategy.activateGroup(groupAddresses[i - 1], ADDRESS_ZERO, head);
                vm.stopPrank();
            }
        }

        createCeloAccount(voter);
        uint256 toLock = _overflowLockAmount(groupAddresses, remaining);
        lockCelo(voter, toLock);

        // Voting limits depend on the total locked CELO, so votes are computed after locking.
        uint256[3] memory votes;
        uint256 sum = 0;
        for (uint256 i = 0; i < 3; i++) {
            uint256 cap = celoElection.getNumVotesReceivable(groupAddresses[i]);
            uint256 current = celoElection.getTotalVotesForGroup(groupAddresses[i]);
            require(cap >= current + remaining[i], "overflow: cap too small");
            votes[i] = cap - current - remaining[i];
            sum += votes[i];
        }
        if (sum > toLock) {
            lockCelo(voter, sum - toLock);
        }
        for (uint256 i = 0; i < 3; i++) {
            (address lesser, address greater) = findLesserAndGreaterAfterVote(
                groupAddresses[i],
                int256(votes[i])
            );
            vm.prank(voter);
            celoElection.vote(groupAddresses[i], votes[i], lesser, greater);
        }
    }

    /// @notice prepareOverflow with activateGroups=true.
    function prepareOverflow(
        DefaultStrategy defaultStrategy,
        address voter,
        address[] memory groupAddresses
    ) internal {
        prepareOverflow(defaultStrategy, voter, groupAddresses, true);
    }

    /// @dev Solve `L >= (T0 + L) * S / N - c` for the CELO the voter has to lock, where S is
    ///      the sum of (members + 1) over the three groups and c the votes not to be cast.
    function _overflowLockAmount(address[] memory groupAddresses, uint256[3] memory remaining)
        private
        view
        returns (uint256)
    {
        uint256 totalLocked = celoLockedGold.getTotalLockedGold();
        (, uint256 maxElectable) = celoElection.getElectableValidators();
        uint256 registered = celoValidators.getNumRegisteredValidators();
        uint256 n = maxElectable < registered ? maxElectable : registered;

        uint256 s = 0;
        uint256 c = 0;
        for (uint256 i = 0; i < 3; i++) {
            s += celoValidators.getGroupNumMembers(groupAddresses[i]) + 1;
            c += remaining[i] + celoElection.getTotalVotesForGroup(groupAddresses[i]);
        }
        require(n > s, "overflow: not enough electable validators");
        uint256 numerator = totalLocked * s;
        if (numerator <= c * n) return 1 ether;
        // Round up and add a small margin for integer division inside Election.
        return (numerator - c * n + (n - s) - 1) / (n - s) + 1 ether;
    }

    // =========================================================================
    //                            MISCELLANEOUS
    // =========================================================================

    /// @notice Allow `accountAddress` to vote for more than maxNumGroupsVotedFor groups
    ///         (ports updateMaxNumberOfGroups).
    function updateMaxNumberOfGroups(address accountAddress, bool updateValue) internal {
        vm.deal(accountAddress, accountAddress.balance + 1 ether);
        createCeloAccount(accountAddress);
        vm.prank(accountAddress);
        celoElection.setAllowedToVoteOverMaxNumberOfGroups(updateValue);
    }

    /// @notice Set the number of concurrent governance proposals
    ///         (ports setGovernanceConcurrentProposals).
    function setGovernanceConcurrentProposals(uint256 count) internal {
        vm.prank(celoGovernance.owner());
        celoGovernance.setConcurrentProposals(count);
    }

    /// @notice Upgrade the GroupHealth proxy owned by the MultiSig to MockGroupHealth
    ///         (ports upgradeToMockGroupHealthE2E).
    function upgradeToMockGroupHealthE2E(
        IMultiSig multiSig,
        address multisigOwner,
        address groupHealthProxy
    ) internal returns (MockGroupHealth) {
        vm.prank(multisigOwner);
        MockGroupHealth implementation = new MockGroupHealth();

        address[] memory destinations = new address[](1);
        destinations[0] = groupHealthProxy;
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("upgradeTo(address)", address(implementation));
        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner);

        return MockGroupHealth(groupHealthProxy);
    }
}
