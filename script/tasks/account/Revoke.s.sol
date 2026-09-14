// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/AccountTaskLib.sol";

/**
 * @title RevokeScript
 * @notice Revokes votes from validator groups. Replaces
 *         `yarn hardhat stakedCelo:account:revoke`.
 *
 * Environment variables:
 *   NETWORK  optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   forge script script/tasks/account/Revoke.s.sol --rpc-url celo --broadcast --ledger
 */
contract RevokeScript is TaskBase {
    /// @notice Revokes the scheduled votes of every group the protocol is voting for.
    function run() external {
        IAccountTask account = accountContract();
        IDefaultStrategyTask defaultStrategy = defaultStrategyContract();
        ISpecificGroupStrategyTask specificGroupStrategy = specificGroupStrategyContract();
        IElectionLookup electionContract = election();

        vm.startBroadcast();
        execute(account, defaultStrategy, specificGroupStrategy, electionContract);
        vm.stopBroadcast();
    }

    /**
     * @notice Runs the revoke task against the given contracts.
     * @param account The StakedCelo Account contract.
     * @param defaultStrategy The DefaultStrategy contract.
     * @param specificGroupStrategy The SpecificGroupStrategy contract.
     * @param electionContract The Celo Election contract.
     */
    function execute(
        IAccountTask account,
        IDefaultStrategyTask defaultStrategy,
        ISpecificGroupStrategyTask specificGroupStrategy,
        IElectionLookup electionContract
    ) internal {
        AccountTaskLib.revoke(account, defaultStrategy, specificGroupStrategy, electionContract);
    }
}
