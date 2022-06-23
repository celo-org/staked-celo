import { task, types } from "hardhat/config";

import { MULTISIG_EXECUTE_PROPOSAL } from "../tasksNames";

import {
  getSigner,
  getContract,
  executeProposal,
  parseEvents,
} from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_EXECUTE_PROPOSAL, "Execute a proposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("namedAccount", "named account of multiSig owner", undefined, types.string)
  .addFlag("useLedger", "use ledger signer")
  .setAction(async ({ proposalId, namedAccount, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, namedAccount, useLedger);
      const multiSigContract = await getContract(hre);
      const receipt = await executeProposal(multiSigContract, proposalId, signer);
      parseEvents(receipt, "TransactionExecuted");
    } catch (error) {
      console.log("Error executing proposal", error);
    }
  });
