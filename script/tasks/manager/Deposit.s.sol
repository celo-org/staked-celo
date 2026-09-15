// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/ManagerTaskLib.sol";

/**
 * @title DepositScript
 * @notice Deposits CELO in the staked CELO protocol. Replaces
 *         `yarn hardhat stakedCelo:manager:deposit --amount <wei>`.
 *
 * Environment variables:
 *   AMOUNT   required. The amount of CELO to deposit, in wei.
 *   NETWORK  optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   AMOUNT=1000000000000000000 forge script script/tasks/manager/Deposit.s.sol \
 *     --rpc-url celo --broadcast --ledger --sender <ledger address>
 */
contract DepositScript is TaskBase {
    /// @notice Reads AMOUNT from the environment and deposits as the broadcaster.
    function run() external {
        IManagerTask manager = managerContract();
        uint256 amount = vm.envUint("AMOUNT");

        vm.startBroadcast();
        execute(manager, amount);
        vm.stopBroadcast();
    }

    /// @notice Deposits `amount` CELO into the protocol.
    /// @param manager The Manager contract.
    /// @param amount The amount of CELO to deposit, in wei.
    function execute(IManagerTask manager, uint256 amount) internal {
        ManagerTaskLib.deposit(manager, amount);
    }
}
