// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";

/**
 * @title IsConfirmedByScript
 * @notice Check if a proposal has been confirmed by a multiSig owner. Replaces
 *         `yarn hardhat stakedCelo:multiSig:isConfirmedBy --proposal-id <id>
 *          --owner-address <address>`.
 *
 * Environment variables:
 *   PROPOSAL_ID    required. The ID of the proposal.
 *   OWNER_ADDRESS  required. The address of the multiSig contract owner.
 *   NETWORK        optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   PROPOSAL_ID=3 OWNER_ADDRESS=0x... \
 *     forge script script/tasks/multisig/IsConfirmedBy.s.sol --rpc-url celo
 */
contract IsConfirmedByScript is TaskBase {
    /// @notice Reads PROPOSAL_ID and OWNER_ADDRESS from the environment and prints the result.
    function run() external view {
        execute(multiSig(), vm.envUint("PROPOSAL_ID"), vm.envAddress("OWNER_ADDRESS"));
    }

    /// @notice Prints whether `ownerAddress` has confirmed `proposalId`.
    /// @param multiSigContract The MultiSig contract to read from.
    /// @param proposalId The ID of the proposal.
    /// @param ownerAddress The owner address to check.
    function execute(IMultiSigTask multiSigContract, uint256 proposalId, address ownerAddress)
        internal
        view
    {
        TaskConsole.log(
            "is Proposal confirmed:", multiSigContract.isConfirmedBy(proposalId, ownerAddress)
        );
    }
}
