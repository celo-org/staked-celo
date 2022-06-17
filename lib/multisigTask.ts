import { task, subtask, types } from "hardhat/config";
import {
  getContract,
  confirmProposal,
  submitProposal,
  executeProposal,
  getOwners,
  getSigner,
  encodeData,
  revokeConfirmation,
  getConfirmations,
  scheduleProposal,
  getProposal,
  isFullyConfirmed,
  isScheduled,
  getTimestamp,
  isProposalTimelockReached,
  isOwner,
  isConfirmedBy,
} from "./helpers/multiSigInterfaceHelper";

task("stakedCelo:multiSig", "Interface with the staked CELO multi-sig contract.")
  .addFlag("getOwners", "Get owners.")
  .addParam("signer", "(required) Account used to sign the transaction.", undefined, types.string)
  .addOptionalParam(
    "submitProposal",
    "Submit a proposal | { destinations:string[],values:number[],payloads:string[] }",
    undefined,
    types.json
  )
  .addOptionalParam("confirmProposal", "Confirm a proposal | number", undefined, types.int)
  .addOptionalParam(
    "revokeConfirmation",
    "Revoke proposal confirmation | number",
    undefined,
    types.int
  )
  .addOptionalParam("scheduleProposal", "Schedule a proposal | number", undefined, types.int)
  .addOptionalParam("executeProposal", "Execute a proposal | number", undefined, types.int)
  .addOptionalParam("getProposal", "Get proposal | number", undefined, types.int)
  .addOptionalParam("getConfirmations", "Get proposal confirmation | number", undefined, types.int)
  .addOptionalParam(
    "isFullyConfirmed",
    "Check if proposal is fully confirmed | number",
    undefined,
    types.int
  )
  .addOptionalParam("isScheduled", "Check if proposal is scheduled | number", undefined, types.int)
  .addOptionalParam("getTimestamp", "Get proposal timestamp | number", undefined, types.int)
  .addOptionalParam(
    "isProposalTimelockReached",
    "Check if proposal time-lock has been reached | number",
    undefined,
    types.int
  )
  .addOptionalParam("isOwner", "Check if an address is an owner | string", undefined, types.string)
  .addOptionalParam(
    "isConfirmedBy",
    "Check if proposal is confirmed owner | { proposalId:number, address:string }",
    undefined,
    types.json
  )
  .setAction(async (taskArgs, hre) => {
    try {
      console.log("running multiSig task", taskArgs);
      await getContract(hre, "MultiSig");
      const signer = await getSigner(hre, taskArgs["signer"]);

      if (taskArgs["getOwners"]) {
        console.log("getting owners");
        await hre.run("multiSig:getOwners");
      }

      if (taskArgs["submitProposal"] != undefined) {
        console.log("submitting proposal");
        await hre.run("multiSig:submitProposal", {
          destinations: taskArgs["submitProposal"]["destinations"],
          values: taskArgs["submitProposal"]["values"],
          payloads: taskArgs["submitProposal"]["payloads"],
          signer: signer,
        });
      } else if (taskArgs["confirmProposal"] != undefined) {
        console.log("confirming proposal");
        await hre.run("multiSig:confirmProposal", {
          proposalId: taskArgs["confirmProposal"],
          signer: signer,
        });
      } else if (taskArgs["scheduleProposal"] != undefined) {
        console.log("scheduling Proposal");
        await hre.run("multiSig:scheduleProposal", {
          proposalId: taskArgs["scheduleProposal"],
          signer: signer,
        });
      } else if (taskArgs["revokeConfirmation"] != undefined) {
        console.log("revoking Confirmation");
        await hre.run("multiSig:revokeConfirmation", {
          proposalId: taskArgs["revokeConfirmation"],
          signer: signer,
        });
      } else if (taskArgs["executeProposal"] != undefined) {
        // TODO:check time has elapsed.
        console.log("executing proposal");
        await hre.run("multiSig:executeProposal", {
          proposalId: taskArgs["executeProposal"],
          signer: signer,
        });
      } else if (taskArgs["getProposal"] != undefined) {
        console.log("getProposal", taskArgs["getProposal"]);
        await hre.run("multiSig:getProposal", { proposalId: taskArgs["getProposal"] });
      } else if (taskArgs["getConfirmations"] != undefined) {
        console.log("getting confirmations of proposal:", taskArgs["getConfirmations"]);
        await hre.run("multiSig:getConfirmations", { proposalId: taskArgs["getConfirmations"] });
      } else if (taskArgs["getTimestamp"] != undefined) {
        console.log("getTimestamp", taskArgs["getTimestamp"]);
        await hre.run("multiSig:getTimestamp", { proposalId: taskArgs["getTimestamp"] });
      } else if (taskArgs["isScheduled"] != undefined) {
        console.log("isScheduled?");
        await hre.run("multiSig:isScheduled", { proposalId: taskArgs["isScheduled"] });
      } else if (taskArgs["isProposalTimelockReached"] != undefined) {
        console.log("isProposalTimelockReached");
        await hre.run("multiSig:isProposalTimelockReached", {
          proposalId: taskArgs["isProposalTimelockReached"],
        });
      } else if (taskArgs["isFullyConfirmed"] != undefined) {
        console.log("isFullyConfirmed", taskArgs["isFullyConfirmed"]);
        await hre.run("multiSig:isFullyConfirmed", {
          proposalId: taskArgs["isFullyConfirmed"],
          signer: signer,
        });
      } else if (taskArgs["isOwner"] != undefined) {
        console.log("isOwner", taskArgs["isOwner"]);
        await hre.run("multiSig:isOwner", { address: taskArgs["isOwner"] });
      } else if (taskArgs["isConfirmedBy"] != undefined) {
        console.log("isConfirmedBy", taskArgs["isConfirmedBy"]);
        await hre.run("multiSig:isConfirmedBy", {
          proposalId: taskArgs["isConfirmedBy"]["proposalId"],
          address: taskArgs["isConfirmedBy"]["address"],
        });
      } else {
        if (!taskArgs["getOwners"]) throw new Error("No valid param was given.");
      }
    } catch (error) {
      console.log(error);
    }
  });

