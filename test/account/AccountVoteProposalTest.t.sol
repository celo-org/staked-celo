// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./AccountTestBase.sol";

/// @notice Port of `describe("Account") > describe("#voteProposal")`.
contract AccountVoteProposalTest is AccountTestBase {
    /// @dev The original attached the MockRegistry ABI to the real Registry and wrote the
    ///      MockGovernance address into it as the Registry owner.
    function _registerMockGovernance() private {
        address registryOwner = celoRegistry.owner();
        vm.prank(registryOwner);
        celoRegistry.setAddressFor("Governance", address(mockGovernance));
    }

    function test_voteProposal_ShouldShouldRevertWhenNotCalledByManager() public {
        vm.prank(nonManager);
        vm.expectRevert(abi.encodeWithSelector(Managed.CallerNotManager.selector, nonManager));
        account.votePartially(3, 4, 5, 6, 7);
    }

    function test_voteProposal_ShouldPassCorrectValuesToGovernanceContract() public {
        _registerMockGovernance();

        vm.prank(managerSigner);
        account.votePartially(1, 0, 5, 6, 7);

        assertEq(mockGovernance.proposalId(), 1);
        assertEq(mockGovernance.index(), 0);
        assertEq(mockGovernance.yesVotes(), 5);
        assertEq(mockGovernance.noVotes(), 6);
        assertEq(mockGovernance.abstainVotes(), 7);
    }

    function test_voteProposal_EmitsVotedPartiallyEventWithCorrectParameters() public {
        _registerMockGovernance();

        _expectEmitFrom(address(account));
        emit VotedPartially(1, 100, 50, 25);
        vm.prank(managerSigner);
        account.votePartially(1, 0, 100, 50, 25);
    }
}
