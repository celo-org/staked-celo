// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";

import "./interfaces/IAccount.sol";
import "./interfaces/IStakedCelo.sol";

contract Vote is UUPSOwnableUpgradeable, UsingRegistryUpgradeable {
    struct ProposalVoteRecord {
        uint256 proposalId;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
    }

    struct Voter {
        // Key of proposalId
        mapping(uint256 => VoterRecord) proposalVotes;
        uint256[] votedProposalIds;
    }

    struct VoterRecord {
        uint256 proposalId;
        uint256[] weights;
        IGovernance.VoteValue[] values;
        uint256 totalWeighs;
    }

    /**
     * @notice Emitted when an account votes for governance proposal.
     * @param voter The voter's address.
     * @param voteValues The voter's vote value (Proposals.VoteValue).
     * @param weights The voter's weight.
     */
    event ProposalVoted(
        address voter,
        uint256 proposalId,
        IGovernance.VoteValue[] voteValues,
        uint256[] weights
    );

    event LockedStCeloInVoting(address account, uint256 lockedCelo);

    /**
     * @notice An instance of the StakedCelo contract this Manager manages.
     */
    IStakedCelo internal stakedCelo;

    /**
     * @notice An instance of the Account contract this Manager manages.
     */
    IAccount internal account;

    mapping(uint256 => ProposalVoteRecord) private voteRecords;
    mapping(address => Voter) private voters;
    // proposalId => proposal timestamp
    mapping(uint256 => uint256) public proposalTimestamps;
    uint256 public referendumDuration;

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _registry The address of the Celo registry.
     * @param _owner The address of the contract owner.
     */
    function initialize(address _registry, address _owner) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @dev Manager, Account and StakedCelo all reference each other
     * so we need a way of setting these after all contracts are
     * deployed and initialized.
     * @param _stakedCelo the address of the StakedCelo contract.
     * @param _account The address of the Account contract.
     */
    function setDependencies(address _stakedCelo, address _account) external onlyOwner {
        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
    }

    function voteProposal(
        uint256 proposalId,
        uint256 index,
        IGovernance.VoteValue[] memory voteValues,
        uint256[] memory weights
    ) public {
        require(voteValues.length == weights.length, "Incorrect length");
        require(voteValues.length <= 3, "VoteValue values allowed");

        uint256 stakedCeloBalance = stakedCelo.balanceOf(msg.sender);
        require(stakedCeloBalance > 0, "No staked celo");
        uint256 totalWeights = getTotalWeightRequested(weights);
        require(totalWeights <= toCelo(stakedCeloBalance), "Not enough celo to vote");

        Voter storage voter = voters[msg.sender];

        VoterRecord storage previousVoterRecord = voter.proposalVotes[proposalId];
        VoterRecord memory currentVoterRecord = VoterRecord(
            proposalId,
            weights,
            voteValues,
            totalWeights
        );
        ProposalVoteRecord memory proposalVoteRecord = voteRecords[proposalId];

        updateProposalVoteRecord(proposalVoteRecord, previousVoterRecord, currentVoterRecord);

        uint256[] memory proposalWeights = new uint256[](3);
        proposalWeights[0] = proposalVoteRecord.yesVotes;
        proposalWeights[1] = proposalVoteRecord.noVotes;
        proposalWeights[2] = proposalVoteRecord.abstainVotes;

        stakedCelo.lockBalance(msg.sender, stakedCeloBalance);
        account.voteProposal(proposalId, index, generateVoteProposalValues(), proposalWeights);

        voteRecords[proposalId] = ProposalVoteRecord(
            proposalId,
            proposalWeights[0],
            proposalWeights[1],
            proposalWeights[2]
        );

        if (previousVoterRecord.proposalId == 0) {
            voter.votedProposalIds.push(proposalId);
        }

        voter.proposalVotes[proposalId] = currentVoterRecord;

        emit ProposalVoted(msg.sender, proposalId, voteValues, weights);

        if (proposalTimestamps[proposalId] == 0) {
            proposalTimestamps[proposalId] = getProposalTimestamp(proposalId);
        }
    }

    function revokeVotes(uint256 proposalId, uint256 index) public {
        voteProposal(proposalId, index, new IGovernance.VoteValue[](0), new uint256[](0));
    }

    function getProposalTimestamp(uint256 proposalId) public view returns (uint256) {
        (, , uint256 timestamp, , ) = getGovernance().getProposal(proposalId);
        return timestamp;
    }

    function generateVoteProposalValues() private pure returns (IGovernance.VoteValue[] memory) {
        IGovernance.VoteValue[] memory voteProposalValues = new IGovernance.VoteValue[](3);
        voteProposalValues[0] = IGovernance.VoteValue.Yes;
        voteProposalValues[1] = IGovernance.VoteValue.No;
        voteProposalValues[2] = IGovernance.VoteValue.Abstain;

        return voteProposalValues;
    }

    /**
     * @notice updates weightsToUpdate with VoterRecord
     * @param proposalVoteRecord expect
     * @param previousVoterRecord expect
     * @param currentVoterRecord expect
     */
    function updateProposalVoteRecord(
        ProposalVoteRecord memory proposalVoteRecord,
        VoterRecord storage previousVoterRecord,
        VoterRecord memory currentVoterRecord
    ) private view {
        for (uint256 i = 0; i < previousVoterRecord.values.length; i++) {
            if (previousVoterRecord.values[i] == IGovernance.VoteValue.Yes) {
                proposalVoteRecord.yesVotes -= previousVoterRecord.weights[i];
            } else if (previousVoterRecord.values[i] == IGovernance.VoteValue.No) {
                proposalVoteRecord.noVotes -= previousVoterRecord.weights[i];
            } else if (previousVoterRecord.values[i] == IGovernance.VoteValue.Abstain) {
                proposalVoteRecord.abstainVotes -= previousVoterRecord.weights[i];
            }
        }

        for (uint256 i = 0; i < currentVoterRecord.values.length; i++) {
            if (currentVoterRecord.values[i] == IGovernance.VoteValue.Yes) {
                proposalVoteRecord.yesVotes += currentVoterRecord.weights[i];
            } else if (currentVoterRecord.values[i] == IGovernance.VoteValue.No) {
                proposalVoteRecord.noVotes += currentVoterRecord.weights[i];
            } else if (currentVoterRecord.values[i] == IGovernance.VoteValue.Abstain) {
                proposalVoteRecord.abstainVotes += currentVoterRecord.weights[i];
            }
        }
    }

    function getLockedStCeloInVoting(address accountAddress) public returns (uint256 lockedAmount) {
        Voter storage voter = voters[accountAddress];

        uint256 i = voter.votedProposalIds.length;
        while (i > 0) {
            uint256 proposalId = voter.votedProposalIds[--i];
            uint256 proposalTimestamp = proposalTimestamps[proposalId];

            if (proposalTimestamp == 0) {
                voter.votedProposalIds.pop();
                continue;
            }

            if (block.timestamp < proposalTimestamp + referendumDuration) {
                lockedAmount = Math.max(lockedAmount, voter.proposalVotes[proposalId].totalWeighs);
            } else {
                voter.votedProposalIds.pop();
                delete proposalTimestamps[proposalId];
            }
        }

        uint256 result = toStakedCelo(lockedAmount);
        emit LockedStCeloInVoting(accountAddress, result);
        return result;
    }

    function getLockedStCeloInVotingView(address accountAddress)
        public
        view
        returns (uint256 lockedAmount)
    {
        Voter storage voter = voters[accountAddress];

        uint256 i = voter.votedProposalIds.length;
        while (i > 0) {
            uint256 proposalId = voter.votedProposalIds[--i];
            uint256 proposalTimestamp = proposalTimestamps[proposalId];

            if (proposalTimestamp == 0) {
                continue;
            }

            if (block.timestamp < proposalTimestamp + referendumDuration) {
                lockedAmount = Math.max(lockedAmount, voter.proposalVotes[proposalId].totalWeighs);
            }
        }

        return toStakedCelo(lockedAmount);
    }

    /**
     * @notice Returns sum of input weights.
     * @param weights The weights to sum up.
     * @return The sum of input weights.
     */
    function getTotalWeightRequested(uint256[] memory weights) private pure returns (uint256) {
        uint256 totalVotesRequested = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalVotesRequested += weights[i];
        }

        return totalVotesRequested;
    }

    function setReferendumDuration(uint256 newReferendumDuration) public onlyOwner {
        referendumDuration = newReferendumDuration;
    }

    function getVoteWeight(address accountAddress) public view returns (uint256) {
        uint256 stakedCeloBalance = stakedCelo.balanceOf(accountAddress);
        return toCelo(stakedCeloBalance);
    }

    function getVoteRecord(uint256 proposalId) public view returns (ProposalVoteRecord memory) {
        return voteRecords[proposalId];
    }

    /**
     * @notice Computes the amount of stCELO that should be minted for a given
     * amount of CELO deposited.
     * @param celoAmount The amount of CELO deposited.
     * @return The amount of stCELO that should be minted.
     */
    function toStakedCelo(uint256 celoAmount) public view returns (uint256) {
        uint256 stCeloSupply = stakedCelo.totalSupply();
        uint256 celoBalance = account.getTotalCelo();

        if (stCeloSupply == 0 || celoBalance == 0) {
            return celoAmount;
        }

        return (celoAmount * stCeloSupply) / celoBalance;
    }

    /**
     * @notice Computes the amount of CELO that should be withdrawn for a given
     * amount of stCELO burned.
     * @param stCeloAmount The amount of stCELO burned.
     * @return The amount of CELO that should be withdrawn.
     */
    function toCelo(uint256 stCeloAmount) public view returns (uint256) {
        uint256 stCeloSupply = stakedCelo.totalSupply();
        uint256 celoBalance = account.getTotalCelo();

        if (stCeloSupply == 0 || celoBalance == 0) {
            return stCeloAmount;
        }

        return (stCeloAmount * celoBalance) / stCeloSupply;
    }
}
