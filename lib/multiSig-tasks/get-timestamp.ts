import { task, types } from "hardhat/config";

import { MULTISIG_GET_TIMESTAMP } from "../tasksNames";

task(MULTISIG_GET_TIMESTAMP, "Get a proposal timestamp")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const timestamp = await multiSigContract.getTimestamp(proposalId);
      console.log(timestamp.toBigInt());
    } catch (error) {
      console.log(error);
    }
  });
