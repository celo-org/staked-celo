import chalk from "chalk";
import { task } from "hardhat/config";
import { setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";

import {
  MANAGER_SUBMIT_PROPOSAL_SET_VOTE,
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD,
  MULTISIG_SUBMIT_PROPOSAL,
} from "../tasksNames";
import { MANAGER_SUBMIT_PROPOSAL_SET_VOTE_DESCRIPTION } from "../helpers/staticVariables";

task(MANAGER_SUBMIT_PROPOSAL_SET_VOTE, MANAGER_SUBMIT_PROPOSAL_SET_VOTE_DESCRIPTION).setAction(
  async (
    args: {
      account: string;
    },
    hre
  ) => {
    try {
      console.log("stakedCelo:manager:submitProposal:setVote task...");

      const payload = await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
        contract: "Manager",
        function: "setVoteContract",
        args: (await hre.deployments.get("Vote")).address,
      });

      await hre.run(MULTISIG_SUBMIT_PROPOSAL, {
        destinations: [(await hre.deployments.get("Manager")).address],
        values: [0],
        payloads: [payload],
        account: args.account,
        useNodeAccount: true,
      });
    } catch (error) {
      console.log(chalk.red("Error getting groups:"), error);
    }
  }
);