/// Get owners
subtask("multiSig:getOwners").setAction(async () => {
  try {
    const owners = await getOwners();
    console.log(owners);
  } catch (error) {
    console.log(error);
  }
});

/// Submit proposal
subtask("multiSig:submitProposal")
  .addParam(
    "destinations",
    "The addresses at which the proposal is target at.",
    undefined,
    types.any
  )
  .addParam("values", "The CELO values involved in the proposal if any.", undefined, types.any)
  .addParam("payloads", "The payloads of the proposal.", undefined, types.any)
  .addParam("signer", "The signer.", undefined, types.any)
  .setAction(async ({ destinations, values, payloads, signer }) => {
    try {
      const receipt = await submitProposal(destinations, values, payloads, signer);
      const event = receipt.events?.find((event) => event.event === "ProposalConfirmed");
      console.log("new event:", event?.event);
    } catch (error) {
      console.log("Error submitting proposal", error);
    }
  });

/// Confirm proposal
subtask("multiSig:confirmProposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("signer", "named account of multiSig owner", undefined, types.any)
  .setAction(async ({ proposalId, signer }) => {
    try {
      const receipt = await confirmProposal(proposalId, signer);
      const event = receipt.events?.find((event) => event.event === "ProposalConfirmed");
      console.log("new event:", event?.event, `(${event?.args})`);
    } catch (error) {
      console.log("Error confirming proposal:", error);
    }
  });

/// Revoke proposal confirmation
subtask("multiSig:revokeConfirmation")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("signer", "named account of multiSig owner", undefined, types.any)
  .setAction(async ({ proposalId, signer }) => {
    try {
      await revokeConfirmation(proposalId, signer);
    } catch (error) {
      console.log(error);
    }
  });

/// Schedule proposal
subtask("multiSig:scheduleProposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("signer", "named account of multiSig owner", undefined, types.any)
  .setAction(async ({ proposalId, signer }) => {
    try {
      await scheduleProposal(proposalId, signer);
    } catch (error) {
      console.log(error);
    }
  });

/// Execute proposal
subtask("multiSig:executeProposal")
  .addPositionalParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("signer", "named account of multiSig owner", undefined, types.any)
  .setAction(async ({ proposalId, signer }) => {
    try {
      await executeProposal(proposalId, signer);
    } catch (error) {
      console.log("Error executing proposal", error);
    }
  });

/// Get proposal
subtask("multiSig:getProposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }) => {
    try {
      const proposal = await getProposal(proposalId);
      console.log(proposal);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:getConfirmations")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }) => {
    try {
      const confirmations = await getConfirmations(proposalId);
      console.log(confirmations);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isFullyConfirmed")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }) => {
    try {
      const fullyConfirmed = await isFullyConfirmed(proposalId);
      console.log(fullyConfirmed);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isScheduled")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }) => {
    try {
      const scheduled = await isScheduled(proposalId);
      console.log(scheduled);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:getTimestamp")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }) => {
    try {
      const timestamp = await getTimestamp(proposalId);
      console.log(timestamp);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isProposalTimelockReached")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ proposalId }) => {
    try {
      const result = await isProposalTimelockReached(proposalId);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isOwner")
  .addParam("address", "Address of suposed owner", undefined, types.string)
  .setAction(async ({ address }) => {
    try {
      const result = await isOwner(address);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isConfirmedBy")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("address", "Owner address", undefined, types.string)
  .setAction(async ({ proposalId, address }) => {
    try {
      const result = await isConfirmedBy(proposalId, address);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });
