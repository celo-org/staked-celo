import { task, types } from "hardhat/config";

import { MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED } from "../tasksNames";

task(MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED, "Check if a proposal time-lock has been reached")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isProposalTimelockReached(proposalId);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });
