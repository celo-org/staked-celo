// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/AccountTaskLib.sol";

/**
 * @title FinishPendingWithdrawalScript
 * @notice Finishes the pending withdrawals created by a `withdraw` call. Replaces
 *         `yarn hardhat stakedCelo:account:finishPendingWithdrawal --beneficiary <address>`.
 *
 * Environment variables:
 *   BENEFICIARY  required. The address of the beneficiary to withdraw for.
 *   NETWORK      optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   BENEFICIARY=0x... forge script script/tasks/account/FinishPendingWithdrawal.s.sol \
 *     --rpc-url celo --broadcast --ledger --sender <ledger address>
 */
contract FinishPendingWithdrawalScript is TaskBase {
    /// @notice Reads BENEFICIARY from the environment and finishes its released withdrawals.
    function run() external {
        IAccountTask account = accountContract();
        ILockedGoldLookup lockedGoldContract = lockedGold();
        address beneficiary = vm.envAddress("BENEFICIARY");

        vm.startBroadcast();
        execute(account, lockedGoldContract, beneficiary);
        vm.stopBroadcast();
    }

    /**
     * @notice Runs the finishPendingWithdrawal task against the given contracts.
     * @param account The StakedCelo Account contract.
     * @param lockedGoldContract The Celo LockedGold contract.
     * @param beneficiary The address the pending withdrawals belong to.
     */
    function execute(
        IAccountTask account,
        ILockedGoldLookup lockedGoldContract,
        address beneficiary
    ) internal {
        TaskConsole.log(
            "number of pending withdrawals:", account.getNumberPendingWithdrawals(beneficiary)
        );
        AccountTaskLib.finishPendingWithdrawals(account, lockedGoldContract, beneficiary);
    }
}
