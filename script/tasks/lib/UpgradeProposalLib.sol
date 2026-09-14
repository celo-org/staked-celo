// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

/**
 * @title UpgradeProposalLib
 * @notice Payload builders shared by the multiSig update scripts.
 */
library UpgradeProposalLib {
    /// @notice Payload for `upgradeTo(address)` on an ERC1967 proxy.
    /// @param implementation The new implementation address.
    /// @return The encoded calldata.
    function upgradeToPayload(address implementation) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("upgradeTo(address)", implementation);
    }

    /**
     * @notice Payload for `setDependencies(...)` on the Manager contract.
     * @param stakedCelo The StakedCelo address.
     * @param account The Account address.
     * @param vote The Vote address.
     * @param groupHealth The GroupHealth address.
     * @param specificGroupStrategy The SpecificGroupStrategy address.
     * @param defaultStrategy The DefaultStrategy address.
     * @return The encoded calldata.
     */
    function managerSetDependenciesPayload(
        address stakedCelo,
        address account,
        address vote,
        address groupHealth,
        address specificGroupStrategy,
        address defaultStrategy
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSignature(
                "setDependencies(address,address,address,address,address,address)",
                stakedCelo,
                account,
                vote,
                groupHealth,
                specificGroupStrategy,
                defaultStrategy
            );
    }

    /// @notice Payload for `setPauser()` on the StakedCelo protocol contracts.
    /// @return The encoded calldata.
    function setPauserPayload() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("setPauser()");
    }

    /// @notice Payload for `setPauser(address)` on the MultiSig contract.
    /// @param pauser The address to set as the pauser.
    /// @return The encoded calldata.
    function setPauserPayload(address pauser) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("setPauser(address)", pauser);
    }

    /// @notice Payload for `addOwner(address)` on the MultiSig contract.
    /// @param owner The owner to add.
    /// @return The encoded calldata.
    function addOwnerPayload(address owner) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("addOwner(address)", owner);
    }

    /// @notice Payload for `setMinCountOfActiveGroups(uint256)` on DefaultStrategy.
    /// @param minCount The minimum number of active groups.
    /// @return The encoded calldata.
    function setMinCountOfActiveGroupsPayload(uint256 minCount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("setMinCountOfActiveGroups(uint256)", minCount);
    }

    /// @notice Payload for `activateGroup(address,address,address)` on DefaultStrategy.
    /// @param group The group to activate.
    /// @param lesser The group with fewer votes, or address(0).
    /// @param greater The group with more votes, or address(0).
    /// @return The encoded calldata.
    function activateGroupPayload(
        address group,
        address lesser,
        address greater
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSignature(
                "activateGroup(address,address,address)",
                group,
                lesser,
                greater
            );
    }

    /// @notice Payload for `setAllowedToVoteOverMaxNumberOfGroups(bool)` on Account.
    /// @param flag The on/off flag.
    /// @return The encoded calldata.
    function setAllowedToVoteOverMaxNumberOfGroupsPayload(bool flag)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("setAllowedToVoteOverMaxNumberOfGroups(bool)", flag);
    }
}
