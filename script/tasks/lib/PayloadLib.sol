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
 *      instead, for example "upgradeTo(address)".
 *
 *      Only the single word static types StakedCelo proposals use are supported:
 *      `address`, `bool`, `bytes32`, `uint8`..`uint256` and `int8`..`int256` in steps of
 *      eight bits. Dynamic types (`string`, `bytes`), arrays and tuples need the head/tail
 *      encoding this encoder does not produce, so they are rejected by name instead of
 *      being silently written as one word, which would yield a payload the MultiSig cannot
 *      execute. Values are validated against the declared type as well: integers must be
 *      decimal and fit the declared width, `bool` is `true` or `false`, and `address` and
 *      `bytes32` are 0x prefixed hex of the exact length.
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

    // =========================================================================
    //                            SIGNATURE PARSING
    // =========================================================================

    /**
     * @dev The declared argument types of `signature`, in order. The parameter list is the
     *      text between the first "(" and the trailing ")"; it is split on commas that are
     *      not nested, so a tuple or an array of tuples arrives whole and can be reported
     *      by name rather than being torn apart into fragments.
     */
    function _argumentTypes(string memory signature) private pure returns (string[] memory) {
        bytes memory raw = bytes(signature);

        uint256 open = 0;
        while (open < raw.length && raw[open] != "(") {
            open++;
        }
        // A name, an opening parenthesis and the trailing one, in that order.
        require(open > 0 && open < raw.length, "payload: malformed signature");
        require(raw[raw.length - 1] == ")", "payload: malformed signature");

        bytes memory list = bytes(_trim(_slice(raw, open + 1, raw.length - 1)));
        if (list.length == 0) {
            return new string[](0);
        }

        string[] memory argTypes = new string[](_countTopLevel(list));
        uint256 index = 0;
        uint256 start = 0;
        uint256 depth = 0;
        for (uint256 i = 0; i < list.length; i++) {
            bytes1 char = list[i];
            if (char == "(" || char == "[") {
                depth++;
            } else if (char == ")" || char == "]") {
                depth--;
            } else if (char == "," && depth == 0) {
                argTypes[index++] = _trim(_slice(list, start, i));
                start = i + 1;
            }
        }
        argTypes[index] = _trim(_slice(list, start, list.length));
        return argTypes;
    }

    /// @dev The number of comma separated entries of `list` that are not nested in
    ///      parentheses or brackets. Reverts when those are unbalanced.
    function _countTopLevel(bytes memory list) private pure returns (uint256 count) {
        count = 1;
        uint256 depth = 0;
        for (uint256 i = 0; i < list.length; i++) {
            bytes1 char = list[i];
            if (char == "(" || char == "[") {
                depth++;
            } else if (char == ")" || char == "]") {
                require(depth > 0, "payload: malformed signature");
                depth--;
            } else if (char == "," && depth == 0) {
                count++;
            }
        }
        require(depth == 0, "payload: malformed signature");
    }

    // =========================================================================
    //                            ARGUMENT ENCODING
    // =========================================================================

    /// @dev One 32 byte head word for a single word static argument, or a revert naming the
    ///      type when `argType` is not one this encoder can write as a single word.
    function _encodeArgument(string memory argType, string memory value)
        private
        pure
        returns (bytes32)
    {
        bytes32 typeHash = keccak256(bytes(argType));
        if (typeHash == keccak256("address")) {
            return bytes32(uint256(_parseHexOfLength(argType, value, 40)));
        }
        if (typeHash == keccak256("bool")) {
            return _parseBool(value);
        }
        if (typeHash == keccak256("bytes32")) {
            return bytes32(_parseHexOfLength(argType, value, 64));
        }

        uint256 width = _integerWidth(argType, "uint");
        if (width != 0) {
            return bytes32(_parseUintOfWidth(argType, value, width));
        }
        width = _integerWidth(argType, "int");
        if (width != 0) {
            return bytes32(uint256(_parseIntOfWidth(argType, value, width)));
        }

        revert(string(abi.encodePacked("payload: unsupported argument type: ", argType)));
    }

    /**
     * @dev The bit width of `argType` when it is `prefix` followed by a canonical width
     *      (8 to 256 in steps of eight), and zero when it is anything else. Zero is not a
     *      valid width, so the caller can use it as "not this kind of integer". The bare
     *      `uint` and `int` aliases are rejected: the selector is taken from the signature
     *      text, and only the canonical names hash to the selector the target expects.
     */
    function _integerWidth(string memory argType, string memory prefix)
        private
        pure
        returns (uint256)
    {
        bytes memory raw = bytes(argType);
        bytes memory prefixBytes = bytes(prefix);
        if (raw.length <= prefixBytes.length) {
            return 0;
        }
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (raw[i] != prefixBytes[i]) {
                return 0;
            }
        }

        // Leading zeros would name a type that hashes to a different selector.
        if (raw[prefixBytes.length] == "0") {
            return 0;
        }
        uint256 width = 0;
        for (uint256 i = prefixBytes.length; i < raw.length; i++) {
            if (raw[i] < "0" || raw[i] > "9") {
                return 0;
            }
            width = width * 10 + uint8(raw[i]) - 48;
            if (width > 256) {
                return 0;
            }
        }
        return width % 8 == 0 ? width : 0;
    }

    /// @dev `value` as an unsigned integer that fits `width` bits.
    function _parseUintOfWidth(
        string memory argType,
        string memory value,
        uint256 width
    ) private pure returns (uint256 parsed) {
        if (!_isDecimal(value, false)) {
            revert(_invalid(argType, value));
        }
        parsed = vm.parseUint(value);
        if (parsed > type(uint256).max >> (256 - width)) {
            revert(_outOfRange(argType, value));
        }
    }

    /// @dev `value` as a signed integer in [-2**(width-1), 2**(width-1) - 1].
    function _parseIntOfWidth(
        string memory argType,
        string memory value,
        uint256 width
    ) private pure returns (int256 parsed) {
        if (!_isDecimal(value, true)) {
            revert(_invalid(argType, value));
        }
        parsed = vm.parseInt(value);

        uint256 bound = uint256(1) << (width - 1);
        int256 max = int256(bound - 1);
        if (parsed > max || parsed < -max - 1) {
            revert(_outOfRange(argType, value));
        }
    }

    /// @dev The word for `value`, which has to be exactly "true" or "false".
    function _parseBool(string memory value) private pure returns (bytes32) {
        bytes32 valueHash = keccak256(bytes(value));
        if (valueHash == keccak256("true")) {
            return bytes32(uint256(1));
        }
        if (valueHash == keccak256("false")) {
            return bytes32(0);
        }
        revert(_invalid("bool", value));
    }

    /**
     * @dev `value` as an unsigned integer, when it is "0x" followed by exactly `digits` hex
     *      characters. Used for `address` (40 digits) and `bytes32` (64 digits), both of
     *      which are right aligned in the word the caller builds from the result.
     */
    function _parseHexOfLength(
        string memory argType,
        string memory value,
        uint256 digits
    ) private pure returns (uint256 parsed) {
        bytes memory raw = bytes(value);
        if (raw.length != digits + 2 || raw[0] != "0" || (raw[1] != "x" && raw[1] != "X")) {
            revert(_invalid(argType, value));
        }
        for (uint256 i = 2; i < raw.length; i++) {
            uint8 nibble = _hexDigit(raw[i]);
            if (nibble == type(uint8).max) {
                revert(_invalid(argType, value));
            }
            parsed = (parsed << 4) | nibble;
        }
    }

    /// @dev The value of one hex character, or uint8 max when `char` is not one.
    function _hexDigit(bytes1 char) private pure returns (uint8) {
        if (char >= "0" && char <= "9") {
            return uint8(char) - 48;
        }
        if (char >= "a" && char <= "f") {
            return uint8(char) - 87;
        }
        if (char >= "A" && char <= "F") {
            return uint8(char) - 55;
        }
        return type(uint8).max;
    }

    /// @dev Whether `value` is a non empty run of decimal digits, optionally preceded by a
    ///      minus sign when `signed` is set. Other bases are rejected so that the range
    ///      check below reads the number the operator wrote.
    function _isDecimal(string memory value, bool signed) private pure returns (bool) {
        bytes memory raw = bytes(value);
        uint256 start = signed && raw.length > 0 && raw[0] == "-" ? 1 : 0;
        if (raw.length == start) {
            return false;
        }
        for (uint256 i = start; i < raw.length; i++) {
            if (raw[i] < "0" || raw[i] > "9") {
                return false;
            }
        }
        return true;
    }

    // =========================================================================
    //                                 STRINGS
    // =========================================================================

    /// @dev The "not a valid <type>" message, quoting the offending value.
    function _invalid(string memory argType, string memory value)
        private
        pure
        returns (string memory)
    {
        return string(abi.encodePacked("payload: invalid ", argType, " argument: ", value));
    }

    /// @dev The "does not fit <type>" message, quoting the offending value.
    function _outOfRange(string memory argType, string memory value)
        private
        pure
        returns (string memory)
    {
        return string(abi.encodePacked("payload: ", argType, " argument out of range: ", value));
    }

    /// @dev `raw[start:end]` as a string.
    function _slice(
        bytes memory raw,
        uint256 start,
        uint256 end
    ) private pure returns (string memory) {
        bytes memory sliced = new bytes(end - start);
        for (uint256 i = 0; i < sliced.length; i++) {
            sliced[i] = raw[start + i];
        }
        return string(sliced);
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
        return _slice(raw, start, end);
    }
}
