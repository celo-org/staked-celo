// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import {DeployBase, DeployLog} from "./DeployBase.s.sol";

import {MultiSig} from "../../contracts/common/MultiSig.sol";
import {Manager} from "../../contracts/Manager.sol";
import {Account} from "../../contracts/Account.sol";
import {StakedCelo} from "../../contracts/StakedCelo.sol";
import {Vote} from "../../contracts/Vote.sol";
import {GroupHealth} from "../../contracts/GroupHealth.sol";
import {SpecificGroupStrategy} from "../../contracts/SpecificGroupStrategy.sol";
import {DefaultStrategy} from "../../contracts/DefaultStrategy.sol";
import {RebasedStakedCelo} from "../../contracts/RebasedStakedCelo.sol";
import {
    AddressSortedLinkedList
} from "../../contracts/common/linkedlists/AddressSortedLinkedList.sol";

/// @dev UUPS upgrade entry point, implemented by every protocol proxy.
interface IUUPS {
    function upgradeTo(address newImplementation) external;
}

/**
 * @title UpgradeImplementation
 * @notice Deploys a fresh implementation for one already deployed proxy and either
 *         upgrades it directly or prints the payload to propose through the MultiSig.
 * @dev Replaces the `catchNotOwnerForProxy` / `catchUpgradeErrorInMultisig` behaviour of
 *      the Hardhat scripts, which relied on the upgrade transaction reverting on chain to
 *      discover that the deployer no longer owns the proxy. Here ownership is read up
 *      front, so nothing is sent that is known to revert.
 *
 *      Required environment variables:
 *        CONTRACT  Name of the contract to upgrade, e.g. `Manager`.
 *      Optional:
 *        NETWORK   Deployments directory name; defaults to the chain id mapping.
 */
contract UpgradeImplementation is DeployBase {
    /// @notice Deploy the new implementation and upgrade the proxy when possible.
    /// @dev The broadcaster is read from inside the broadcast rather than from
    ///      `msg.sender`, which with `--ledger` and no `--sender` is forge's default
    ///      simulation sender and not the account that signs.
    function run() external {
        _initNetwork();

        string memory name = vm.envString("CONTRACT");
        address proxy = readDeploymentAddress(name);
        require(proxy != address(0), "UpgradeImplementation: no deployment record");

        DeployLog.a(string(abi.encodePacked(name, ": proxy")), proxy);
        DeployLog.a(
            string(abi.encodePacked(name, ": current implementation")), implementationOf(proxy)
        );

        vm.startBroadcast();
        deployer = _readBroadcaster("UpgradeImplementation");
        address implementation = _deployImplementation(name);
        bool upgraded = _upgradeOrPrintPayload(proxy, implementation);
        vm.stopBroadcast();

        _recordImplementationDeployment(name, implementation);
        _recordLinkedLibrary(name);
        if (upgraded) {
            _recordProxyDeployment(name, proxy, implementation);
        }
        DeployLog.a(string(abi.encodePacked(name, ": new implementation")), implementation);
    }

    /// @dev DefaultStrategy is the one contract here that links a library, and forge
    ///      deploys a fresh AddressSortedLinkedList alongside the implementation. It is a
    ///      contract of its own on chain and needs verifying, so its record has to be
    ///      refreshed too - otherwise it keeps pointing at the previous deployment.
    function _recordLinkedLibrary(string memory name) private {
        if (keccak256(bytes(name)) != keccak256("DefaultStrategy")) {
            return;
        }
        _recordImplementationDeployment("AddressSortedLinkedList", address(AddressSortedLinkedList));
        DeployLog.a("AddressSortedLinkedList: linked", address(AddressSortedLinkedList));
    }

    /// @dev Upgrade the proxy if the broadcaster owns it, otherwise print what has to be
    ///      submitted through the MultiSig.
    /// @return True when the proxy was upgraded in this run.
    function _upgradeOrPrintPayload(address proxy, address implementation) private returns (bool) {
        if (_ownerOf(proxy) == deployer) {
            IUUPS(proxy).upgradeTo(implementation);
            DeployLog.s("upgradeTo executed by the broadcaster");
            return true;
        }
        DeployLog.s("Broadcaster does not own the proxy; submit this through the MultiSig:");
        DeployLog.a("  destination", proxy);
        DeployLog.u("  value", 0);
        DeployLog.s(
            string(
                abi.encodePacked(
                    "  payload ",
                    vm.toString(abi.encodeWithSignature("upgradeTo(address)", implementation))
                )
            )
        );
        return false;
    }

    /// @dev Read `owner()` without reverting on contracts that have no such function.
    ///      MultiSig authorizes its own upgrades through a proposal instead of Ownable.
    function _ownerOf(address proxy) private view returns (address) {
        (bool ok, bytes memory data) = proxy.staticcall(abi.encodeWithSignature("owner()"));
        if (!ok || data.length != 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    /// @dev Deploy the implementation matching `name`.
    function _deployImplementation(string memory name) private returns (address) {
        bytes32 id = keccak256(bytes(name));
        if (id == keccak256("Manager")) {
            return address(new Manager());
        }
        if (id == keccak256("Account")) {
            return address(new Account());
        }
        if (id == keccak256("StakedCelo")) {
            return address(new StakedCelo());
        }
        if (id == keccak256("Vote")) {
            return address(new Vote());
        }
        if (id == keccak256("GroupHealth")) {
            return address(new GroupHealth());
        }
        return _deployRemainingImplementation(id);
    }

    /// @dev Second half of the name dispatch, split to keep both functions shallow under
    ///      the production profile (no optimizer, no via-ir).
    function _deployRemainingImplementation(bytes32 id) private returns (address) {
        if (id == keccak256("SpecificGroupStrategy")) {
            return address(new SpecificGroupStrategy());
        }
        if (id == keccak256("DefaultStrategy")) {
            return address(new DefaultStrategy());
        }
        if (id == keccak256("RebasedStakedCelo")) {
            return address(new RebasedStakedCelo());
        }
        if (id == keccak256("MultiSig")) {
            return address(new MultiSig(vm.envUint("TIME_LOCK_MIN_DELAY")));
        }
        revert("UpgradeImplementation: unknown CONTRACT");
    }
}
