import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_IS_FULLY_CONFIRMED } from "../tasksNames";
import {
  MULTISIG_IS_FULLY_CONFIRMED_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_IS_FULLY_CONFIRMED, MULTISIG_IS_FULLY_CONFIRMED_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .setAction(async (args, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const fullyConfirmed = await multiSigContract.isFullyConfirmed(args[PROPOSAL_ID]);
      console.log(fullyConfirmed);
    } catch (error) {
      console.log(chalk.red("Error checking if proposal if fully confirmed:"), error);
    }
  });
