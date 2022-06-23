import { task, types } from "hardhat/config";

import { MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED } from "../tasksNames";

import { getContract, isProposalTimelockReached } from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }, hre) => {
    try {
      const multiSigContract = await getContract(hre);
      const result = await isProposalTimelockReached(multiSigContract, proposalId);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });
