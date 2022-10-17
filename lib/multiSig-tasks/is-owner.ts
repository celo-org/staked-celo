import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_IS_OWNER } from "../tasksNames";
import {
  MULTISIG_IS_OWNER_TASK_DESCRIPTION,
  OWNER_ADDRESS,
  OWNER_ADDRESS_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_IS_OWNER, MULTISIG_IS_OWNER_TASK_DESCRIPTION)
  .addParam(OWNER_ADDRESS, OWNER_ADDRESS_DESCRIPTION, undefined, types.string)
  .setAction(async (args, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isOwner(args[OWNER_ADDRESS]);
      console.log(result);
    } catch (error) {
      console.log(chalk.red("Error checking if address is a multiSig owner"), error);
    }
  });
