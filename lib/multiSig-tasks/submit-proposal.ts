import { task, types } from "hardhat/config";

import { MULTISIG_SUBMIT_PROPOSAL } from "../tasksNames";

import { getSigner } from "../helpers/interfaceHelper";

task(MULTISIG_SUBMIT_PROPOSAL, "Submit a proposal to the multiSig contract")
  .addParam(
    "destinations",
    "The addresses at which the operations are targeted",
    undefined,
    types.string
  )
  .addParam("values", "The CELO values involved in the proposal if any.", undefined, types.string)
  .addParam("payloads", "The payloads of the proposal.", undefined, types.string)
  .addOptionalParam("namedAccount", "The signer.")
  .addFlag("useLedger", "use ledger signer")
  .setAction(async ({ destinations, values, payloads, namedAccount, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, namedAccount, useLedger);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract
        .connect(signer)
        .submitProposal(destinations.split(","), values.split(","), payloads.split(","));
      const receipt = await tx.wait();
      const events = receipt.events;
      if (events !== undefined) {
        for (var i = 0; i < events!.length; i++) {
          console.log("new event emitted:", events[i].event, `(${events[i].args})`);
        }
      }
    } catch (error) {
      console.log("Error submitting proposal", error);
    }
  });
