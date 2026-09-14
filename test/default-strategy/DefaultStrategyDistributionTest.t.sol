// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./DefaultStrategyTestBase.sol";

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
 * @title DefaultStrategyDistributionTest
 * @notice Ports the vote distribution describe blocks of `test-ts/default-strategy.test.ts`:
 *         `#generateDepositVoteDistribution`, `#generateWithdrawalVoteDistribution` and
 *         `V1 -> V2 migration test`.
 */
contract DefaultStrategyDistributionTest is DefaultStrategyTestBase {
    /// @dev The V1 accounting the migration test starts from.
    uint256[3] internal migrationVotes = [uint256(95_824 ether), uint256(0), uint256(95_664 ether)];

    function setUp() public {
        _deployDefaultStrategyFixture();
    }

    /// @dev `.to.emit(defaultStrategyContract, name)` without `withArgs`: only the event
    ///      signature and the emitter are checked.
    function _expectEventFromStrategy() private {
        IVmExpectEmitFrom(address(vm)).expectEmit(
            false,
            false,
            false,
            false,
            address(mockDefaultStrategy)
        );
    }

    // =========================================================================
    //                  #generateDepositVoteDistribution
    // =========================================================================

    function test_generateDepositVoteDistribution_CannotBeCalledByANonManagerAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DefaultStrategy.CallerNotManagerNorStrategy.selector,
                nonManager
            )
        );
        vm.prank(nonManager);
        mockDefaultStrategy.generateDepositVoteDistribution(10, 10, ADDRESS_ZERO);
    }

    function test_generateDepositVoteDistribution_WhenCalledThroughManagerDeposit_EmitsDepositVoteDistributionGeneratedEvent()
        public
    {
        _activateGroupsFromPrevious(3);

        _expectEventFromStrategy();
        emit DepositVoteDistributionGenerated(new address[](0), new uint256[](0));
        manager.deposit{value: 100}();
    }

    // =========================================================================
    //                #generateWithdrawalVoteDistribution
    // =========================================================================

    function test_generateWithdrawalVoteDistribution_CannotBeCalledByANonManagerAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DefaultStrategy.CallerNotManagerNorStrategy.selector,
                nonManager
            )
        );
        vm.prank(nonManager);
        mockDefaultStrategy.generateWithdrawalVoteDistribution(10);
    }

    function test_generateWithdrawalVoteDistribution_WhenCalledThroughManagerWithdraw_EmitsWithdrawalVoteDistributionGeneratedEvent()
        public
    {
        _activateGroupsFromPrevious(3);
        // Deposit first so we have something to withdraw.
        manager.deposit{value: 300}();
        _updateGroupCelo();

        _expectEventFromStrategy();
        emit WithdrawalVoteDistributionGenerated(new address[](0), new uint256[](0));
        manager.withdraw(100);
    }

    // =========================================================================
    //                       V1 -> V2 migration test
    // =========================================================================

    /// @dev `describe("V1 -> V2 migration test")` beforeEach.
    function _setUpMigration() private {
        for (uint256 i = 0; i < 3; i++) {
            mockDefaultStrategy.addToStrategyTotalStCeloVotesPublic(
                groupAddresses[i],
                migrationVotes[i]
            );
        }
    }

    function test_V1ToV2MigrationTest_ShouldSetCorrectAccountingForGroup0() public {
        _setUpMigration();

        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[0]);
        vm.prank(owner);
        mockDefaultStrategy.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);

        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[0]), migrationVotes[0]);
    }

    function test_V1ToV2MigrationTest_ShouldSetCorrectAccountingForGroupThatHas0CeloLocked()
        public
    {
        _setUpMigration();

        vm.prank(owner);
        mockDefaultStrategy.addActivatableGroup(groupAddresses[1]);
        vm.prank(owner);
        mockDefaultStrategy.activateGroup(groupAddresses[1], ADDRESS_ZERO, ADDRESS_ZERO);

        assertEq(defaultStrategy.stCeloInGroup(groupAddresses[1]), 0);
    }
}
