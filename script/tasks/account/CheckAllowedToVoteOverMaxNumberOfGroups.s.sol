// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";

/**
 * @title CheckAllowedToVoteOverMaxNumberOfGroupsScript
 * @notice Checks if the Account contract may vote for more than the maximum number of
 *         groups. Replaces `yarn hardhat stakedCelo:account:voteOverMax`.
 *
 * Environment variables:
 *   NETWORK  optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   forge script script/tasks/account/CheckAllowedToVoteOverMaxNumberOfGroups.s.sol \
 *     --rpc-url celo
 */
contract CheckAllowedToVoteOverMaxNumberOfGroupsScript is TaskBase {
    /// @notice Prints the Election flag for the deployed Account contract.
    function run() external view {
        execute(election(), address(accountContract()));
    }

    /// @notice Prints whether `accountAddress` may vote over the maximum number of groups.
    /// @param electionContract The Celo Election contract.
    /// @param accountAddress The StakedCelo Account contract address.
    function execute(IElectionLookup electionContract, address accountAddress) internal view {
        TaskConsole.log(
            "Account allowed to vote over maximum number of groups:",
            electionContract.allowedToVoteOverMaxNumberOfGroups(accountAddress)
        );
    }
}
