import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export async function getGroups(hre: HardhatRuntimeEnvironment) {
  try {
    const managerContract = await hre.ethers.getContract("Manager");

    const deprecatedGroups = await managerContract.getGroups();

    console.log(chalk.yellow("Groups:"), deprecatedGroups);
  } catch (error) {
    throw error;
  }
}
