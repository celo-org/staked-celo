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
    mapping(address => uint256) public scheduledRevokeForGroup;
    mapping(address => uint256) public scheduledWithdrawalsForGroup;
    mapping(address => uint256) public votesForGroup;

    uint256 public proposalIdVoted;
    uint256 public indexVoted;
    uint256 public yesVotesVoted;
    uint256 public noVotesVoted;
    uint256 public abstainVoteVoted;

    /**
     * @notice Used when attempting to schedule more withdrawals
     * than CELO available to the contract.
     * @param group The offending group.
     * @param celoAvailable CELO available to the group.
     * @param celoToWithdraw total amount of CELO that would be scheduled to be withdrawn.
     */
    error WithdrawalAmountTooHigh(address group, uint256 celoAvailable, uint256 celoToWithdraw);

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function scheduleVotes(address[] calldata groups, uint256[] calldata votes) external payable {
        lastVotedGroups = groups;
        lastVotes = votes;
    }

    function scheduleWithdrawals(
        address beneficiary,
        address[] calldata groups,
        uint256[] calldata withdrawals
    ) external {
        // Validate that each group has enough CELO for the withdrawal
        // This matches the validation in the real Account contract
        for (uint256 i = 0; i < withdrawals.length; i++) {
            uint256 celoAvailableForGroup = getCeloForGroup[groups[i]];
            if (celoAvailableForGroup < withdrawals[i]) {
                revert WithdrawalAmountTooHigh(groups[i], celoAvailableForGroup, withdrawals[i]);
            }
        }

        lastWithdrawnGroups = groups;
        lastWithdrawals = withdrawals;
        lastWithdrawalBeneficiary = beneficiary;
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

    function setScheduledRevokeForGroup(address group, uint256 amount) external {
        scheduledRevokeForGroup[group] = amount;
    }

    function setScheduledWithdrawalsForGroup(address group, uint256 amount) external {
        scheduledWithdrawalsForGroup[group] = amount;
    }

    function setVotesForGroup(address group, uint256 amount) external {
        votesForGroup[group] = amount;
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

    function getLastScheduledVotes() external view returns (address[] memory, uint256[] memory) {
        return (lastVotedGroups, lastVotes);
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
}
