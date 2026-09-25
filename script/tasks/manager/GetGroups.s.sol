// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/GroupsLib.sol";
import "../lib/FormatLib.sol";

/**
 * @title GetGroupsScript
 * @notice Returns all groups the protocol is voting for. Replaces
 *         `yarn hardhat stakedCelo:manager:getGroups`.
 *
 * Environment variables:
 *   NETWORK  optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   forge script script/tasks/manager/GetGroups.s.sol --rpc-url celo
 */
contract GetGroupsScript is TaskBase {
    /// @notice Prints the active groups of DefaultStrategy.
    function run() external view {
        execute(defaultStrategyContract());
    }

    /// @notice Prints the active groups held by `defaultStrategy`.
    /// @param defaultStrategy The DefaultStrategy contract.
    function execute(IDefaultStrategyTask defaultStrategy) internal view {
        address[] memory groups = GroupsLib.defaultGroups(defaultStrategy);
        TaskConsole.log("Groups:", FormatLib.join(groups));
    }
}
