import { task } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_GET_OWNERS } from "../tasksNames";
import { MULTISIG_GET_OWNERS_TASK_DESCRIPTION } from "../helpers/staticVariables";

task(MULTISIG_GET_OWNERS, MULTISIG_GET_OWNERS_TASK_DESCRIPTION).setAction(async (_, hre) => {
  try {
    const multiSigContract = await hre.ethers.getContract("MultiSig");
    const owners = await multiSigContract.getOwners();
    console.log(chalk.yellow("Current multiSig owners:"), owners);
  } catch (error) {
    console.log(chalk.red("Error getting multiSig owners:"), error);
  }
});
