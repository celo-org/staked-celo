import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_GET_TIMESTAMP } from "../tasksNames";

task(MULTISIG_GET_TIMESTAMP, "Get a proposal timestamp")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const timestamp = await multiSigContract.getTimestamp(proposalId);
      console.log(chalk.green(`Proposal ${proposalId} timestamp:`), timestamp.toBigInt());
    } catch (error) {
      console.log(chalk.red("Error getting proposal timestamp"), error);
    }
  });
