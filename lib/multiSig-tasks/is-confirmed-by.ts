import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_IS_CONFIRMED_BY } from "../tasksNames";

task(MULTISIG_IS_CONFIRMED_BY, "Check if a proposal has been confirmed a multiSig owner")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("address", "Owner address", undefined, types.string)
  .setAction(async ({ proposalId, address }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isConfirmedBy(proposalId, address);
      console.log(result);
    } catch (error) {
      console.log(chalk.red("Error getting proposal confirmation by address:"), error);
    }
  });
