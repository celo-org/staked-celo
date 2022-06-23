import { task, types } from "hardhat/config";

import { MULTISIG_GET_TIMESTAMP } from "../tasksNames";

import { getContract, getTimestamp } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_GET_TIMESTAMP)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await getContract(hre);
      const timestamp = await getTimestamp(multiSigContract, proposalId);
      console.log(timestamp.toBigInt());
    } catch (error) {
      console.log(error);
    }
  });
