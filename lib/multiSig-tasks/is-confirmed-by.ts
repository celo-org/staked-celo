import { task, types } from "hardhat/config";

import { MULTISIG_IS_CONFIRMED_BY } from "../tasksNames";

import { getContract, isConfirmedBy } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_IS_CONFIRMED_BY)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("address", "Owner address", undefined, types.string)
  .setAction(async ({ proposalId, address }, hre) => {
    try {
      const multiSigContract = await getContract(hre);
      const result = await isConfirmedBy(multiSigContract, proposalId, address);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });
