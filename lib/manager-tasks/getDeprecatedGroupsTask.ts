import { task, types } from "hardhat/config";
import { setLocalNodeDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MANAGER_GET_DEPRECATED_GROUPS_TASK_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MANAGER_GET_DEPRECATED_GROUPS } from "../tasksNames";

task(MANAGER_GET_DEPRECATED_GROUPS, MANAGER_GET_DEPRECATED_GROUPS_TASK_DESCRIPTION)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      taskLogger.info("Starting stakedCelo:manager:getDeprecatedGroups task...");

      await setLocalNodeDeploymentPath(hre);
      const managerContract = await hre.ethers.getContract("Manager");

      const deprecatedGroups = await managerContract.getDeprecatedGroups();

      taskLogger.log("Deprecated Groups:", deprecatedGroups);
    } catch (error) {
      taskLogger.error("Error getting deprecated groups:", error);
    }
  });
