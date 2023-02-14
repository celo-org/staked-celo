import { task, types } from "hardhat/config";
import { setLocalNodeDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MULTISIG_GET_OWNERS_TASK_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_GET_OWNERS } from "../tasksNames";

task(MULTISIG_GET_OWNERS, MULTISIG_GET_OWNERS_TASK_DESCRIPTION)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      await setLocalNodeDeploymentPath(hre);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const owners = await multiSigContract.getOwners();
      taskLogger.log("Current multiSig owners:", owners);
    } catch (error) {
      taskLogger.error("Error getting multiSig owners:", error);
    }
  });
