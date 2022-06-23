import { task, types } from "hardhat/config";

import { MULTISIG_IS_FULLY_CONFIRMED } from "../tasksNames";

import { getContract, isFullyConfirmed } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_IS_FULLY_CONFIRMED, "Check if a proposal has been fully confirmed")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await getContract(hre);
      const fullyConfirmed = await isFullyConfirmed(multiSigContract, proposalId);
      console.log(fullyConfirmed);
    } catch (error) {
      console.log(error);
    }
  });
