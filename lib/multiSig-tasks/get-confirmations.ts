import { task, types } from "hardhat/config";
import { TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MULTISIG_GET_CONFIRMATIONS_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_GET_CONFIRMATIONS } from "../tasksNames";

task(MULTISIG_GET_CONFIRMATIONS, MULTISIG_GET_CONFIRMATIONS_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const confirmations = await multiSigContract.getConfirmations(args.proposalId);
      taskLogger.log("Addresses that have confirmed the proposal:", confirmations);
    } catch (error) {
      taskLogger.error("Error getting proposal confirmations", error);
    }
  });
