//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IRegistry.sol";

/**
 * @title Routes identifiers to addresses.
 */
contract MockRegistry is IRegistry, Ownable, Initializable {
    using SafeMath for uint256;

    mapping(bytes32 => address) public registry;

    event RegistryUpdated(string identifier, bytes32 indexed identifierHash, address indexed addr);

    /**
     * @notice Used when identifier has no entry in the registry contract.
     */
    error IdentifierHasNoRegistryEntry();

    /**
     * @notice Associates the given address with the given identifier.
     * @param identifier Identifier of contract whose address we want to set.
     * @param addr Address of contract.
     */
    function setAddressFor(string calldata identifier, address addr) external onlyOwner {
        bytes32 identifierHash = keccak256(abi.encodePacked(identifier));
        registry[identifierHash] = addr;
    }

    /**
     * @notice Gets address associated with the given identifierHash.
     * @param identifierHash Identifier hash of contract whose address we want to look up.
     * @dev Throws if address not set.
     */
    function getAddressForOrDie(bytes32 identifierHash) external view returns (address) {
        if (registry[identifierHash] == address(0)) {
            revert IdentifierHasNoRegistryEntry();
        }
        return registry[identifierHash];
    }

    /**
     * @notice Gets address associated with the given identifierHash.
     * @param identifierHash Identifier hash of contract whose address we want to look up.
     */
    function getAddressFor(bytes32 identifierHash) external view returns (address) {
        return registry[identifierHash];
    }

    /**
     * @notice Gets address associated with the given identifier.
     * @param identifier Identifier of contract whose address we want to look up.
     * @dev Throws if address not set.
     */
    function getAddressForStringOrDie(string calldata identifier) external view returns (address) {
        bytes32 identifierHash = keccak256(abi.encodePacked(identifier));
        if (registry[identifierHash] == address(0)) {
            revert IdentifierHasNoRegistryEntry();
        }
        return registry[identifierHash];
    }

    /**
     * @notice Gets address associated with the given identifier.
     * @param identifier Identifier of contract whose address we want to look up.
     */
    function getAddressForString(string calldata identifier) external view returns (address) {
        bytes32 identifierHash = keccak256(abi.encodePacked(identifier));
        return registry[identifierHash];
    }

    /**
     * @notice Iterates over provided array of identifiers, getting the address for each.
     *         Returns true if `sender` matches the address of one of the provided identifiers.
     * @param identifierHashes Array of hashes of approved identifiers.
     * @param sender Address in question to verify membership.
     * @return True if `sender` corresponds to the address of any of `identifiers`
     *         registry entries.
     */
    function isOneOf(bytes32[] calldata identifierHashes, address sender)
        external
        view
        returns (bool)
    {
        for (uint256 i = 0; i < identifierHashes.length; i = i.add(1)) {
            if (registry[identifierHashes[i]] == sender) {
                return true;
            }
        }
        return false;
    }
}
