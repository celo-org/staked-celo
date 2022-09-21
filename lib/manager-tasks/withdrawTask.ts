import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSigner, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";

import { MANAGER_WITHDRAW } from "../tasksNames";
import {
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  AMOUNT_DESCRIPTION,
  AMOUNT,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  MANAGER_WITHDRAW_TASK_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";
import { managerWithdraw } from "./helpers/withdrawHelper";

task(MANAGER_WITHDRAW, MANAGER_WITHDRAW_TASK_DESCRIPTION)
  .addParam(AMOUNT, AMOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args, hre) => {
    try {
      const signer = await getSigner(hre, args[ACCOUNT], args[USE_LEDGER], args[USE_NODE_ACCOUNT]);
      await setLocalNodeDeploymentPath(hre);
      console.log("Starting stakedCelo:manager:withdraw task...");

      await managerWithdraw(hre, signer, args[AMOUNT]);
    } catch (error) {
      console.log(chalk.red("Error withdrawing stCELO:"), error);
    }
  });
