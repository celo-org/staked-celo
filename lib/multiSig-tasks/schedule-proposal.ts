import { task, types } from "hardhat/config";

import { MULTISIG_SCHEDULE_PROPOSAL } from "../tasksNames";

import {
  getSigner,
  getMultiSig,
  scheduleProposal,
  parseEvents,
} from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_SCHEDULE_PROPOSAL, "Schedule a proposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("namedAccount", "named account of multiSig owner", undefined, types.string)
  .addFlag("useLedger", "use ledger signer")
  .setAction(async ({ proposalId, namedAccount, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, namedAccount, useLedger);
      const multiSigContract = await getMultiSig(hre);
      const receipt = await scheduleProposal(multiSigContract, proposalId, signer);
      parseEvents(receipt, "ProposalScheduled");
    } catch (error) {
      console.log(error);
    }
  });
