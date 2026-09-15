// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./MultiSigTestBase.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Port of `describe("MultiSig") > describe("#constructor")` and `describe("#initialize")`.
contract MultiSigInitializeTest is MultiSigTestBase {
    /// @dev Implementation address behind the already-deployed proxy (EIP-1967 slot).
    ///      Read separately from `_multiSigInitialize` so that an armed `vm.expectRevert`
    ///      sits immediately before the CREATE and cannot be consumed by the `vm.load`.
    function _multiSigImpl() internal view returns (address) {
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        return address(uint160(uint256(vm.load(address(multiSig), implSlot))));
    }

    /// @dev Deploy a new MultiSig behind proxy (for initialize tests), reusing `msImpl`.
    function _multiSigInitialize(
        address msImpl,
        address[] memory _owners,
        uint256 _required
    ) internal returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address[],uint256,uint256)")),
            _owners,
            _required,
            7 * DAY
        );
        ERC1967Proxy proxy = new ERC1967Proxy(msImpl, initData);
        return address(proxy);
    }

    // =========================================================================
    //                       #constructor (1)
    // =========================================================================

    function test_Constructor_ShouldHaveSetMinDelayTo3Days() public {
        assertEq(msig.minDelay(), 3 * DAY);
    }

    // =========================================================================
    //                       #initialize (7)
    // =========================================================================

    function test_Initialize_ShouldHaveSetOwners() public {
        address[] memory currentOwners = msig.getOwners();
        assertEq(currentOwners.length, owners.length);
        assertEq(currentOwners[0], owners[0]);
        assertEq(currentOwners[1], owners[1]);
    }

    function test_Initialize_ShouldHaveSetDelay() public {
        assertEq(msig.delay(), delay);
    }

    function test_Initialize_ShouldHaveSetRequired() public {
        assertEq(msig.required(), REQUIRED_SIGS);
    }

    function test_Initialize_ShouldNotBeCallableAgain() public {
        vm.expectRevert("Initializable: contract is already initialized");
        msig.initialize(owners, REQUIRED_SIGS, 3 * DAY);
    }

    function test_Initialize_ShouldFailIfOwnersCountIsZero() public {
        address msImpl = _multiSigImpl();
        address[] memory emptyOwners = new address[](0);
        // Bare expectRevert, as in the original: InvalidRequirement bubbles up through the
        // proxy delegatecall, so the selector cannot be matched on the CREATE.
        vm.expectRevert();
        _multiSigInitialize(msImpl, emptyOwners, 10);
    }

    function test_Initialize_ShouldFailIfOwnersLessThanRequired() public {
        address msImpl = _multiSigImpl();
        // Bare expectRevert, as in the original: InvalidRequirement bubbles up through the
        // proxy delegatecall, so the selector cannot be matched on the CREATE.
        vm.expectRevert();
        _multiSigInitialize(msImpl, owners, 10);
    }

    function test_Initialize_ShouldFailIfRequiredIsZero() public {
        address msImpl = _multiSigImpl();
        // Bare expectRevert, as in the original: InvalidRequirement bubbles up through the
        // proxy delegatecall, so the selector cannot be matched on the CREATE.
        vm.expectRevert();
        _multiSigInitialize(msImpl, owners, 0);
    }
}
