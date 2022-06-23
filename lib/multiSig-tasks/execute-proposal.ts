import { task, types } from "hardhat/config";

import { MULTISIG_EXECUTE_PROPOSAL } from "../tasksNames";

import { getSigner, parseEvents } from "../helpers/interfaceHelper";

task(MULTISIG_EXECUTE_PROPOSAL, "Execute a proposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("namedAccount", "named account of multiSig owner", undefined, types.string)
  .addFlag("useLedger", "use ledger signer")
  .setAction(async ({ proposalId, namedAccount, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, namedAccount, useLedger);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract.connect(signer).executeProposal(proposalId);
      const receipt = await tx.wait();
      parseEvents(receipt, "TransactionExecuted");
    } catch (error) {
      console.log("Error executing proposal", error);
    }
  });
