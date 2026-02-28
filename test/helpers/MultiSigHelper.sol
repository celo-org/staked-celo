// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../../contracts/common/MultiSig.sol";

/**
 * @title Vm
 * @notice Foundry cheatcode VM interface
 * @dev Minimal interface for vm.prank() and vm.warp() without importing forge-std/Test.sol
 */
interface Vm {
    function prank(address) external;
    function warp(uint256) external;
}

/**
 * @title MultiSigHelper
 * @notice Provides utility functions for testing MultiSig proposals
 * @dev Ports submitAndExecuteMultiSigProposal from test-ts/utils-multisig.ts
 */
abstract contract MultiSigHelper {
    // Foundry cheatcode VM instance
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /**
     * @notice Submits a proposal to the MultiSig contract and executes it after the delay
     * @param multiSig The MultiSig contract instance
     * @param destinations The addresses at which the proposal is directed to
     * @param values The amounts of CELO involved
     * @param payloads The payloads of the proposal
     * @param signer The address of the signer submitting the proposal
     * @return proposalId The ID of the submitted proposal
     */
    function submitAndExecuteMultiSigProposal(
        MultiSig multiSig,
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory payloads,
        address signer
    ) internal returns (uint256 proposalId) {
        // Submit proposal as signer
        vm.prank(signer);
        proposalId = multiSig.submitProposal(destinations, values, payloads);

        // Time travel past the delay
        // submitProposal calls confirmProposal which auto-schedules if fully confirmed
        // (which is the case when required == 1, common in tests)
        uint256 delay = multiSig.delay();
        vm.warp(block.timestamp + delay + 1);

        // Execute proposal as signer
        vm.prank(signer);
        multiSig.executeProposal(proposalId);
    }

    /**
     * @notice Encodes a proposal payload using selector and arguments
     * @param selector The function selector (4 bytes)
     * @param args The encoded arguments
     * @return The encoded payload
     */
    function encodeProposalPayload(bytes4 selector, bytes memory args)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(selector, args);
    }
}
