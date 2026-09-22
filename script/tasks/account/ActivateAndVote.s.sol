// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/AccountTaskLib.sol";

/**
 * @title ActivateAndVoteScript
 * @notice Activate CELO and vote for validator groups. Replaces
 *         `yarn hardhat stakedCelo:account:activateAndVote`.
 *
 * Environment variables:
 *   NETWORK  optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   forge script script/tasks/account/ActivateAndVote.s.sol --rpc-url celo \
 *     --broadcast --ledger --sender <ledger address>
 */
contract ActivateAndVoteScript is TaskBase {
    /// @notice Activates and votes for every group the protocol is voting for.
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
     * @notice Runs the activateAndVote task against the given contracts.
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
        AccountTaskLib.activateAndVote(
            account, defaultStrategy, specificGroupStrategy, electionContract
        );
    }
}
