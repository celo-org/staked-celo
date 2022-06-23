import { task, types } from "hardhat/config";

import { MULTISIG_CONFIRM_PROPOSAL } from "../tasksNames";

import { getSigner, parseEvents } from "../helpers/interfaceHelper";

task(MULTISIG_CONFIRM_PROPOSAL, "Confirm a multiSig proposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("namedAccount", "named account of multiSig owner", undefined, types.string)
  .addFlag("useLedger", "use ledger signer")
  .setAction(async ({ proposalId, namedAccount, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, namedAccount, useLedger);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract.connect(signer).confirmProposal(proposalId);
      const receipt = await tx.wait();
      parseEvents(receipt, "ProposalConfirmed");
    } catch (error) {
      console.log("Error confirming proposal:", error);
    }
  });
