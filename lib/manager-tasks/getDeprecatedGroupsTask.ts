import chalk from "chalk";
import { task } from "hardhat/config";
import { setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";
import { MANAGER_GET_DEPRECATED_GROUPS_TASK_DESCRIPTION } from "../helpers/staticVariables";
import { MANAGER_GET_DEPRECATED_GROUPS } from "../tasksNames";

task(MANAGER_GET_DEPRECATED_GROUPS, MANAGER_GET_DEPRECATED_GROUPS_TASK_DESCRIPTION).setAction(
  async (_, hre) => {
    try {
      console.log(chalk.blue("Starting stakedCelo:manager:getDeprecatedGroups task..."));

      await setLocalNodeDeploymentPath(hre);
      const managerContract = await hre.ethers.getContract("Manager");

      const deprecatedGroups = await managerContract.getDeprecatedGroups();

      console.log(chalk.yellow("Deprecated Groups:"), deprecatedGroups);
    } catch (error) {
      console.log(chalk.red("Error getting deprecated groups:"), error);
    }
  }
);
