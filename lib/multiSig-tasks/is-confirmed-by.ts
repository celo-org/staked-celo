import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_IS_CONFIRMED_BY } from "../tasksNames";
import {
  MULTISIG_IS_CONFIRMED_TASK_DESCRIPTION,
  OWNER_ADDRESS,
  OWNER_ADDRESS_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_IS_CONFIRMED_BY, MULTISIG_IS_CONFIRMED_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addParam(OWNER_ADDRESS, OWNER_ADDRESS_DESCRIPTION, undefined, types.string)
  .setAction(async (args, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isConfirmedBy(args[PROPOSAL_ID], args[OWNER_ADDRESS]);
      console.log(result);
    } catch (error) {
      console.log(chalk.red("Error getting proposal confirmation by address:"), error);
    }
  });
