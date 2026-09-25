// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskVm.sol";

/**
 * @title FormatLib
 * @notice Renders proposal arrays as the comma separated strings the submit script reads
 *         from DESTINATIONS / VALUES / PAYLOADS, so the output of an encode script can be
 *         pasted straight into the next command.
 */
library FormatLib {
    TaskVm private constant vm = TaskVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Joins addresses with commas.
    function join(address[] memory values) internal pure returns (string memory out) {
        for (uint256 i = 0; i < values.length; i++) {
            out = i == 0
                ? vm.toString(values[i])
                : string(abi.encodePacked(out, ",", vm.toString(values[i])));
        }
    }

    /// @notice Joins unsigned integers with commas.
    function join(uint256[] memory values) internal pure returns (string memory out) {
        for (uint256 i = 0; i < values.length; i++) {
            out = i == 0
                ? vm.toString(values[i])
                : string(abi.encodePacked(out, ",", vm.toString(values[i])));
        }
    }

    /// @notice Joins hex encoded byte strings with commas.
    function join(bytes[] memory values) internal pure returns (string memory out) {
        for (uint256 i = 0; i < values.length; i++) {
            out = i == 0
                ? vm.toString(values[i])
                : string(abi.encodePacked(out, ",", vm.toString(values[i])));
        }
    }
}
