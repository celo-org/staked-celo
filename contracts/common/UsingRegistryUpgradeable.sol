//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAccounts.sol";
import "../interfaces/IElection.sol";
import "../interfaces/IGoldToken.sol";
import "../interfaces/ILockedGold.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IGovernance.sol";
import "../interfaces/IValidators.sol";

/**
 * @title A helper for getting Celo core contracts from the Registry.
 */
abstract contract UsingRegistryUpgradeable is Initializable {
    /// @notice The canonical address of the Registry.
    address internal constant CANONICAL_REGISTRY = 0x000000000000000000000000000000000000ce10;

    /// @notice The registry ID for the Accounts contract.
    bytes32 private constant ACCOUNTS_REGISTRY_ID = keccak256(abi.encodePacked("Accounts"));

    /// @notice The registry ID for the Election contract.
    bytes32 private constant ELECTION_REGISTRY_ID = keccak256(abi.encodePacked("Election"));

    /// @notice The registry ID for the GoldToken contract.
    bytes32 private constant GOLD_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("GoldToken"));

    /// @notice The registry ID for the LockedGold contract.
    bytes32 private constant LOCKED_GOLD_REGISTRY_ID = keccak256(abi.encodePacked("LockedGold"));

    /// @notice The registry ID for the Governance contract.
    bytes32 private constant GOVERNANCE_REGISTRY_ID = keccak256(abi.encodePacked("Governance"));

    /// @notice The registry ID for the Validator contract.
    bytes32 private constant VALIDATORS_REGISTRY_ID = keccak256(abi.encodePacked("Validators"));

    /// @notice The Registry.
    IRegistry public registry;

    /**
     * @notice Initializes the UsingRegistryUpgradable contract in an upgradable scenario
     * @param _registry The address of the Registry. For convenience, if the zero address is
     * provided, the registry is set to the canonical Registry address, i.e. 0x0...ce10. This
     * parameter should only be a non-zero address when testing.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __UsingRegistry_init(address _registry) internal onlyInitializing {
        if (_registry == address(0)) {
            registry = IRegistry(CANONICAL_REGISTRY);
        } else {
            registry = IRegistry(_registry);
        }
    }

    /**
     * @notice Gets the Accounts contract from the Registry.
     * @return The Accounts contract from the Registry.
     */
    function getAccounts() internal view returns (IAccounts) {
        return IAccounts(registry.getAddressForOrDie(ACCOUNTS_REGISTRY_ID));
    }

    /**
     * @notice Gets the Election contract from the Registry.
     * @return The Election contract from the Registry.
     */
    function getElection() internal view returns (IElection) {
        return IElection(registry.getAddressForOrDie(ELECTION_REGISTRY_ID));
    }

    /**
     * @notice Gets the GoldToken contract from the Registry.
     * @return The GoldToken contract from the Registry.
     */
    function getGoldToken() internal view returns (IGoldToken) {
        return IGoldToken(registry.getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID));
    }

    /**
     * @notice Gets the LockedGold contract from the Registry.
     * @return The LockedGold contract from the Registry.
     */
    function getLockedGold() internal view returns (ILockedGold) {
        return ILockedGold(registry.getAddressForOrDie(LOCKED_GOLD_REGISTRY_ID));
    }

    /**
     * @notice Gets the Governance contract from the Registry.
     * @return The Governance contract from the Registry.
     */
    function getGovernance() internal view returns (IGovernance) {
        return IGovernance(registry.getAddressForOrDie(GOVERNANCE_REGISTRY_ID));
    }

    /**
     * @notice Gets the validators contract from the Registry.
     * @return The validators contract from the Registry.
     */
    function getValidators() internal view returns (IValidators) {
        return IValidators(registry.getAddressForOrDie(VALIDATORS_REGISTRY_ID));
    }
}
