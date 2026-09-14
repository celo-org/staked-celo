// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#scheduleVotes()")`.
contract AccountScheduleVotesTest is AccountTestBase {
    function test_scheduleVotes_AssignsVotesToAGivenGroup() public {
        _scheduleVotes(_addrs(groupAddresses[0]), _amounts(100), 100);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 100);
    }

    function test_scheduleVotes_EmitsAVotesScheduledEvent() public {
        _expectEmitFrom(address(account));
        emit VotesScheduled(groupAddresses[0], 100);
        _scheduleVotes(_addrs(groupAddresses[0]), _amounts(100), 100);
    }

    function test_scheduleVotes_AssignsVotesToMultipleGroups() public {
        _scheduleVotes(_allGroups(), _amounts(100, 30, 70), 200);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 100);
        assertEq(account.scheduledVotesForGroup(groupAddresses[1]), 30);
        assertEq(account.scheduledVotesForGroup(groupAddresses[2]), 70);
    }

    function test_scheduleVotes_EmitsMultipleVotesScheduledEvents() public {
        _expectEmitFrom(address(account));
        emit VotesScheduled(groupAddresses[0], 100);
        _expectEmitFrom(address(account));
        emit VotesScheduled(groupAddresses[1], 30);
        _expectEmitFrom(address(account));
        emit VotesScheduled(groupAddresses[2], 70);
        _scheduleVotes(_allGroups(), _amounts(100, 30, 70), 200);
    }

    function test_scheduleVotes_AggregatesPendingVotesAcrossInvocations() public {
        _scheduleVotes(_addrs(groupAddresses[0], groupAddresses[2]), _amounts(100, 30), 130);
        _scheduleVotes(_addrs(groupAddresses[2], groupAddresses[1]), _amounts(50, 70), 120);
        assertEq(account.scheduledVotesForGroup(groupAddresses[0]), 100);
        assertEq(account.scheduledVotesForGroup(groupAddresses[1]), 70);
        assertEq(account.scheduledVotesForGroup(groupAddresses[2]), 80);
    }

    function test_scheduleVotes_RevertsWhenTotalVotesAreMoreThanValueSent() public {
        address[] memory groups = _allGroups();
        uint256[] memory votes = _amounts(100, 31, 70);
        vm.prank(managerSigner);
        vm.expectRevert(abi.encodeWithSelector(Account.TotalVotesMismatch.selector, 200, 201));
        account.scheduleVotes{value: 200}(groups, votes);
    }

    function test_scheduleVotes_RevertsWhenTotalVotesAreLessThanValueSent() public {
        address[] memory groups = _allGroups();
        uint256[] memory votes = _amounts(100, 29, 70);
        vm.prank(managerSigner);
        vm.expectRevert(abi.encodeWithSelector(Account.TotalVotesMismatch.selector, 200, 199));
        account.scheduleVotes{value: 200}(groups, votes);
    }

    function test_scheduleVotes_RevertsWhenThereAreMoreVotesThanGroups() public {
        address[] memory groups = _addrs(groupAddresses[0]);
        uint256[] memory votes = _amounts(100, 30);
        vm.prank(managerSigner);
        vm.expectRevert(
            abi.encodeWithSelector(Account.GroupsAndVotesArrayLengthsMismatch.selector)
        );
        account.scheduleVotes{value: 100}(groups, votes);
    }

    function test_scheduleVotes_RevertsWhenThereAreMoreGroupsThanVotes() public {
        address[] memory groups = _addrs(groupAddresses[0], groupAddresses[1]);
        uint256[] memory votes = _amounts(100);
        vm.prank(managerSigner);
        vm.expectRevert(
            abi.encodeWithSelector(Account.GroupsAndVotesArrayLengthsMismatch.selector)
        );
        account.scheduleVotes{value: 100}(groups, votes);
    }

    function test_scheduleVotes_CannotBeCalledByANonManagerAddress() public {
        address[] memory groups = _allGroups();
        uint256[] memory votes = _amounts(100, 30, 70);
        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        account.scheduleVotes{value: 200}(groups, votes);
    }
}
