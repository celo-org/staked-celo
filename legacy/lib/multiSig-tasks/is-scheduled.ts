import { task, types } from "hardhat/config";
import { setLocalNodeDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MULTISIG_IS_SCHEDULED_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_IS_SCHEDULED } from "../tasksNames";

task(MULTISIG_IS_SCHEDULED, MULTISIG_IS_SCHEDULED_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      await setLocalNodeDeploymentPath(hre);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const scheduled = await multiSigContract.isScheduled(args.proposalId);
      taskLogger.log("Is Proposal scheduled:", scheduled);
    } catch (error) {
      taskLogger.error("Error checking proposal schedule status:", error);
    }
  });
