import { task, subtask, types } from "hardhat/config";
import {
  getMultisigContract,
  confirmProposal,
  createProposal,
  executeProposal,
  getOwners,
} from "../lib/multiSigInterface";

task("multiSig", "interface with staked CELO MultiSig contract")
  .addFlag("createProposal", "create a proposal")
  // .addPositionalParam("function", "Function to execute", undefined, types.int)
  .addOptionalParam("parameters", "list of function parameters")
  .setAction(async (taskArgs, hre) => {
    try {
      // switch () {
      //     case value:

      //         break;

      //     default:
      //         break;
      // }
      console.log("running multisig task");
    } catch (error) {
      console.log(error);
    }
  });

subtask("createProposal", "Submit a proposal to the multiSig")
  .addPositionalParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("owner", "named account of multiSig owner", "multisigOwner0", types.string)
  .setAction(async (taskArgs, hre) => {
    try {
      await getMultisigContract(hre, taskArgs["owner"]);
      await createProposal();
    } catch (error) {
      console.log(error);
    }
  });
task("confirmProposal", "Submit a proposal to the multiSig")
  .addPositionalParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("owner", "named account of multiSig owner", "multisigOwner0", types.string)
  .setAction(async (taskArgs, hre) => {
    try {
      console.log(taskArgs["proposalId"]);
      await getMultisigContract(hre, taskArgs["owner"]);
      // await confirmProposal(hre, taskArgs["proposalId"]);
    } catch (error) {
      console.log(error);
    }
  });
task("executeProposal", "Submit a proposal to the multiSig")
  .addPositionalParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("owner", "named account of multiSig owner", "multisigOwner0", types.string)
  .setAction(async (taskArgs, hre) => {
    try {
      await getMultisigContract(hre, taskArgs["owner"]);
      console.log(taskArgs["proposalId"]);
      await executeProposal(taskArgs["proposalId"]);
    } catch (error) {
      console.log(error);
    }
  });
task("getOwners", "Submit a proposal to the multiSig")
  // .addPositionalParam("proposalId", "ID of the proposal", undefined, types.int)
  .setAction(async (taskArgs, hre) => {
    try {
      await getMultisigContract(hre, taskArgs["owner"]);
      await getOwners(hre);
    } catch (error) {
      console.log(error);
    }
  });
