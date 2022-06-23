import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_GET_CONFIRMATIONS } from "../tasksNames";

task(MULTISIG_GET_CONFIRMATIONS, "Get list of addresses that have confirmed a proposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const confirmations = await multiSigContract.getConfirmations(proposalId);
      console.log(chalk.yellow("Addresses that have confirmed the proposal:"), confirmations);
    } catch (error) {
      console.log(chalk.red("Error getting proposal confirmations"), error);
    }
  });
