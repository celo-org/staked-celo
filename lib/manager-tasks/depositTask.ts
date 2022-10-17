import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";

import { MANAGER_DEPOSIT } from "../tasksNames";
import {
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  AMOUNT_DESCRIPTION,
  AMOUNT,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  MANAGER_DEPOSIT_TASK_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";

task(MANAGER_DEPOSIT, MANAGER_DEPOSIT_TASK_DESCRIPTION)
  .addParam(AMOUNT, AMOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      console.log("Starting stakedCelo:manager:deposit task...");

      const signer = await getSignerAndSetDeploymentPath(hre, args);

      const managerContract = await hre.ethers.getContract("Manager");
      const tx = await managerContract.connect(signer).deposit({ value: args.amount!, type: 0 });
      const receipt = await tx.wait();
      console.log(chalk.yellow("receipt status"), receipt.status);
    } catch (error) {
      console.log(chalk.red("Error depositing CELO:"), error);
    }
  });
