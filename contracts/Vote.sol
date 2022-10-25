// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./Managed.sol";

import "./interfaces/IAccount.sol";
import "./interfaces/IStakedCelo.sol";
import "hardhat/console.sol";

contract Vote is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed {
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
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
    }

    /**
     * @notice Emitted when an account votes for governance proposal.
     * @param voter The voter's address.
     * @param proposalId The proposal UIID.
     * @param yesVotes The yes votes.
     * @param noVotes The no votes.
     * @param abstainVotes The abstain votes.
     */
    event ProposalVoted(
        address voter,
        uint256 proposalId,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
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
    function initialize(
        address _registry,
        address _owner,
        address manager
    ) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
        __Managed_init(manager);
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
        address accountVoter,
        uint256 proposalId,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    )
        public
        onlyManager
        returns (
            uint256 stakedCeloBalance,
            uint256 totalYesVotes,
            uint256 totalNoVotes,
            uint256 totalAbstainVotes
        )
    {
        stakedCeloBalance =
            stakedCelo.balanceOf(accountVoter) +
            stakedCelo.lockedBalanceOf(accountVoter);
        require(stakedCeloBalance > 0, "No staked celo");
        uint256 totalWeights = yesVotes + noVotes + abstainVotes;
        console.log("stakedCeloBalance: %s", stakedCeloBalance);
        console.log("accountVoter: %s", accountVoter);
        console.log("celoBalance: %s", toCelo(stakedCeloBalance));
        console.log("totalWeights: %s", totalWeights);
        require(totalWeights <= toCelo(stakedCeloBalance), "Not enough celo to vote");

        Voter storage voter = voters[accountVoter];

        VoterRecord storage previousVoterRecord = voter.proposalVotes[proposalId];
        VoterRecord memory currentVoterRecord = VoterRecord(
            proposalId,
            yesVotes,
            noVotes,
            abstainVotes
        );
        ProposalVoteRecord memory proposalVoteRecord = voteRecords[proposalId];

        // Subtract previous vote.
        proposalVoteRecord.yesVotes -= previousVoterRecord.yesVotes;
        proposalVoteRecord.noVotes -= previousVoterRecord.noVotes;
        proposalVoteRecord.abstainVotes -= previousVoterRecord.abstainVotes;

        // Add new vote.
        proposalVoteRecord.yesVotes += yesVotes;
        proposalVoteRecord.noVotes += noVotes;
        proposalVoteRecord.abstainVotes += abstainVotes;

        voteRecords[proposalId] = ProposalVoteRecord(
            proposalId,
            proposalVoteRecord.yesVotes,
            proposalVoteRecord.noVotes,
            proposalVoteRecord.abstainVotes
        );

        if (previousVoterRecord.proposalId == 0) {
            voter.votedProposalIds.push(proposalId);
        }

        voter.proposalVotes[proposalId] = currentVoterRecord;

        emit ProposalVoted(accountVoter, proposalId, yesVotes, noVotes, abstainVotes);

        if (proposalTimestamps[proposalId] == 0) {
            proposalTimestamps[proposalId] = getProposalTimestamp(proposalId);
        }

        return (
            stakedCeloBalance,
            proposalVoteRecord.yesVotes,
            proposalVoteRecord.noVotes,
            proposalVoteRecord.abstainVotes
        );
    }

    function revokeVotes(address accountVoter, uint256 proposalId)
        public
        onlyManager
        returns (
            uint256 stakedCeloBalance,
            uint256 totalYesVotes,
            uint256 totalNoVotes,
            uint256 totalAbstainVotes
        )
    {
        return voteProposal(accountVoter, proposalId, 0, 0, 0);
    }

    function getProposalTimestamp(uint256 proposalId) public view returns (uint256) {
        (, , uint256 timestamp, , ) = getGovernance().getProposal(proposalId);
        return timestamp;
    }

    function getLockedStCeloInVoting(address accountAddress)
        public
        onlyManager
        returns (uint256 lockedAmount)
    {
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
                VoterRecord storage voterRecord = voter.proposalVotes[proposalId];
                lockedAmount = Math.max(
                    lockedAmount,
                    voterRecord.yesVotes + voterRecord.noVotes + voterRecord.abstainVotes
                );
            } else {
                voter.votedProposalIds.pop();
                delete proposalTimestamps[proposalId];
            }
        }

        uint256 stCelo = toStakedCelo(lockedAmount);
        emit LockedStCeloInVoting(accountAddress, stCelo);
        return stCelo;
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
                VoterRecord storage voterRecord = voter.proposalVotes[proposalId];
                lockedAmount = Math.max(
                    lockedAmount,
                    voterRecord.yesVotes + voterRecord.noVotes + voterRecord.abstainVotes
                );
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
