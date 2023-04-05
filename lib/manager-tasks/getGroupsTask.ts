import { Contract } from "ethers";
import { task, types } from "hardhat/config";
import { setLocalNodeDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MANAGER_GET_GROUPS_TASK_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { getDefaultGroupsHHTask } from "../task-utils";
import { MANAGER_GET_GROUPS } from "../tasksNames";

task(MANAGER_GET_GROUPS, MANAGER_GET_GROUPS_TASK_DESCRIPTION)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      taskLogger.info("Starting stakedCelo:manager:getGroups task...");
      await setLocalNodeDeploymentPath(hre);

      const defaultStrategyContract = await hre.ethers.getContract("DefaultStrategy");
      const groups = await getDefaultGroupsHHTask(defaultStrategyContract)
      taskLogger.log("Groups:", groups);
    } catch (error) {
      taskLogger.error("Error getting groups:", error);
    }
  });

  export async function getDefaultGroupsSafe(
    defaultStrategy: Contract
  ) : Promise<string[]> {
    const activeGroupsLengthPromise = defaultStrategy.getNumberOfGroups();
    let [key] = await defaultStrategy.getGroupsHead();
  
    const activeGroups = [];
  
    for (let i = 0; i < (await activeGroupsLengthPromise).toNumber(); i++) {
      activeGroups.push(key);
      [key] = await defaultStrategy.getGroupPreviousAndNext(key);
    }
  
    return activeGroups
  }
