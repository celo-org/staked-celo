import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSigner, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";

import { MANAGER_WITHDRAW } from "../tasksNames";
import {
  FROM_DESCRIPTION,
  FROM_PARAM_NAME,
  AMOUNT_DESCRIPTION,
  AMOUNT_PARAM_NAME,
  USE_LEDGER_PARAM_NAME,
  USE_LEDGER_DESCRIPTION,
  MANAGER_WITHDRAW_TASK_DESCRIPTION,
} from "../helpers/staticVariables";
import { managerWithdraw } from "./helpers/withdrawHelper";

task(MANAGER_WITHDRAW, MANAGER_WITHDRAW_TASK_DESCRIPTION)
  .addParam(AMOUNT_PARAM_NAME, AMOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(FROM_PARAM_NAME, FROM_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER_PARAM_NAME, USE_LEDGER_DESCRIPTION)
  .setAction(async ({ amount, from, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, from, useLedger);
      await setLocalNodeDeploymentPath(hre);
      console.log("Starting stakedCelo:manager:withdraw task...");

      await managerWithdraw(hre, signer, amount);
    } catch (error) {
      console.log(chalk.red("Error withdrawing stCELO:"), error);
    }
  });
