import { task, types } from "hardhat/config";
import { setLocalNodeDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MULTISIG_GET_TIMESTAMP_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_GET_TIMESTAMP } from "../tasksNames";

task(MULTISIG_GET_TIMESTAMP, MULTISIG_GET_TIMESTAMP_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      await setLocalNodeDeploymentPath(hre);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const timestamp = await multiSigContract.getTimestamp(args.proposalId);
      taskLogger.log(`Proposal ${args.proposalId} timestamp:`, timestamp.toBigInt());
    } catch (error) {
      taskLogger.error("Error getting proposal timestamp", error);
    }
  });
