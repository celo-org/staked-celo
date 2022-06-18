import { task, subtask, types } from "hardhat/config";
import {
  getContract,
  confirmProposal,
  submitProposal,
  executeProposal,
  getOwners,
  getSigner,
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
  parseEvents,
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
      console.log("running multiSig task");
      const multiSigContract = await getContract(hre);
      const signer = await getSigner(hre, taskArgs["signer"]);

      if (taskArgs["getOwners"]) {
        console.log("getting owners");
        await hre.run("multiSig:getOwners", { contract: multiSigContract });
      }

      if (taskArgs["submitProposal"] !== undefined) {
        console.log("submitting proposal");
        await hre.run("multiSig:submitProposal", {
          contract: multiSigContract,
          destinations: taskArgs["submitProposal"]["destinations"],
          values: taskArgs["submitProposal"]["values"],
          payloads: taskArgs["submitProposal"]["payloads"],
          signer: signer,
        });
      } else if (taskArgs["confirmProposal"] !== undefined) {
        console.log("confirming proposal");
        await hre.run("multiSig:confirmProposal", {
          contract: multiSigContract,
          proposalId: taskArgs["confirmProposal"],
          signer: signer,
        });
      } else if (taskArgs["scheduleProposal"] !== undefined) {
        console.log("scheduling Proposal");
        await hre.run("multiSig:scheduleProposal", {
          contract: multiSigContract,
          proposalId: taskArgs["scheduleProposal"],
          signer: signer,
        });
      } else if (taskArgs["revokeConfirmation"] !== undefined) {
        console.log("revoking Confirmation");
        await hre.run("multiSig:revokeConfirmation", {
          contract: multiSigContract,
          proposalId: taskArgs["revokeConfirmation"],
          signer: signer,
        });
      } else if (taskArgs["executeProposal"] !== undefined) {
        console.log("executing proposal");
        await hre.run("multiSig:executeProposal", {
          contract: multiSigContract,
          proposalId: taskArgs["executeProposal"],
          signer: signer,
        });
      } else if (taskArgs["getProposal"] !== undefined) {
        console.log("getProposal");
        await hre.run("multiSig:getProposal", {
          contract: multiSigContract,
          proposalId: taskArgs["getProposal"],
        });
      } else if (taskArgs["getConfirmations"] !== undefined) {
        console.log("getConfirmations", taskArgs["getConfirmations"]);
        await hre.run("multiSig:getConfirmations", {
          contract: multiSigContract,
          proposalId: taskArgs["getConfirmations"],
        });
      } else if (taskArgs["getTimestamp"] !== undefined) {
        console.log("getTimestamp");
        await hre.run("multiSig:getTimestamp", {
          contract: multiSigContract,
          proposalId: taskArgs["getTimestamp"],
        });
      } else if (taskArgs["isScheduled"] !== undefined) {
        console.log("isScheduled");
        await hre.run("multiSig:isScheduled", {
          contract: multiSigContract,
          proposalId: taskArgs["isScheduled"],
        });
      } else if (taskArgs["isProposalTimelockReached"] !== undefined) {
        console.log("isProposalTimelockReached");
        await hre.run("multiSig:isProposalTimelockReached", {
          contract: multiSigContract,
          proposalId: taskArgs["isProposalTimelockReached"],
        });
      } else if (taskArgs["isFullyConfirmed"] !== undefined) {
        console.log("isFullyConfirmed");
        await hre.run("multiSig:isFullyConfirmed", {
          contract: multiSigContract,
          proposalId: taskArgs["isFullyConfirmed"],
          signer: signer,
        });
      } else if (taskArgs["isOwner"] !== undefined) {
        console.log("isOwner");
        await hre.run("multiSig:isOwner", {
          contract: multiSigContract,
          address: taskArgs["isOwner"],
        });
      } else if (taskArgs["isConfirmedBy"] !== undefined) {
        console.log("isConfirmedBy");
        await hre.run("multiSig:isConfirmedBy", {
          contract: multiSigContract,
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
subtask("multiSig:getOwners")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .setAction(async ({ contract }) => {
    try {
      const owners = await getOwners(contract);
      console.log(owners);
    } catch (error) {
      console.log(error);
    }
  });

/// Submit proposal
subtask("multiSig:submitProposal")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam(
    "destinations",
    "The addresses at which the proposal is target at.",
    undefined,
    types.any
  )
  .addParam("values", "The CELO values involved in the proposal if any.", undefined, types.any)
  .addParam("payloads", "The payloads of the proposal.", undefined, types.any)
  .addParam("signer", "The signer.", undefined, types.any)
  .setAction(async ({ contract, destinations, values, payloads, signer }) => {
    try {
      const receipt = await submitProposal(contract, destinations, values, payloads, signer);
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

/// Confirm proposal
subtask("multiSig:confirmProposal")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("signer", "named account of multiSig owner", undefined, types.any)
  .setAction(async ({ contract, proposalId, signer }) => {
    try {
      const receipt = await confirmProposal(contract, proposalId, signer);
      parseEvents(receipt, "ProposalConfirmed");
    } catch (error) {
      console.log("Error confirming proposal:", error);
    }
  });

/// Revoke proposal confirmation
subtask("multiSig:revokeConfirmation")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("signer", "named account of multiSig owner", undefined, types.any)
  .setAction(async ({ contract, proposalId, signer }) => {
    try {
      const receipt = await revokeConfirmation(contract, proposalId, signer);
      parseEvents(receipt, "ConfirmationRevoked");
    } catch (error) {
      console.log(error);
    }
  });

/// Schedule proposal
subtask("multiSig:scheduleProposal")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("signer", "named account of multiSig owner", undefined, types.any)
  .setAction(async ({ contract, proposalId, signer }) => {
    try {
      const receipt = await scheduleProposal(contract, proposalId, signer);
      parseEvents(receipt, "ProposalScheduled");
    } catch (error) {
      console.log(error);
    }
  });

/// Execute proposal
subtask("multiSig:executeProposal")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addPositionalParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("signer", "named account of multiSig owner", undefined, types.any)
  .setAction(async ({ contract, proposalId, signer }) => {
    try {
      const receipt = await executeProposal(contract, proposalId, signer);
      parseEvents(receipt, "ProposalExecuted");
    } catch (error) {
      console.log("Error executing proposal", error);
    }
  });

/// Get proposal
subtask("multiSig:getProposal")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ contract, proposalId }) => {
    try {
      const proposal = await getProposal(contract, proposalId);
      console.log(proposal);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:getConfirmations")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ contract, proposalId }) => {
    try {
      const confirmations = await getConfirmations(contract, proposalId);
      console.log(confirmations);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isFullyConfirmed")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ contract, proposalId }) => {
    try {
      const fullyConfirmed = await isFullyConfirmed(contract, proposalId);
      console.log(fullyConfirmed);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isScheduled")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ contract, proposalId }) => {
    try {
      const scheduled = await isScheduled(contract, proposalId);
      console.log(scheduled);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:getTimestamp")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ contract, proposalId }) => {
    try {
      const timestamp = await getTimestamp(contract, proposalId);
      console.log(timestamp.toBigInt());
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isProposalTimelockReached")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async ({ contract, proposalId }) => {
    try {
      const result = await isProposalTimelockReached(contract, proposalId);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isOwner")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("address", "Address of suposed owner", undefined, types.string)
  .setAction(async ({ contract, address }) => {
    try {
      const result = await isOwner(contract, address);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });

/// Get confirmations
subtask("multiSig:isConfirmedBy")
  .addParam("contract", "MultiSig contract instance", undefined, types.any)
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addParam("address", "Owner address", undefined, types.string)
  .setAction(async ({ contract, proposalId, address }) => {
    try {
      const result = await isConfirmedBy(contract, proposalId, address);
      console.log(result);
    } catch (error) {
      console.log(error);
    }
  });
