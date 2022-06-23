import { task, types } from "hardhat/config";

import { MULTISIG_GET_CONFIRMATIONS } from "../tasksNames";

task(MULTISIG_GET_CONFIRMATIONS, "Get proposal confirmations")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const confirmations = await multiSigContract.getConfirmations(proposalId);
      console.log(confirmations);
    } catch (error) {
      console.log(error);
    }
  });
