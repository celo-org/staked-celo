// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of
///         `describe("Account") > describe("#setAllowedToVoteOverMaxNumberOfGroups()")`.
contract AccountSetAllowedToVoteOverMaxNumberOfGroupsTest is AccountTestBase {
    function test_setAllowedToVoteOverMaxNumberOfGroups_RevertsWhenNotCalledByOwner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        account.setAllowedToVoteOverMaxNumberOfGroups(true);
    }

    function test_setAllowedToVoteOverMaxNumberOfGroups_SetsAllowedToVoteOverMaxNumberOfGroupsCorrectly()
        public
    {
        assertFalse(celoElection.allowedToVoteOverMaxNumberOfGroups(address(account)));

        vm.prank(account.owner());
        account.setAllowedToVoteOverMaxNumberOfGroups(true);

        assertTrue(celoElection.allowedToVoteOverMaxNumberOfGroups(address(account)));
    }

    function test_setAllowedToVoteOverMaxNumberOfGroups_EmitsAllowedToVoteOverMaxNumberOfGroupsSetEventWhenSetToTrue()
        public
    {
        vm.expectEmit(true, true, true, true);
        emit AllowedToVoteOverMaxNumberOfGroupsSet(true);
        vm.prank(account.owner());
        account.setAllowedToVoteOverMaxNumberOfGroups(true);
    }

    function test_setAllowedToVoteOverMaxNumberOfGroups_EmitsAllowedToVoteOverMaxNumberOfGroupsSetEventWhenSetToFalse()
        public
    {
        vm.prank(account.owner());
        account.setAllowedToVoteOverMaxNumberOfGroups(true);

        vm.expectEmit(true, true, true, true);
        emit AllowedToVoteOverMaxNumberOfGroupsSet(false);
        vm.prank(account.owner());
        account.setAllowedToVoteOverMaxNumberOfGroups(false);
    }
}
