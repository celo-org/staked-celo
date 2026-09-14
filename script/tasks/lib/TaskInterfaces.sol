// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

/**
 * @dev Minimal interfaces for the contracts the operational scripts talk to.
 *      The production contracts are not imported directly: MultiSig and the OpenZeppelin
 *      upgradeable base contracts declare colliding `Initializable` source units, and the
 *      scripts only need a handful of selectors.
 */

/// @notice Celo Registry (only the lookup the scripts use).
interface IRegistryLookup {
    function getAddressForStringOrDie(string calldata identifier) external view returns (address);
}

/// @notice Celo Election view helpers used for lesser/greater computation and reporting.
interface IElectionLookup {
    function getTotalVotesForEligibleValidatorGroups()
        external
        view
        returns (address[] memory groups, uint256[] memory votes);

    function getGroupsVotedForByAccount(address account)
        external
        view
        returns (address[] memory);

    function getPendingVotesForGroupByAccount(address group, address account)
        external
        view
        returns (uint256);

    function hasActivatablePendingVotes(address account, address group)
        external
        view
        returns (bool);

    /// @dev Declared `view` here; the core contract exposes it without the view modifier.
    function allowedToVoteOverMaxNumberOfGroups(address account) external view returns (bool);
}

/// @notice Celo LockedGold pending withdrawal lookup.
interface ILockedGoldLookup {
    function getPendingWithdrawals(address account)
        external
        view
        returns (uint256[] memory values, uint256[] memory timestamps);
}

/// @notice Celo Governance dequeue lookup.
interface IGovernanceLookup {
    function getDequeue() external view returns (uint256[] memory);
}

/// @notice StakedCelo Account contract.
interface IAccountTask {
    function activateAndVote(
        address group,
        address voteLesser,
        address voteGreater
    ) external;

    function revokeVotes(
        address group,
        address lesserAfterPendingRevoke,
        address greaterAfterPendingRevoke,
        address lesserAfterActiveRevoke,
        address greaterAfterActiveRevoke,
        uint256 index
    ) external;

    function withdraw(
        address beneficiary,
        address group,
        address lesserAfterPendingRevoke,
        address greaterAfterPendingRevoke,
        address lesserAfterActiveRevoke,
        address greaterAfterActiveRevoke,
        uint256 index
    ) external returns (uint256);

    function finishPendingWithdrawal(
        address beneficiary,
        uint256 localPendingWithdrawalIndex,
        uint256 lockedGoldPendingWithdrawalIndex
    ) external returns (uint256);

    function scheduledVotesForGroup(address group) external view returns (uint256);

    function scheduledRevokeForGroup(address group) external view returns (uint256);

    function scheduledWithdrawalsForGroupAndBeneficiary(address group, address beneficiary)
        external
        view
        returns (uint256);

    function getPendingWithdrawals(address beneficiary)
        external
        view
        returns (uint256[] memory values, uint256[] memory timestamps);

    function getNumberPendingWithdrawals(address beneficiary) external view returns (uint256);

    function getCeloForGroup(address group) external view returns (uint256);
}

/// @notice StakedCelo Manager contract.
interface IManagerTask {
    function deposit() external payable;

    function withdraw(uint256 stCeloAmount) external;

    function voteProposal(
        uint256 proposalId,
        uint256 index,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) external;
}

/// @notice StakedCelo DefaultStrategy contract (active group list traversal).
interface IDefaultStrategyTask {
    function getNumberOfGroups() external view returns (uint256);

    function getGroupsHead() external view returns (address head, address previousAddress);

    function getGroupPreviousAndNext(address group)
        external
        view
        returns (address previousAddress, address nextAddress);
}

/// @notice StakedCelo SpecificGroupStrategy contract (voted group list).
interface ISpecificGroupStrategyTask {
    function getNumberOfVotedGroups() external view returns (uint256);

    function getVotedGroup(uint256 index) external view returns (address);
}

/// @notice StakedCelo GroupHealth contract.
interface IGroupHealthTask {
    function isGroupValid(address group) external view returns (bool);

    function updateGroupHealth(address group) external;
}

/// @notice StakedCelo MultiSig contract.
interface IMultiSigTask {
    function submitProposal(
        address[] calldata destinations,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) external returns (uint256 proposalId);

    function confirmProposal(uint256 proposalId) external;

    function revokeConfirmation(uint256 proposalId) external;

    function scheduleProposal(uint256 proposalId) external;

    function executeProposal(uint256 proposalId) external;

    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        );

    function getConfirmations(uint256 proposalId) external view returns (address[] memory);

    function getOwners() external view returns (address[] memory);

    function getTimestamp(uint256 proposalId) external view returns (uint256);

    function isScheduled(uint256 proposalId) external view returns (bool);

    function isProposalTimelockReached(uint256 proposalId) external view returns (bool);

    function isFullyConfirmed(uint256 proposalId) external view returns (bool);

    function isConfirmedBy(uint256 proposalId, address owner) external view returns (bool);

    function isOwner(address owner) external view returns (bool);

    function delay() external view returns (uint256);

    function required() external view returns (uint256);
}
