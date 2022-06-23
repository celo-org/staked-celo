import { task } from "hardhat/config";

import { MULTISIG_GET_OWNERS } from "../tasksNames";

task(MULTISIG_GET_OWNERS, "Get multiSig owners").setAction(async (_, hre) => {
  try {
    const multiSigContract = await hre.ethers.getContract("MultiSig");
    const owners = await multiSigContract.getOwners();
    console.log(owners);
  } catch (error) {
    console.log(error);
  }
});
