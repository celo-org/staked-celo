import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  AMOUNT,
  AMOUNT_DESCRIPTION,
  MANAGER_WITHDRAW_TASK_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
  VERBOSE_LOG,
  VERBOSE_LOG_DESCRIPTION,
} from "../helpers/staticVariables";
import { MANAGER_WITHDRAW } from "../tasksNames";

task(MANAGER_WITHDRAW, MANAGER_WITHDRAW_TASK_DESCRIPTION)
  .addParam(AMOUNT, AMOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .addFlag(VERBOSE_LOG, VERBOSE_LOG_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      console.log(chalk.blue("Starting stakedCelo:manager:withdraw task..."));
      const signer = await getSignerAndSetDeploymentPath(hre, args);

      const managerContract = await hre.ethers.getContract("Manager");
      const tx = await managerContract.connect(signer).withdraw(args.amount!, { type: 0 });
      const receipt = await tx.wait();
      if (args.verboseLog) {
        console.log(chalk.yellow("receipt status"), receipt.status);
      }
    } catch (error) {
      console.log(chalk.red("Error withdrawing stCELO:"), error);
    }
  });
