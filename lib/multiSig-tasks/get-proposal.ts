import { task, types } from "hardhat/config";

import { MULTISIG_GET_PROPOSAL } from "../tasksNames";

task(MULTISIG_GET_PROPOSAL, "Get a multiSig proposal by it's ID")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const proposal = await multiSigContract.getProposal(proposalId);
      console.log(proposal);
    } catch (error) {
      console.log(error);
    }
  });
