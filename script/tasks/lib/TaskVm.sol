// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

/**
 * @dev Minimal Foundry cheatcode interface used by the operational task scripts.
 *      forge-std cannot be imported: it requires pragma >=0.8.13 while the production
 *      compilation profile pins solc 0.8.11. Only the cheatcodes the scripts need are
 *      declared, with the same mutability forge-std uses.
 */
interface TaskVm {
    // ---- environment ----
    function envString(string calldata name) external view returns (string memory);

    function envUint(string calldata name) external view returns (uint256);

    function envAddress(string calldata name) external view returns (address);

    function envBool(string calldata name) external view returns (bool);

    function envAddress(string calldata name, string calldata delim)
        external
        view
        returns (address[] memory);

    function envUint(string calldata name, string calldata delim)
        external
        view
        returns (uint256[] memory);

    function envBytes(string calldata name, string calldata delim)
        external
        view
        returns (bytes[] memory);

    function envOr(string calldata name, string calldata defaultValue)
        external
        view
        returns (string memory);

    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);

    function envOr(string calldata name, address defaultValue) external view returns (address);

    function envOr(string calldata name, bool defaultValue) external view returns (bool);

    // ---- filesystem / json ----
    function readFile(string calldata path) external view returns (string memory);

    function parseJsonAddress(string calldata json, string calldata key)
        external
        pure
        returns (address);

    // ---- string parsing / formatting ----
    function parseAddress(string calldata value) external pure returns (address);

    function parseUint(string calldata value) external pure returns (uint256);

    function parseInt(string calldata value) external pure returns (int256);

    function parseBool(string calldata value) external pure returns (bool);

    function split(string calldata input, string calldata delimiter)
        external
        pure
        returns (string[] memory);

    function toString(uint256 value) external pure returns (string memory);

    function toString(int256 value) external pure returns (string memory);

    function toString(address value) external pure returns (string memory);

    function toString(bool value) external pure returns (string memory);

    function toString(bytes calldata value) external pure returns (string memory);

    // ---- broadcasting ----
    function startBroadcast() external;

    function stopBroadcast() external;
}

/**
 * @dev Minimal console logger. `console.log` from forge-std is unavailable under
 *      pragma 0.8.11, so the log payload is sent to the console address directly.
 *      The call is a staticcall that Foundry intercepts; failures are ignored.
 */
library TaskConsole {
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    function _send(bytes memory payload) private view {
        (bool ok,) = CONSOLE.staticcall(payload);
        ok;
    }

    function log(string memory message) internal view {
        _send(abi.encodeWithSignature("log(string)", message));
    }

    function log(string memory label, string memory value) internal view {
        _send(abi.encodeWithSignature("log(string,string)", label, value));
    }

    function log(string memory label, uint256 value) internal view {
        _send(abi.encodeWithSignature("log(string,uint256)", label, value));
    }

    function log(string memory label, address value) internal view {
        _send(abi.encodeWithSignature("log(string,address)", label, value));
    }

    function log(string memory label, bool value) internal view {
        _send(abi.encodeWithSignature("log(string,bool)", label, value));
    }
}
