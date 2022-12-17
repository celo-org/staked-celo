import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  ACCOUNT_WITHDRAW_TASK_DESCRIPTION,
  BENEFICIARY,
  BENEFICIARY_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
  VERBOSE_LOG,
  VERBOSE_LOG_DESCRIPTION,
} from "../helpers/staticVariables";
import { ACCOUNT_WITHDRAW } from "../tasksNames";
import { withdraw } from "./helpers/withdrawalHelper";

task(ACCOUNT_WITHDRAW, ACCOUNT_WITHDRAW_TASK_DESCRIPTION)
  .addParam(BENEFICIARY, BENEFICIARY_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .addFlag(VERBOSE_LOG, VERBOSE_LOG_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      console.log(chalk.blue("Starting stakedCelo:account:withdraw task..."));

      const signer = await getSignerAndSetDeploymentPath(hre, args);

      await withdraw(hre, signer, args.beneficiary!, args.verboseLog);
    } catch (error) {
      console.log(chalk.red("Error withdrawing CELO:"), error);
    }
  });
