// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./TaskInterfaces.sol";

/**
 * @title ElectionLib
 * @notice Solidity port of the ContractKit Election wrapper helpers the Hardhat tasks used.
 * @dev `findLesserAndGreaterAfterVote` mirrors ElectionWrapper.findLesserAndGreaterAfterVote:
 *      the eligible validator groups are returned ordered from most to least votes, so the
 *      neighbours of `group` after applying `delta` to its votes are the first group with
 *      votes at or below the new total (lesser) and the last group above it (greater).
 */
library ElectionLib {
    /**
     * @notice Finds the neighbours of `group` in the eligible group list after its votes
     *         change by `delta`.
     * @param electionContract The Celo Election contract.
     * @param group The validator group whose votes change.
     * @param delta The signed vote change; negative when revoking.
     * @return lesser The group that will have fewer votes than `group`, or address(0).
     * @return greater The group that will have more votes than `group`, or address(0).
     */
    function findLesserAndGreaterAfterVote(
        IElectionLookup electionContract,
        address group,
        int256 delta
    ) internal view returns (address lesser, address greater) {
        (address[] memory groups, uint256[] memory votes) = electionContract
            .getTotalVotesForEligibleValidatorGroups();

        uint256 total = _totalAfterVote(groups, votes, group, delta);

        for (uint256 i = 0; i < groups.length; i++) {
            if (groups[i] == group) {
                continue;
            }
            if (votes[i] <= total) {
                lesser = groups[i];
                break;
            }
            greater = groups[i];
        }
    }

    /**
     * @notice Index of `group` in the list of groups `account` votes for.
     * @dev Ports findAddressIndex from the account task helpers. Reverts when the account
     *      does not vote for the group, which is where the TypeScript version failed to
     *      encode the -1 that Array.indexOf returned.
     * @param electionContract The Celo Election contract.
     * @param account The voting account, in practice the StakedCelo Account contract.
     * @param group The validator group to look up.
     * @return The index of `group` in Election's per account group list.
     */
    function findAddressIndex(
        IElectionLookup electionContract,
        address account,
        address group
    ) internal view returns (uint256) {
        address[] memory list = electionContract.getGroupsVotedForByAccount(account);
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == group) {
                return i;
            }
        }
        revert("group not found in the account's voted group list");
    }

    /// @dev Current votes of `group` shifted by `delta`.
    function _totalAfterVote(
        address[] memory groups,
        uint256[] memory votes,
        address group,
        int256 delta
    ) private pure returns (uint256) {
        uint256 current = 0;
        for (uint256 i = 0; i < groups.length; i++) {
            if (groups[i] == group) {
                current = votes[i];
                break;
            }
        }
        return delta >= 0 ? current + uint256(delta) : current - uint256(-delta);
    }
}
