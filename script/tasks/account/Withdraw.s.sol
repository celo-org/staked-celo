// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/AccountTaskLib.sol";

/**
 * @title WithdrawScript
 * @notice Withdraws CELO from the Account contract. Replaces
 *         `yarn hardhat stakedCelo:account:withdraw --beneficiary <address>`.
 *
 * Environment variables:
 *   BENEFICIARY  required. The address of the beneficiary to withdraw for.
 *   NETWORK      optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   BENEFICIARY=0x... forge script script/tasks/account/Withdraw.s.sol \
 *     --rpc-url celo --broadcast --ledger --sender <ledger address>
 */
contract WithdrawScript is TaskBase {
    /// @notice Reads BENEFICIARY from the environment and withdraws for it.
    function run() external {
        IAccountTask account = accountContract();
        IDefaultStrategyTask defaultStrategy = defaultStrategyContract();
        ISpecificGroupStrategyTask specificGroupStrategy = specificGroupStrategyContract();
        IElectionLookup electionContract = election();
        address beneficiary = vm.envAddress("BENEFICIARY");

        vm.startBroadcast();
        execute(account, defaultStrategy, specificGroupStrategy, electionContract, beneficiary);
        vm.stopBroadcast();
    }

    /**
     * @notice Runs the withdraw task against the given contracts.
     * @param account The StakedCelo Account contract.
     * @param defaultStrategy The DefaultStrategy contract.
     * @param specificGroupStrategy The SpecificGroupStrategy contract.
     * @param electionContract The Celo Election contract.
     * @param beneficiary The address the withdrawal was scheduled for.
     */
    function execute(
        IAccountTask account,
        IDefaultStrategyTask defaultStrategy,
        ISpecificGroupStrategyTask specificGroupStrategy,
        IElectionLookup electionContract,
        address beneficiary
    ) internal {
        AccountTaskLib.withdraw(
            account, defaultStrategy, specificGroupStrategy, electionContract, beneficiary
        );
    }
}
