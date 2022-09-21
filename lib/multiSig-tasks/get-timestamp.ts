import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_GET_TIMESTAMP } from "../tasksNames";
import {
  MULTISIG_GET_TIMESTAMP_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_GET_TIMESTAMP, MULTISIG_GET_TIMESTAMP_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .setAction(async (args, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const timestamp = await multiSigContract.getTimestamp(args[PROPOSAL_ID]);
      console.log(chalk.green(`Proposal ${args[PROPOSAL_ID]} timestamp:`), timestamp.toBigInt());
    } catch (error) {
      console.log(chalk.red("Error getting proposal timestamp"), error);
    }
  });
