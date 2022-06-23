import { task, types } from "hardhat/config";

import { MULTISIG_IS_OWNER } from "../tasksNames";

task(MULTISIG_IS_OWNER, "Check if an address is a multiSig owner")
  .addParam("address", "Address of suposed owner", undefined, types.string)
  .setAction(async ({ address }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isOwner(address);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });
