// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/ManagerTaskLib.sol";

/**
 * @title WithdrawScript
 * @notice Withdraws stCELO from the staked CELO protocol. Replaces
 *         `yarn hardhat stakedCelo:manager:withdraw --amount <wei>`.
 *
 * Environment variables:
 *   AMOUNT   required. The amount of stCELO to withdraw, in wei.
 *   NETWORK  optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   AMOUNT=1000000000000000000 forge script script/tasks/manager/Withdraw.s.sol \
 *     --rpc-url celo --broadcast --ledger
 */
contract WithdrawScript is TaskBase {
    /// @notice Reads AMOUNT from the environment and withdraws as the broadcaster.
    function run() external {
        IManagerTask manager = managerContract();
        uint256 amount = vm.envUint("AMOUNT");

        vm.startBroadcast();
        execute(manager, amount);
        vm.stopBroadcast();
    }

    /// @notice Withdraws `amount` stCELO from the protocol.
    /// @param manager The Manager contract.
    /// @param amount The amount of stCELO to withdraw, in wei.
    function execute(IManagerTask manager, uint256 amount) internal {
        ManagerTaskLib.withdraw(manager, amount);
    }
}
