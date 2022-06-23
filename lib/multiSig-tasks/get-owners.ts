import { task } from "hardhat/config";

import { MULTISIG_GET_OWNERS } from "../tasksNames";

import { getMultiSig, getOwners } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_GET_OWNERS, "Get multiSig owners").setAction(async (_, hre) => {
  try {
    const multiSigContract = await getMultiSig(hre);
    const owners = await getOwners(multiSigContract);
    console.log(owners);
  } catch (error) {
    console.log(error);
  }
});
