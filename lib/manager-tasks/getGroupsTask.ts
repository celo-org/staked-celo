import chalk from "chalk";
import { task } from "hardhat/config";
import { setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";

import { MANAGER_GET_GROUPS } from "../tasksNames";
import { MANAGER_GET_GROUPS_TASK_DESCRIPTION } from "../helpers/staticVariables";
import { getGroups } from "./helpers/getGroups";

task(MANAGER_GET_GROUPS, MANAGER_GET_GROUPS_TASK_DESCRIPTION).setAction(async (_, hre) => {
  try {
    await setLocalNodeDeploymentPath(hre);
    console.log("Starting stakedCelo:manager:getGroups task...");

    await getGroups(hre);
  } catch (error) {
    console.log(chalk.red("Error getting groups:"), error);
  }
});
