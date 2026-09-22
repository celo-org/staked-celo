// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/PayloadLib.sol";

/**
 * @title EncodeProposalPayloadScript
 * @notice Encodes a function payload on a contract for a proposal. Replaces
 *         `yarn hardhat stakedCelo:multiSig:encode:proposal:payload --contract <name>
 *          --function <name> --args <a,b>`.
 *
 * Environment variables:
 *   FUNCTION_SIGNATURE  required. Full signature, e.g. "upgradeTo(address)". The Hardhat
 *                       task took a bare function name and resolved the types through the
 *                       deployment ABI; Solidity has no runtime ABI, so the types are part
 *                       of the input here.
 *   ARGS                optional. Comma separated arguments; empty for a no-argument call.
 *   CONTRACT            optional. Deployment name, e.g. "Manager". When set, the address of
 *                       that deployment is printed as the proposal destination.
 *   NETWORK             optional. Deployments directory: celo | sepolia | local.
 *
 * Usage:
 *   CONTRACT=Manager FUNCTION_SIGNATURE='upgradeTo(address)' ARGS=0x... \
 *     forge script script/tasks/multisig/EncodeProposalPayload.s.sol --rpc-url celo
 */
contract EncodeProposalPayloadScript is TaskBase {
    /// @notice Reads the signature and arguments from the environment and prints the payload.
    function run() external view {
        string memory contractName = vm.envOr("CONTRACT", string(""));
        address destination =
            bytes(contractName).length == 0 ? ADDRESS_ZERO : deploymentAddress(contractName);

        execute(destination, vm.envString("FUNCTION_SIGNATURE"), vm.envOr("ARGS", string("")));
    }

    /**
     * @notice Encodes and prints the payload for `signature` called with `argsCsv`.
     * @param destination The proposal destination, printed for convenience; may be zero.
     * @param signature The full function signature, e.g. "setMinCountOfActiveGroups(uint256)".
     * @param argsCsv The comma separated arguments, empty when there are none.
     * @return payload The encoded calldata.
     */
    function execute(address destination, string memory signature, string memory argsCsv)
        internal
        view
        returns (bytes memory payload)
    {
        payload = PayloadLib.encodePayload(signature, argsCsv);

        if (destination != ADDRESS_ZERO) {
            TaskConsole.log("DESTINATIONS", destination);
            TaskConsole.log("VALUES", uint256(0));
        }
        TaskConsole.log("PAYLOADS", vm.toString(payload));
    }
}
