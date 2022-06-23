import { task, types } from "hardhat/config";

import { MULTISIG_GET_PROPOSAL } from "../tasksNames";

import { getMultiSig, getProposal } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_GET_PROPOSAL, "Get a multiSig proposal by it's ID")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await getMultiSig(hre);
      const proposal = await getProposal(multiSigContract, proposalId);
      console.log(proposal);
    } catch (error) {
      console.log(error);
    }
  });
