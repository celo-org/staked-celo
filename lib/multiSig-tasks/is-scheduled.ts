import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_IS_SCHEDULED } from "../tasksNames";

task(MULTISIG_IS_SCHEDULED, "Check if a proposal is scheduled")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const scheduled = await multiSigContract.isScheduled(proposalId);
      console.log(scheduled);
    } catch (error) {
      console.log(chalk.red("Error checking proposal schedule status:"), error);
    }
  });
