import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export async function getDeprecatedGroups(hre: HardhatRuntimeEnvironment) {
  try {
    const managerContract = await hre.ethers.getContract("Manager");

    const deprecatedGroups = await managerContract.getDeprecatedGroups();

    console.log(chalk.yellow("Deprecated Groups:"), deprecatedGroups);
  } catch (error) {
    throw error;
  }
}
