// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/deploy/CoreDeployHelper.sol";
import "./helpers/MultiSigHelper.sol";

/**
 * @title ProxyDeployTest
 * @notice Tests that all protocol contracts are properly deployed behind proxies
 *         with correct ownership and upgrade capabilities.
 * @dev Migrated from test-ts/proxy-deploy.test.ts
 *      Tests 8 contracts (StakedCelo, Account, Manager, RebasedStakedCelo,
 *      Vote, DefaultStrategy, SpecificGroupStrategy, GroupHealth) with 6 test
 *      scenarios each (56 total test functions).
 */
contract ProxyDeployTest is MultiSigHelper, CoreDeployHelper {
    // ERC1967 implementation slot
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal nonOwner;

    function setUp() public {
        // The original fixture set TIME_LOCK_MIN_DELAY, TIME_LOCK_DELAY and
        // MULTISIG_REQUIRED_CONFIRMATIONS to 1 before deploying.
        deployCoreWithMockRegistry(1, 1, 1);
        nonOwner = randomAddress();
    }

    // =========================================================================
    //                        STAKED CELO TESTS
    // =========================================================================

    function test_StakedCelo_implCannotBeInitialized() public {
        address impl = _getImplementation(address(stakedCelo));
        StakedCelo implContract = StakedCelo(payable(impl));

        vm.expectRevert("Initializable: contract is already initialized");
        implContract.initialize(randomAddress(), randomAddress());
    }

    function test_StakedCelo_isOwnedByMultiSig() public {
        assertEq(stakedCelo.owner(), multiSigProxy);
    }

    function test_StakedCelo_proxyAddressNotEqualImplementation() public {
        address impl = _getImplementation(address(stakedCelo));
        assertNotEq(impl, ADDRESS_ZERO);
        assertNotEq(address(stakedCelo), impl);
    }

    function test_StakedCelo_canTransferOwnershipViaMultiSig() public {
        address newOwner = randomAddress();

        address[] memory destinations = new address[](1);
        destinations[0] = address(stakedCelo);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transferOwnership(address)", newOwner);

        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        assertEq(stakedCelo.owner(), newOwner);
    }

    function test_StakedCelo_canUpdateImplementationViaMultiSig() public {
        StakedCelo newImpl = new StakedCelo();

        _upgradeViaMultiSig(address(stakedCelo), address(newImpl));

        // Verify implementation was updated
        assertEq(_getImplementation(address(stakedCelo)), address(newImpl));
    }

    function test_StakedCelo_nonOwnerCannotTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        stakedCelo.transferOwnership(nonOwner);
    }

    function test_StakedCelo_nonOwnerCannotUpgrade() public {
        StakedCelo newImpl = new StakedCelo();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        stakedCelo.upgradeTo(address(newImpl));
    }

    // =========================================================================
    //                        ACCOUNT TESTS
    // =========================================================================

    function test_Account_implCannotBeInitialized() public {
        address impl = _getImplementation(address(account));
        Account implContract = Account(payable(impl));

        vm.expectRevert("Initializable: contract is already initialized");
        implContract.initialize(randomAddress(), randomAddress(), randomAddress());
    }

    function test_Account_isOwnedByMultiSig() public {
        assertEq(account.owner(), multiSigProxy);
    }

    function test_Account_proxyAddressNotEqualImplementation() public {
        address impl = _getImplementation(address(account));
        assertNotEq(impl, ADDRESS_ZERO);
        assertNotEq(address(account), impl);
    }

    function test_Account_canTransferOwnershipViaMultiSig() public {
        address newOwner = randomAddress();

        address[] memory destinations = new address[](1);
        destinations[0] = address(account);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transferOwnership(address)", newOwner);

        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        assertEq(account.owner(), newOwner);
    }

    function test_Account_canUpdateImplementationViaMultiSig() public {
        Account newImpl = new Account();

        _upgradeViaMultiSig(address(account), address(newImpl));

        // Verify implementation was updated
        assertEq(_getImplementation(address(account)), address(newImpl));
    }

    function test_Account_nonOwnerCannotTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        account.transferOwnership(nonOwner);
    }

    function test_Account_nonOwnerCannotUpgrade() public {
        Account newImpl = new Account();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        account.upgradeTo(address(newImpl));
    }

    // =========================================================================
    //                        MANAGER TESTS
    // =========================================================================

    function test_Manager_implCannotBeInitialized() public {
        address impl = _getImplementation(address(manager));
        Manager implContract = Manager(payable(impl));

        vm.expectRevert("Initializable: contract is already initialized");
        implContract.initialize(randomAddress(), randomAddress());
    }

    function test_Manager_isOwnedByMultiSig() public {
        assertEq(manager.owner(), multiSigProxy);
    }

    function test_Manager_proxyAddressNotEqualImplementation() public {
        address impl = _getImplementation(address(manager));
        assertNotEq(impl, ADDRESS_ZERO);
        assertNotEq(address(manager), impl);
    }

    function test_Manager_canTransferOwnershipViaMultiSig() public {
        address newOwner = randomAddress();

        address[] memory destinations = new address[](1);
        destinations[0] = address(manager);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transferOwnership(address)", newOwner);

        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        assertEq(manager.owner(), newOwner);
    }

    function test_Manager_canUpdateImplementationViaMultiSig() public {
        Manager newImpl = new Manager();

        _upgradeViaMultiSig(address(manager), address(newImpl));

        // Verify implementation was updated
        assertEq(_getImplementation(address(manager)), address(newImpl));
    }

    function test_Manager_nonOwnerCannotTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        manager.transferOwnership(nonOwner);
    }

    function test_Manager_nonOwnerCannotUpgrade() public {
        Manager newImpl = new Manager();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        manager.upgradeTo(address(newImpl));
    }

    // =========================================================================
    //                        REBASED STAKED CELO TESTS
    // =========================================================================

    function test_RebasedStakedCelo_implCannotBeInitialized() public {
        address impl = _getImplementation(address(rebasedStakedCelo));
        RebasedStakedCelo implContract = RebasedStakedCelo(payable(impl));

        vm.expectRevert("Initializable: contract is already initialized");
        implContract.initialize(randomAddress(), randomAddress(), randomAddress());
    }

    function test_RebasedStakedCelo_isOwnedByMultiSig() public {
        assertEq(rebasedStakedCelo.owner(), multiSigProxy);
    }

    function test_RebasedStakedCelo_proxyAddressNotEqualImplementation() public {
        address impl = _getImplementation(address(rebasedStakedCelo));
        assertNotEq(impl, ADDRESS_ZERO);
        assertNotEq(address(rebasedStakedCelo), impl);
    }

    function test_RebasedStakedCelo_canTransferOwnershipViaMultiSig() public {
        address newOwner = randomAddress();

        address[] memory destinations = new address[](1);
        destinations[0] = address(rebasedStakedCelo);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transferOwnership(address)", newOwner);

        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        assertEq(rebasedStakedCelo.owner(), newOwner);
    }

    function test_RebasedStakedCelo_canUpdateImplementationViaMultiSig() public {
        RebasedStakedCelo newImpl = new RebasedStakedCelo();

        _upgradeViaMultiSig(address(rebasedStakedCelo), address(newImpl));

        // Verify implementation was updated
        assertEq(_getImplementation(address(rebasedStakedCelo)), address(newImpl));
    }

    function test_RebasedStakedCelo_nonOwnerCannotTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        rebasedStakedCelo.transferOwnership(nonOwner);
    }

    function test_RebasedStakedCelo_nonOwnerCannotUpgrade() public {
        RebasedStakedCelo newImpl = new RebasedStakedCelo();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        rebasedStakedCelo.upgradeTo(address(newImpl));
    }

    // =========================================================================
    //                        VOTE TESTS
    // =========================================================================

    function test_Vote_implCannotBeInitialized() public {
        address impl = _getImplementation(address(vote));
        Vote implContract = Vote(payable(impl));

        vm.expectRevert("Initializable: contract is already initialized");
        implContract.initialize(randomAddress(), randomAddress(), randomAddress());
    }

    function test_Vote_isOwnedByMultiSig() public {
        assertEq(vote.owner(), multiSigProxy);
    }

    function test_Vote_proxyAddressNotEqualImplementation() public {
        address impl = _getImplementation(address(vote));
        assertNotEq(impl, ADDRESS_ZERO);
        assertNotEq(address(vote), impl);
    }

    function test_Vote_canTransferOwnershipViaMultiSig() public {
        address newOwner = randomAddress();

        address[] memory destinations = new address[](1);
        destinations[0] = address(vote);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transferOwnership(address)", newOwner);

        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        assertEq(vote.owner(), newOwner);
    }

    function test_Vote_canUpdateImplementationViaMultiSig() public {
        Vote newImpl = new Vote();

        _upgradeViaMultiSig(address(vote), address(newImpl));

        // Verify implementation was updated
        assertEq(_getImplementation(address(vote)), address(newImpl));
    }

    function test_Vote_nonOwnerCannotTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        vote.transferOwnership(nonOwner);
    }

    function test_Vote_nonOwnerCannotUpgrade() public {
        Vote newImpl = new Vote();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        vote.upgradeTo(address(newImpl));
    }

    // =========================================================================
    //                        DEFAULT STRATEGY TESTS
    // =========================================================================

    function test_DefaultStrategy_implCannotBeInitialized() public {
        address impl = _getImplementation(address(defaultStrategy));
        DefaultStrategy implContract = DefaultStrategy(payable(impl));

        vm.expectRevert("Initializable: contract is already initialized");
        implContract.initialize(randomAddress(), randomAddress());
    }

    function test_DefaultStrategy_isOwnedByMultiSig() public {
        assertEq(defaultStrategy.owner(), multiSigProxy);
    }

    function test_DefaultStrategy_proxyAddressNotEqualImplementation() public {
        address impl = _getImplementation(address(defaultStrategy));
        assertNotEq(impl, ADDRESS_ZERO);
        assertNotEq(address(defaultStrategy), impl);
    }

    function test_DefaultStrategy_canTransferOwnershipViaMultiSig() public {
        address newOwner = randomAddress();

        address[] memory destinations = new address[](1);
        destinations[0] = address(defaultStrategy);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transferOwnership(address)", newOwner);

        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        assertEq(defaultStrategy.owner(), newOwner);
    }

    function test_DefaultStrategy_canUpdateImplementationViaMultiSig() public {
        DefaultStrategy newImpl = new DefaultStrategy();

        _upgradeViaMultiSig(address(defaultStrategy), address(newImpl));

        // Verify implementation was updated
        assertEq(_getImplementation(address(defaultStrategy)), address(newImpl));
    }

    function test_DefaultStrategy_nonOwnerCannotTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        defaultStrategy.transferOwnership(nonOwner);
    }

    function test_DefaultStrategy_nonOwnerCannotUpgrade() public {
        DefaultStrategy newImpl = new DefaultStrategy();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        defaultStrategy.upgradeTo(address(newImpl));
    }

    // =========================================================================
    //                        SPECIFIC GROUP STRATEGY TESTS
    // =========================================================================

    function test_SpecificGroupStrategy_implCannotBeInitialized() public {
        address impl = _getImplementation(address(specificGroupStrategy));
        SpecificGroupStrategy implContract = SpecificGroupStrategy(payable(impl));

        vm.expectRevert("Initializable: contract is already initialized");
        implContract.initialize(randomAddress(), randomAddress());
    }

    function test_SpecificGroupStrategy_isOwnedByMultiSig() public {
        assertEq(specificGroupStrategy.owner(), multiSigProxy);
    }

    function test_SpecificGroupStrategy_proxyAddressNotEqualImplementation() public {
        address impl = _getImplementation(address(specificGroupStrategy));
        assertNotEq(impl, ADDRESS_ZERO);
        assertNotEq(address(specificGroupStrategy), impl);
    }

    function test_SpecificGroupStrategy_canTransferOwnershipViaMultiSig() public {
        address newOwner = randomAddress();

        address[] memory destinations = new address[](1);
        destinations[0] = address(specificGroupStrategy);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transferOwnership(address)", newOwner);

        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        assertEq(specificGroupStrategy.owner(), newOwner);
    }

    function test_SpecificGroupStrategy_canUpdateImplementationViaMultiSig() public {
        SpecificGroupStrategy newImpl = new SpecificGroupStrategy();

        _upgradeViaMultiSig(address(specificGroupStrategy), address(newImpl));

        // Verify implementation was updated
        assertEq(_getImplementation(address(specificGroupStrategy)), address(newImpl));
    }

    function test_SpecificGroupStrategy_nonOwnerCannotTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        specificGroupStrategy.transferOwnership(nonOwner);
    }

    function test_SpecificGroupStrategy_nonOwnerCannotUpgrade() public {
        SpecificGroupStrategy newImpl = new SpecificGroupStrategy();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        specificGroupStrategy.upgradeTo(address(newImpl));
    }

    // =========================================================================
    //                        GROUP HEALTH TESTS
    // =========================================================================

    function test_GroupHealth_implCannotBeInitialized() public {
        address impl = _getImplementation(address(groupHealth));
        GroupHealth implContract = GroupHealth(payable(impl));

        vm.expectRevert("Initializable: contract is already initialized");
        implContract.initialize(randomAddress(), randomAddress());
    }

    function test_GroupHealth_isOwnedByMultiSig() public {
        assertEq(groupHealth.owner(), multiSigProxy);
    }

    function test_GroupHealth_proxyAddressNotEqualImplementation() public {
        address impl = _getImplementation(address(groupHealth));
        assertNotEq(impl, ADDRESS_ZERO);
        assertNotEq(address(groupHealth), impl);
    }

    function test_GroupHealth_canTransferOwnershipViaMultiSig() public {
        address newOwner = randomAddress();

        address[] memory destinations = new address[](1);
        destinations[0] = address(groupHealth);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transferOwnership(address)", newOwner);

        submitAndExecuteMultiSigProposal(multiSig, destinations, values, payloads, multisigOwner0);

        assertEq(groupHealth.owner(), newOwner);
    }

    function test_GroupHealth_canUpdateImplementationViaMultiSig() public {
        GroupHealth newImpl = new GroupHealth();

        _upgradeViaMultiSig(address(groupHealth), address(newImpl));

        // Verify implementation was updated
        assertEq(_getImplementation(address(groupHealth)), address(newImpl));
    }

    function test_GroupHealth_nonOwnerCannotTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        groupHealth.transferOwnership(nonOwner);
    }

    function test_GroupHealth_nonOwnerCannotUpgrade() public {
        GroupHealth newImpl = new GroupHealth();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwner);
        groupHealth.upgradeTo(address(newImpl));
    }

    // =========================================================================
    //                        HELPER FUNCTIONS
    // =========================================================================

    /// @dev Upgrade a proxy through the MultiSig, asserting that the proxy emits Upgraded.
    ///      Same steps as MultiSigHelper.submitAndExecuteMultiSigProposal, spelled out here
    ///      so that the event expectation sits on the execution rather than the submission:
    ///      submitProposal emits ProposalScheduled, which would consume the expectation.
    function _upgradeViaMultiSig(address proxy, address newImpl) internal {
        address[] memory destinations = new address[](1);
        destinations[0] = proxy;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("upgradeTo(address)", newImpl);

        vm.prank(multisigOwner0);
        uint256 proposalId = multiSig.submitProposal(destinations, values, payloads);

        vm.warp(block.timestamp + multiSig.delay() + 1);

        vm.expectEmit(true, false, false, false, proxy);
        emit Upgraded(newImpl);
        vm.prank(multisigOwner0);
        multiSig.executeProposal(proposalId);
    }

    /// @dev Get the implementation address from a proxy using ERC1967 slot
    function _getImplementation(address proxy) internal view returns (address impl) {
        bytes32 implSlot = vm.load(proxy, IMPL_SLOT);
        impl = address(uint160(uint256(implSlot)));
    }

    // =========================================================================
    //                        EVENTS
    // =========================================================================

    event Upgraded(address indexed implementation);
}
