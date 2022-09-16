import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Signer } from "ethers";

export async function deposit(hre: HardhatRuntimeEnvironment, signer: Signer, amount: string) {
  try {
    const managerContract = await hre.ethers.getContract("Manager");

    const tx = await managerContract.connect(signer).deposit({ value: amount, type: 0 });
    const receipt = await tx.wait();
    console.log(chalk.yellow("receipt status"), receipt.status);
  } catch (error) {
    throw error;
  }
}
