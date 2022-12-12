//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

/**
 * @notice This is a simple mock exposing the Manager-facing Account API as
 * simple functions that
 * 1. Record their arguments for functions called by Manager.
 * 2. Can have their output mocked for functions read by Manager.
 */
// solhint-disable max-states-count
contract MockAccount {
    address[] public lastVotedGroups;
    uint256[] public lastVotes;

    address[] public lastTransferFromGroups;
    uint256[] public lastTransferFromVotes;
    address[] public lastTransferToGroups;
    uint256[] public lastTransferToVotes;

    address[] public lastWithdrawnGroups;
    uint256[] public lastWithdrawals;
    address public lastWithdrawalBeneficiary;

    mapping(address => uint256) public getCeloForGroup;
    uint256 public getTotalCelo;

    mapping(address => uint256) public scheduledVotesForGroup;

    uint256 public proposalIdVoted;
    uint256 public indexVoted;
    uint256 public yesVotesVoted;
    uint256 public noVotesVoted;
    uint256 public abstainVoteVoted;

    function scheduleVotes(address[] calldata groups, uint256[] calldata votes) external payable {
        lastVotedGroups = groups;
        lastVotes = votes;
    }

    function getLastScheduledVotes() external view returns (address[] memory, uint256[] memory) {
        return (lastVotedGroups, lastVotes);
    }

    function scheduleWithdrawals(
        address beneficiary,
        address[] calldata groups,
        uint256[] calldata withdrawals
    ) external {
        lastWithdrawnGroups = groups;
        lastWithdrawals = withdrawals;
        lastWithdrawalBeneficiary = beneficiary;
    }

    function getLastScheduledWithdrawals()
        external
        view
        returns (
            address[] memory,
            uint256[] memory,
            address
        )
    {
        return (lastWithdrawnGroups, lastWithdrawals, lastWithdrawalBeneficiary);
    }

    function setCeloForGroup(address group, uint256 amount) external {
        getCeloForGroup[group] = amount;
    }

    function setTotalCelo(uint256 amount) external {
        getTotalCelo = amount;
    }

    function setScheduledVotes(address group, uint256 amount) external {
        scheduledVotesForGroup[group] = amount;
    }

    function votePartially(
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) public {
        proposalIdVoted = proposalId;
        indexVoted = index;
        yesVotesVoted = yesVotes;
        noVotesVoted = noVotes;
        abstainVoteVoted = abstainVotes;
    }

    function scheduleTransfer(
        address[] calldata fromGroups,
        uint256[] calldata fromVotes,
        address[] calldata toGroups,
        uint256[] calldata toVotes
    ) external {
        lastTransferFromGroups = fromGroups;
        lastTransferFromVotes = fromVotes;
        lastTransferToGroups = toGroups;
        lastTransferToVotes = toVotes;
    }

    function getLastTransferValues()
        external
        view
        returns (
            address[] memory,
            uint256[] memory,
            address[] memory,
            uint256[] memory
        )
    {
        return (
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes
        );
    }
}
