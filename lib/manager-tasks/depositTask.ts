import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath } from "../helpers/interfaceHelper";

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
import { deposit } from "./helpers/depositHelper";

task(MANAGER_DEPOSIT, MANAGER_DEPOSIT_TASK_DESCRIPTION)
  .addParam(AMOUNT, AMOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args, hre) => {
    try {
      const signer = await getSignerAndSetDeploymentPath(
        hre,
        args[ACCOUNT],
        args[USE_LEDGER],
        args[USE_NODE_ACCOUNT]
      );

      console.log("Starting stakedCelo:manager:deposit task...");

      await deposit(hre, signer, args[AMOUNT]);
    } catch (error) {
      console.log(chalk.red("Error depositing CELO:"), error);
    }
  });
