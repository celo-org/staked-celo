// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of
///         `describe("Account") > describe("#setAllowedToVoteOverMaxNumberOfGroups()")`.
contract AccountSetAllowedToVoteOverMaxNumberOfGroupsTest is AccountTestBase {
    /// @dev Strengthened port: the original assertion never ran. It was missing the `await` on
    ///      `expect(...).revertedWith(...)`, and it called through the owner signer, so the
    ///      call it asserted on would not have reverted anyway. Here the call really is made
    ///      by a non-owner and the revert really is asserted.
    function test_setAllowedToVoteOverMaxNumberOfGroups_RevertsWhenNotCalledByOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        account.setAllowedToVoteOverMaxNumberOfGroups(true);
    }

    function test_setAllowedToVoteOverMaxNumberOfGroups_SetsAllowedToVoteOverMaxNumberOfGroupsCorrectly()
        public
    {
        address accountOwner = account.owner();
        assertFalse(celoElection.allowedToVoteOverMaxNumberOfGroups(address(account)));

        vm.prank(accountOwner);
        account.setAllowedToVoteOverMaxNumberOfGroups(true);

        assertTrue(celoElection.allowedToVoteOverMaxNumberOfGroups(address(account)));
    }

    function test_setAllowedToVoteOverMaxNumberOfGroups_EmitsAllowedToVoteOverMaxNumberOfGroupsSetEventWhenSetToTrue()
        public
    {
        address accountOwner = account.owner();

        _expectEmitFrom(address(account));
        emit AllowedToVoteOverMaxNumberOfGroupsSet(true);
        vm.prank(accountOwner);
        account.setAllowedToVoteOverMaxNumberOfGroups(true);
    }

    function test_setAllowedToVoteOverMaxNumberOfGroups_EmitsAllowedToVoteOverMaxNumberOfGroupsSetEventWhenSetToFalse()
        public
    {
        address accountOwner = account.owner();

        vm.prank(accountOwner);
        account.setAllowedToVoteOverMaxNumberOfGroups(true);

        _expectEmitFrom(address(account));
        emit AllowedToVoteOverMaxNumberOfGroupsSet(false);
        vm.prank(accountOwner);
        account.setAllowedToVoteOverMaxNumberOfGroups(false);
    }
}
