import { task, types } from "hardhat/config";

import { MULTISIG_IS_OWNER } from "../tasksNames";

import { getContract, isOwner } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_IS_OWNER)
  .addParam("address", "Address of suposed owner", undefined, types.string)
  .setAction(async ({ address }, hre) => {
    try {
      const multiSigContract = await getContract(hre);
      const result = await isOwner(multiSigContract, address);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });
