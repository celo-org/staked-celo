// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskVm.sol";

/**
 * @title PayloadLib
 * @notice Builds MultiSig proposal calldata from a function signature and comma separated
 *         arguments, replacing the ethers `contract.interface.encodeFunctionData` call of
 *         the `stakedCelo:multiSig:encode:proposal:payload` task.
 * @dev The Hardhat task looked the ABI up from the deployment artifact and took a bare
 *      function name. Solidity has no runtime ABI, so the full signature is passed in
 *      instead, for example "upgradeTo(address)". Every argument type used by StakedCelo
 *      proposals encodes to a single 32 byte word (address, bool, uintN, intN), which is
 *      what this encoder supports; anything else is rejected rather than mis-encoded.
 */
library PayloadLib {
    TaskVm private constant vm =
        TaskVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /**
     * @notice Encodes a call to `signature` with `argsCsv`.
     * @param signature The full function signature, e.g. "activateGroup(address,address,address)".
     * @param argsCsv The comma separated arguments, empty when the function takes none.
     * @return The ABI encoded calldata.
     */
    function encodePayload(string memory signature, string memory argsCsv)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory payload = abi.encodePacked(bytes4(keccak256(bytes(signature))));

        string[] memory argTypes = _argumentTypes(signature);
        string[] memory args = bytes(argsCsv).length == 0
            ? new string[](0)
            : vm.split(argsCsv, ",");
        require(argTypes.length == args.length, "payload: argument count mismatch");

        for (uint256 i = 0; i < args.length; i++) {
            payload = abi.encodePacked(payload, _encodeArgument(argTypes[i], _trim(args[i])));
        }
        return payload;
    }

    /// @dev The declared argument types of `signature`, in order.
    function _argumentTypes(string memory signature) private pure returns (string[] memory) {
        string[] memory afterName = vm.split(signature, "(");
        require(afterName.length == 2, "payload: malformed signature");

        string[] memory beforeClose = vm.split(afterName[1], ")");
        string memory typeList = _trim(beforeClose[0]);
        if (bytes(typeList).length == 0) {
            return new string[](0);
        }

        string[] memory argTypes = vm.split(typeList, ",");
        for (uint256 i = 0; i < argTypes.length; i++) {
            argTypes[i] = _trim(argTypes[i]);
        }
        return argTypes;
    }

    /// @dev One 32 byte head word for a static single word argument.
    function _encodeArgument(string memory argType, string memory value)
        private
        pure
        returns (bytes32)
    {
        bytes32 typeHash = keccak256(bytes(argType));
        if (typeHash == keccak256("address")) {
            return bytes32(uint256(uint160(vm.parseAddress(value))));
        }
        if (typeHash == keccak256("bool")) {
            return vm.parseBool(value) ? bytes32(uint256(1)) : bytes32(0);
        }
        if (_startsWith(argType, "uint")) {
            return bytes32(vm.parseUint(value));
        }
        if (_startsWith(argType, "int")) {
            return bytes32(uint256(vm.parseInt(value)));
        }
        revert("payload: unsupported argument type");
    }

    /// @dev Whether `value` begins with `prefix`.
    function _startsWith(string memory value, string memory prefix) private pure returns (bool) {
        bytes memory valueBytes = bytes(value);
        bytes memory prefixBytes = bytes(prefix);
        if (valueBytes.length < prefixBytes.length) {
            return false;
        }
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (valueBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        return true;
    }

    /// @dev Strips leading and trailing spaces so "a, b" reads the same as "a,b".
    function _trim(string memory value) private pure returns (string memory) {
        bytes memory raw = bytes(value);
        uint256 start = 0;
        uint256 end = raw.length;
        while (start < end && raw[start] == 0x20) {
            start++;
        }
        while (end > start && raw[end - 1] == 0x20) {
            end--;
        }
        bytes memory trimmed = new bytes(end - start);
        for (uint256 i = 0; i < trimmed.length; i++) {
            trimmed[i] = raw[start + i];
        }
        return string(trimmed);
    }
}
