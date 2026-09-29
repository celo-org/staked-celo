// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

/// @dev The cheatcodes the checks below read the deployments directory with.
interface NetworkCheckVm {
    function exists(string calldata path) external view returns (bool);

    function readFile(string calldata path) external view returns (string memory);

    function keyExistsJson(string calldata json, string calldata key) external view returns (bool);

    function parseJsonUint(string calldata json, string calldata key)
        external
        pure
        returns (uint256);

    function parseUint(string calldata value) external pure returns (uint256);

    function toString(uint256 value) external pure returns (string memory);
}

/**
 * @title NetworkCheck
 * @notice Ties a deployments directory to the chain its records were written on.
 * @dev `NETWORK` picks the directory by name, and nothing else ties that name to the node
 *      `--rpc-url` connects to. Pointed at another chain, a deploy would take the records
 *      for stale, deploy replacements there and overwrite them, and a task could send a
 *      transaction to whatever the recorded address holds on that chain. Both script
 *      families therefore check the directory when they resolve it and every record when
 *      they read one.
 */
library NetworkCheck {
    NetworkCheckVm private constant VM =
        NetworkCheckVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Celo mainnet chain id.
    uint256 internal constant CELO_CHAIN_ID = 42220;

    /// @notice Celo Sepolia chain id.
    uint256 internal constant SEPOLIA_CHAIN_ID = 11142220;

    /// @notice anvil's default chain id, which the `local` directory belongs to.
    uint256 internal constant LOCAL_CHAIN_ID = 31337;

    /**
     * @notice The chain id the records of `network` belong to, or zero when nothing says.
     * @dev The two public networks and `local` are known by name, the same table the
     *      scripts resolve a chain id with. `local` has to be among them: it is git-ignored
     *      and nothing writes a `.chainId` into it, so a first local deployment pointed at a
     *      public node would otherwise go through. Any other directory is known by the
     *      `.chainId` file the earlier deployment tooling kept in it, where there is one.
     */
    function expectedChainId(string memory network) internal view returns (uint256) {
        bytes32 name = keccak256(bytes(network));
        if (name == keccak256("celo")) {
            return CELO_CHAIN_ID;
        }
        if (name == keccak256("sepolia")) {
            return SEPOLIA_CHAIN_ID;
        }
        if (name == keccak256("local")) {
            return LOCAL_CHAIN_ID;
        }
        string memory file = string(abi.encodePacked("deployments/", network, "/.chainId"));
        if (!VM.exists(file)) {
            return 0;
        }
        return VM.parseUint(_trim(VM.readFile(file)));
    }

    /// @notice Revert unless the connected chain is the one the records of `network` belong to.
    function requireChain(string memory network) internal view {
        uint256 expected = expectedChainId(network);
        if (expected == 0 || expected == block.chainid) {
            return;
        }
        revert(
            string(
                abi.encodePacked(
                    "NETWORK ",
                    network,
                    " is chain ",
                    VM.toString(expected),
                    " but the node is chain ",
                    VM.toString(block.chainid)
                )
            )
        );
    }

    /**
     * @notice Revert when a record carries the chain id of another chain.
     * @dev The records the Foundry scripts write carry the chain id they were written on;
     *      the older ones do not, and are covered by `requireChain`.
     */
    function requireRecordChain(string memory json, string memory path) internal view {
        if (!VM.keyExistsJson(json, ".chainId")) {
            return;
        }
        uint256 recorded = VM.parseJsonUint(json, ".chainId");
        if (recorded == block.chainid) {
            return;
        }
        revert(
            string(
                abi.encodePacked(
                    "record ",
                    path,
                    " was written on chain ",
                    VM.toString(recorded),
                    " but the node is chain ",
                    VM.toString(block.chainid)
                )
            )
        );
    }

    /// @dev `value` without trailing whitespace, e.g. the newline a `.chainId` file may end in.
    function _trim(string memory value) private pure returns (string memory) {
        bytes memory raw = bytes(value);
        uint256 end = raw.length;
        while (end > 0 && (raw[end - 1] == " " || raw[end - 1] == "\n" || raw[end - 1] == "\r")) {
            end--;
        }
        bytes memory trimmed = new bytes(end);
        for (uint256 i = 0; i < end; i++) {
            trimmed[i] = raw[i];
        }
        return string(trimmed);
    }
}
