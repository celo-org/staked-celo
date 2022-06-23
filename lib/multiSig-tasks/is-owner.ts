import { task, types } from "hardhat/config";

import { MULTISIG_IS_OWNER } from "../tasksNames";

import { getMultiSig, isOwner } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_IS_OWNER, "Check if an address is a multiSig owner")
  .addParam("address", "Address of suposed owner", undefined, types.string)
  .setAction(async ({ address }, hre) => {
    try {
      const multiSigContract = await getMultiSig(hre);
      const result = await isOwner(multiSigContract, address);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });
