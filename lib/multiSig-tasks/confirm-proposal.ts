import { task, types } from "hardhat/config";

import { MULTISIG_CONFIRM_PROPOSAL } from "../tasksNames";

import {
  getSigner,
  getContract,
  confirmProposal,
  parseEvents,
} from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_CONFIRM_PROPOSAL)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("namedAccount", "named account of multiSig owner", undefined, types.string)
  .addFlag("useLedger", "use ledger signer")
  .setAction(async ({ proposalId, namedAccount, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, namedAccount, useLedger);
      const multiSigContract = await getContract(hre);
      const receipt = await confirmProposal(multiSigContract, proposalId, signer);
      parseEvents(receipt, "ProposalConfirmed");
    } catch (error) {
      console.log("Error confirming proposal:", error);
    }
  });
