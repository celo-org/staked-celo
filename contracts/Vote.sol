// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./Managed.sol";

import "./interfaces/IAccount.sol";
import "./interfaces/IStakedCelo.sol";

/**
 * @title Handles governance voting for CELO in protocol.
 */
contract Vote is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed {
    /**
     * @notice Keeps track of total votes for proposal (votes of Account contract).
     * @param proposalId The proposal UUID.
     * @param yesVotes The yes votes weight.
     * @param noVotes The no votes weight.
     * @param abstainVotes The abstain votes weight.
     */
    struct ProposalVoteRecord {
        uint256 proposalId;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
    }

    /**
     * @notice Votes of account.
     * @param proposalVotes Votes per proposal UUID.
     * @param votedProposalIds History of voted proposals that are still active.
     */
    struct Voter {
        // Key of proposalId
        mapping(uint256 => VoterRecord) proposalVotes;
        uint256[] votedProposalIds;
    }

    /**
     * @notice Voter's votes for particular proposal.
     * @param proposalId The proposal UIID.
     * @param yesVotes The yes votes.
     * @param noVotes The no votes.
     * @param abstainVotes The abstain votes.
     */
    struct VoterRecord {
        uint256 proposalId;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
    }

    /**
     * @notice An instance of the StakedCelo contract this Manager manages.
     */
    IStakedCelo internal stakedCelo;

    /**
     * @notice An instance of the Account contract this Manager manages.
     */
    IAccount internal account;

    /**
     * @notice Votes of Account's contract per proposal.
     */
    mapping(uint256 => ProposalVoteRecord) private voteRecords;

    /**
     * @notice History of all voters.
     */
    mapping(address => Voter) private voters;

    /**
     * @notice Timestamps of every voted proposal.
     */
    mapping(uint256 => uint256) public proposalTimestamps;

    /**
     * @notice Emitted when an account votes for governance proposal.
     * @param voter The voter's address.
     * @param proposalId The proposal UIID.
     * @param yesVotes The yes votes.
     * @param noVotes The no votes.
     * @param abstainVotes The abstain votes.
     */
    event ProposalVoted(
        address indexed voter,
        uint256 indexed proposalId,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    );

    /**
     * @notice Emitted when unlock of stCELO is requested.
     * @param account The account's address.
     * @param lockedCelo The stCELO that is still being locked.
     */
    event LockedStCeloInVoting(address account, uint256 lockedCelo);

    /**
     * @notice Used when attempting to vote when there is no stCELO.
     * @param account The account's address.
     */
    error NoStakedCelo(address account);

    /**
     * @notice Used when attempting to vote when there is not enough of stCELO.
     * @param account The account's address.
     */
    error NotEnoughStakedCelo(address account);

    /**
     * @notice Used when attempting to pass in address zero where not allowed.
     */
    error AddressZeroNotAllowed();

    /**
     * @notice Used when attempting to delete voter's proposal id with incorrect index.
     */
    error IncorrectIndex();

    /**
     * @notice Used when attempting to delete voter's proposal id when proposal is not expired.
     */
    error ProposalNotExpired();

    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _registry The address of the Celo Registry.
     * @param _owner The address of the contract owner.
     * @param _manager The address of the contract manager.
     */
    function initialize(
        address _registry,
        address _owner,
        address _manager
    ) external initializer {
        __UsingRegistry_init(_registry);
        __Managed_init(_manager);
        _transferOwnership(_owner);
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @dev The StakedCelo contracts all reference each other
     * so we need a way of setting these after all contracts are
     * deployed and initialized.
     * @param _stakedCelo the address of the StakedCelo contract.
     * @param _account The address of the Account contract.
     */
    function setDependencies(address _stakedCelo, address _account) external onlyOwner {
        if (_stakedCelo == address(0) || _account == address(0)) {
            revert AddressZeroNotAllowed();
        }
        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
    }

    /**
     * Deletes proposalId from voter's history if proposal expired.
     * @param voter The voter address.
     * @param proposalId The proposal id.
     * @param index Index of voter's proposal id.
     */
    function deleteExpiredVoterProposalId(
        address voter,
        uint256 proposalId,
        uint256 index
    ) external {
        Voter storage voterStruct = voters[voter];

        uint256 proposalIdOnChain = voterStruct.votedProposalIds[index];
        if (proposalIdOnChain == 0 || proposalIdOnChain != proposalId) {
            revert IncorrectIndex();
        }

        uint256 proposalTimestamp = proposalTimestamps[proposalId];
        if (proposalTimestamp != 0) {
            deleteExpiredProposalTimestamp(proposalId);
        }

        voterStruct.votedProposalIds[index] = voterStruct.votedProposalIds[
            voterStruct.votedProposalIds.length - 1
        ];
        voterStruct.votedProposalIds.pop();
    }

    /**
     * @notice Returns the storage, major, minor, and patch version of the contract.
     * @return Storage version of the contract.
     * @return Major version of the contract.
     * @return Minor version of the contract.
     * @return Patch version of the contract.
     */
    function getVersionNumber()
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (1, 1, 2, 1);
    }

    /**
     * @notice Votes on a proposal in the referendum stage.
     * @param accountVoter The account that is voting.
     * @param proposalId The ID of the proposal to vote on.
     * @param yesVotes The yes votes weight.
     * @param noVotes The no votes weight.
     * @param abstainVotes The abstain votes weight.
     * @return totalWeights Account's staked celo balance.
     * @return totalYesVotes SUM of all AccountContract yes votes for proposal.
     * @return totalNoVotes SUM of all AccountContract no votes for proposal.
     * @return totalAbstainVotes SUM of all AccountContract abstain votes for proposal.
     */
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
            uint256,
            uint256 totalYesVotes,
            uint256 totalNoVotes,
            uint256 totalAbstainVotes
        )
    {
        uint256 stakedCeloBalance = stakedCelo.balanceOf(accountVoter) +
            stakedCelo.lockedVoteBalanceOf(accountVoter);
        if (stakedCeloBalance == 0) {
            revert NoStakedCelo(accountVoter);
        }
        uint256 totalWeights = yesVotes + noVotes + abstainVotes;
        if (totalWeights > toCelo(stakedCeloBalance)) {
            revert NotEnoughStakedCelo(accountVoter);
        }

        Voter storage voter = voters[accountVoter];

        VoterRecord storage previousVoterRecord = voter.proposalVotes[proposalId];
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

        voter.proposalVotes[proposalId] = VoterRecord(proposalId, yesVotes, noVotes, abstainVotes);

        emit ProposalVoted(accountVoter, proposalId, yesVotes, noVotes, abstainVotes);

        if (proposalTimestamps[proposalId] == 0) {
            proposalTimestamps[proposalId] = getProposalTimestamp(proposalId);
        }

        return (
            toStakedCelo(totalWeights),
            proposalVoteRecord.yesVotes,
            proposalVoteRecord.noVotes,
            proposalVoteRecord.abstainVotes
        );
    }

    /**
     * @notice Revokes votes on already voted proposal.
     * @param accountVoter The account that is voting.
     * @param proposalId The ID of the proposal to vote on.
     * @return totalYesVotes SUM of all AccountContract yes votes for proposal.
     * @return totalNoVotes SUM of all AccountContract no votes for proposal.
     * @return totalAbstainVotes SUM of all AccountContract abstain votes for proposal.
     */
    function revokeVotes(address accountVoter, uint256 proposalId)
        public
        onlyManager
        returns (
            uint256 totalYesVotes,
            uint256 totalNoVotes,
            uint256 totalAbstainVotes
        )
    {
        (, totalYesVotes, totalNoVotes, totalAbstainVotes) = voteProposal(
            accountVoter,
            proposalId,
            0,
            0,
            0
        );
        return (totalYesVotes, totalNoVotes, totalAbstainVotes);
    }

    /**
     * @notice Updates the beneficiaries voting history and returns locked stCELO in voting.
     * (This stCELO cannot be unlocked.)
     * And it will remove voted proposals from account history if appropriate.
     * @param beneficiary The beneficiary.
     * @return Currently locked stCELO in voting.
     */
    function updateHistoryAndReturnLockedStCeloInVoting(address beneficiary)
        public
        returns (uint256)
    {
        Voter storage voter = voters[beneficiary];
        uint256 lockedAmount;

        uint256 i = voter.votedProposalIds.length;
        while (i > 0) {
            uint256 proposalId = voter.votedProposalIds[--i];
            uint256 proposalTimestamp = proposalTimestamps[proposalId];

            if (proposalTimestamp == 0) {
                voter.votedProposalIds[i] = voter.votedProposalIds[
                    voter.votedProposalIds.length - 1
                ];
                voter.votedProposalIds.pop();
                continue;
            }

            if (
                block.timestamp < proposalTimestamp + getGovernance().getReferendumStageDuration()
            ) {
                VoterRecord storage voterRecord = voter.proposalVotes[proposalId];
                lockedAmount = Math.max(
                    lockedAmount,
                    voterRecord.yesVotes + voterRecord.noVotes + voterRecord.abstainVotes
                );
            } else {
                voter.votedProposalIds[i] = voter.votedProposalIds[
                    voter.votedProposalIds.length - 1
                ];
                voter.votedProposalIds.pop();
                delete proposalTimestamps[proposalId];
            }
        }

        uint256 stCELO = toStakedCelo(lockedAmount);
        emit LockedStCeloInVoting(beneficiary, stCELO);
        return stCELO;
    }

    /**
     * Deletes timestamp of expired proposal from storage.
     * @param proposalId The proposal Id.
     */
    function deleteExpiredProposalTimestamp(uint256 proposalId) public {
        uint256 proposalTimestamp = proposalTimestamps[proposalId];
        if (block.timestamp <= proposalTimestamp + getGovernance().getReferendumStageDuration()) {
            revert ProposalNotExpired();
        }

        delete proposalTimestamps[proposalId];
    }

    /**
     * @notice Returns save timestamp of proposal.
     * @param proposalId The proposal UUID.
     * @return The timestamp of proposal.
     */
    function getProposalTimestamp(uint256 proposalId) public view returns (uint256) {
        (, , uint256 timestamp, , ) = getGovernance().getProposal(proposalId);
        return timestamp;
    }

    /**
     * @notice Returns proposals still in referendum stage that voter voted on.
     * @param voter The voter.
     * @return Proposals in referendum stage.
     * @dev For up to date result call updateHistoryAndReturnLockedStCeloInVoting first.
     */
    function getVotedStillRelevantProposals(address voter) public view returns (uint256[] memory) {
        return voters[voter].votedProposalIds;
    }

    /**
     * @notice Returns currently locked stCELO in voting. (This stCELO cannot be unlocked.)
     * @param beneficiary The account.
     */
    function getLockedStCeloInVoting(address beneficiary) public view returns (uint256) {
        Voter storage voter = voters[beneficiary];
        uint256 lockedAmount;

        uint256 i = voter.votedProposalIds.length;
        while (i > 0) {
            uint256 proposalId = voter.votedProposalIds[--i];
            uint256 proposalTimestamp = proposalTimestamps[proposalId];

            if (proposalTimestamp == 0) {
                continue;
            }

            if (
                block.timestamp < proposalTimestamp + getGovernance().getReferendumStageDuration()
            ) {
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
     * @return Governance referendum duration.
     */
    function getReferendumDuration() public view returns (uint256) {
        return getGovernance().getReferendumStageDuration();
    }

    /**
     * @notice Returns vote weight of account owning stCELO.
     * @param beneficiary The account.
     */
    function getVoteWeight(address beneficiary) public view returns (uint256) {
        uint256 stakedCeloBalance = stakedCelo.balanceOf(beneficiary);
        return toCelo(stakedCeloBalance);
    }

    /**
     * @notice Gets vote record of proposal.
     * @param proposalId The proposal UUID.
     */
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
}
