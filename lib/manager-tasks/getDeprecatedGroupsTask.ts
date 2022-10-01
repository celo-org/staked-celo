import chalk from "chalk";
import { task } from "hardhat/config";
import { setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";

import { MANAGER_GET_DEPRECATED_GROUPS } from "../tasksNames";
import { MANAGER_GET_DEPRECATED_GROUPS_TASK_DESCRIPTION } from "../helpers/staticVariables";
import { getDeprecatedGroups } from "./helpers/getDeprecatedGroups";

task(MANAGER_GET_DEPRECATED_GROUPS, MANAGER_GET_DEPRECATED_GROUPS_TASK_DESCRIPTION).setAction(
  async (_, hre) => {
    try {
      await setLocalNodeDeploymentPath(hre);
      console.log("Starting stakedCelo:manager:getDeprecatedGroups task...");

      await getDeprecatedGroups(hre);
    } catch (error) {
      console.log(chalk.red("Error getting deprecated groups:"), error);
    }
  }
);
