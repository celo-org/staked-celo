import { task, types } from "hardhat/config";
import { setLocalNodeDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MULTISIG_IS_FULLY_CONFIRMED_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_IS_FULLY_CONFIRMED } from "../tasksNames";

task(MULTISIG_IS_FULLY_CONFIRMED, MULTISIG_IS_FULLY_CONFIRMED_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      await setLocalNodeDeploymentPath(hre);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const fullyConfirmed = await multiSigContract.isFullyConfirmed(args.proposalId);
      taskLogger.log("is proposal fully confirmed: ", fullyConfirmed);
    } catch (error) {
      taskLogger.error("Error checking if proposal if fully confirmed:", error);
    }
  });
