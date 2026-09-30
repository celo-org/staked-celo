// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Tests for `Account.setAllowedToVoteOverMaxNumberOfGroups`.
contract AccountSetAllowedToVoteOverMaxNumberOfGroupsTest is AccountTestBase {
    /// @dev The call is made by the test contract, which is not the owner, and the ownership
    ///      revert is asserted.
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
