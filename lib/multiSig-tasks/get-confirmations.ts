import { task, types } from "hardhat/config";

import { MULTISIG_GET_CONFIRMATIONS } from "../tasksNames";

import { getMultiSig, getConfirmations } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_GET_CONFIRMATIONS, "Get proposal confirmations")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await getMultiSig(hre);
      const confirmations = await getConfirmations(multiSigContract, proposalId);
      console.log(confirmations);
    } catch (error) {
      console.log(error);
    }
  });
