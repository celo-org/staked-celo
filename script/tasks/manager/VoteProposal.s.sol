// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../lib/TaskBase.sol";
import "../lib/ManagerTaskLib.sol";

/**
 * @title VoteProposalScript
 * @notice Votes with stCELO on a governance proposal. Replaces
 *         `yarn hardhat stakedCelo:manager:voteProposal --proposal-id <id> --yes <n>
 *          --no <n> --abstain <n>`.
 *
 * Environment variables:
 *   PROPOSAL_ID  required. The ID of the governance proposal.
 *   YES          optional, default 0. Yes vote weight.
 *   NO           optional, default 0. No vote weight.
 *   ABSTAIN      optional, default 0. Abstain vote weight.
 *   NETWORK      optional. Deployments directory: celo | alfajores | staging.
 *
 * Usage:
 *   PROPOSAL_ID=42 YES=1000 forge script script/tasks/manager/VoteProposal.s.sol \
 *     --rpc-url celo --broadcast --ledger
 */
contract VoteProposalScript is TaskBase {
    /// @notice Reads the vote from the environment and casts it as the broadcaster.
    function run() external {
        IManagerTask manager = managerContract();
        IGovernanceLookup governanceContract = governance();
        uint256 proposalId = vm.envUint("PROPOSAL_ID");

        vm.startBroadcast();
        execute(
            manager,
            governanceContract,
            proposalId,
            vm.envOr("YES", uint256(0)),
            vm.envOr("NO", uint256(0)),
            vm.envOr("ABSTAIN", uint256(0))
        );
        vm.stopBroadcast();
    }

    /**
     * @notice Votes on `proposalId`, resolving its index in the governance dequeue first.
     * @param manager The Manager contract.
     * @param governanceContract The Celo Governance contract.
     * @param proposalId The ID of the governance proposal.
     * @param yesVotes The yes vote weight.
     * @param noVotes The no vote weight.
     * @param abstainVotes The abstain vote weight.
     */
    function execute(
        IManagerTask manager,
        IGovernanceLookup governanceContract,
        uint256 proposalId,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) internal {
        ManagerTaskLib.voteProposal(
            manager, governanceContract, proposalId, yesVotes, noVotes, abstainVotes
        );
    }
}
