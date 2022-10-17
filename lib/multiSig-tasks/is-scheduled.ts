import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_IS_SCHEDULED } from "../tasksNames";
import {
  MULTISIG_IS_SCHEDULED_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_IS_SCHEDULED, MULTISIG_IS_SCHEDULED_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .setAction(async (args, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const scheduled = await multiSigContract.isScheduled(args[PROPOSAL_ID]);
      console.log(scheduled);
    } catch (error) {
      console.log(chalk.red("Error checking proposal schedule status:"), error);
    }
  });
