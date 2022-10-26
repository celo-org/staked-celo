import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_GET_CONFIRMATIONS } from "../tasksNames";
import {
  MULTISIG_GET_CONFIRMATIONS_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_GET_CONFIRMATIONS, MULTISIG_GET_CONFIRMATIONS_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .setAction(async (args, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const confirmations = await multiSigContract.getConfirmations(args[PROPOSAL_ID]);
      console.log(chalk.yellow("Addresses that have confirmed the proposal:"), confirmations);
    } catch (error) {
      console.log(chalk.red("Error getting proposal confirmations"), error);
    }
  });
