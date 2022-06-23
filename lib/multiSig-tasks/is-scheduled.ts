import { task, types } from "hardhat/config";

import { MULTISIG_IS_SCHEDULED } from "../tasksNames";

import { getContract, isScheduled } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_IS_SCHEDULED, "Check if a proposal is scheduled")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await getContract(hre);
      const scheduled = await isScheduled(multiSigContract, proposalId);
      console.log(scheduled);
    } catch (error) {
      console.log(error);
    }
  });
