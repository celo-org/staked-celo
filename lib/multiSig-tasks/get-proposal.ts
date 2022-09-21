import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_GET_PROPOSAL } from "../tasksNames";
import {
  MULTISIG_GET_PROPOSAL_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_GET_PROPOSAL, MULTISIG_GET_PROPOSAL_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .setAction(async (args, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const proposal = await multiSigContract.getProposal(args[PROPOSAL_ID]);
      console.log(chalk.yellow(`Proposal ${args[PROPOSAL_ID]} data:`), proposal);
    } catch (error) {
      console.log(chalk.red("Error getting Proposal:"), error);
    }
  });
