import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSigner, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";

import { MANAGER_DEPOSIT } from "../tasksNames";
import {
  FROM_DESCRIPTION,
  FROM_PARAM_NAME,
  AMOUNT_DESCRIPTION,
  AMOUNT_PARAM_NAME,
  USE_LEDGER_PARAM_NAME,
  USE_LEDGER_DESCRIPTION,
  MANAGER_DEPOSIT_TASK_DESCRIPTION,
  USE_NODE_ACCOUNT_PARAM_NAME,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";
import { deposit } from "./helpers/depositHelper";

task(MANAGER_DEPOSIT, MANAGER_DEPOSIT_TASK_DESCRIPTION)
  .addParam(AMOUNT_PARAM_NAME, AMOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(FROM_PARAM_NAME, FROM_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER_PARAM_NAME, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT_PARAM_NAME, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async ({ amount, from, useLedger, useNodeAccount }, hre) => {
    try {
      const signer = await getSigner(hre, from, useLedger, useNodeAccount);
      await setLocalNodeDeploymentPath(hre);
      console.log("Starting stakedCelo:manager:deposit task...");

      await deposit(hre, signer, amount);
    } catch (error) {
      console.log(chalk.red("Error depositing CELO:"), error);
    }
  });
