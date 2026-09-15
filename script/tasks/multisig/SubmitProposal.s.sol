// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/MultiSigTaskLib.sol";

/**
 * @title SubmitProposalScript
 * @notice Submit a proposal to the multiSig contract. Replaces
 *         `yarn hardhat stakedCelo:multiSig:submitProposal --destinations <a,b>
 *          --values <0,0> --payloads <0x..,0x..>`.
 *
 * Environment variables:
 *   DESTINATIONS  required. Comma separated addresses the operations are targeted at.
 *   VALUES        required. Comma separated CELO values involved in the proposal.
 *   PAYLOADS      required. Comma separated hex payloads of the proposal.
 *   NETWORK       optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   DESTINATIONS=0xA,0xB VALUES=0,0 PAYLOADS=0x...,0x... \
 *     forge script script/tasks/multisig/SubmitProposal.s.sol --rpc-url celo \
 *     --broadcast --ledger
 */
contract SubmitProposalScript is TaskBase {
    /// @notice Reads the proposal from the environment and submits it as the broadcaster.
    function run() external {
        IMultiSigTask multiSigContract = multiSig();
        address[] memory destinations = vm.envAddress("DESTINATIONS", ",");
        uint256[] memory values = vm.envUint("VALUES", ",");
        bytes[] memory payloads = vm.envBytes("PAYLOADS", ",");

        vm.startBroadcast();
        execute(multiSigContract, destinations, values, payloads);
        vm.stopBroadcast();
    }

    /**
     * @notice Submits a proposal and prints the resulting proposal ID.
     * @param multiSigContract The MultiSig contract to submit to.
     * @param destinations The addresses at which the operations are targeted.
     * @param values The CELO values involved in the proposal if any.
     * @param payloads The payloads of the proposal.
     * @return proposalId The ID of the submitted proposal.
     */
    function execute(
        IMultiSigTask multiSigContract,
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory payloads
    ) internal returns (uint256 proposalId) {
        proposalId = MultiSigTaskLib.submitProposal(
            multiSigContract, destinations, values, payloads
        );
    }
}
