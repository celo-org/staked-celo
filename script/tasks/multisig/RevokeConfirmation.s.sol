// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/MultiSigTaskLib.sol";

/**
 * @title RevokeConfirmationScript
 * @notice Revoke a proposal confirmation. Replaces
 *         `yarn hardhat stakedCelo:multiSig:revokeConfirmation --proposal-id <id>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the proposal.
 *   NETWORK      optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   PROPOSAL_ID=3 forge script script/tasks/multisig/RevokeConfirmation.s.sol \
 *     --rpc-url celo --broadcast --ledger
 */
contract RevokeConfirmationScript is TaskBase {
    /// @notice Reads PROPOSAL_ID from the environment and revokes as the broadcaster.
    function run() external {
        IMultiSigTask multiSigContract = multiSig();
        uint256 proposalId = vm.envUint("PROPOSAL_ID");

        vm.startBroadcast();
        execute(multiSigContract, proposalId);
        vm.stopBroadcast();
    }

    /// @notice Revokes the broadcaster's confirmation of `proposalId`.
    /// @param multiSigContract The MultiSig contract to revoke on.
    /// @param proposalId The ID of the proposal.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId) internal {
        MultiSigTaskLib.revokeConfirmation(multiSigContract, proposalId);
    }
}
