import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_FINISH_PENDING_WITHDRAWAL } from "../tasksNames";
import { finishPendingWithdrawals } from "./helpers/finishPendingWithdrawalHelper";
import { setHreConfigs } from "./helpers/taskAction";
import {
  BENEFICIARY_DESCRIPTION,
  BENEFICIARY_PARAM_NAME,
  DEPLOYMENTS_PATH_DESCRIPTION,
  DEPLOYMENTS_PATH_PARAM_NAME,
  ACCOUNT_FINISH_PENDING_WITHDRAWAL_TASK_DESCRIPTION,
  FROM_DESCRIPTION,
  FROM_PARAM_NAME,
  USE_PRIVATE_KEY_DESCRIPTION,
  USE_PRIVATE_KEY_PARAM_NAME,
} from "../helpers/staticVariables";

task(ACCOUNT_FINISH_PENDING_WITHDRAWAL, ACCOUNT_FINISH_PENDING_WITHDRAWAL_TASK_DESCRIPTION)
  .addParam(BENEFICIARY_PARAM_NAME, BENEFICIARY_DESCRIPTION, undefined, types.string)
  .addOptionalParam(FROM_PARAM_NAME, FROM_DESCRIPTION, undefined, types.string)
  .addOptionalParam(
    DEPLOYMENTS_PATH_PARAM_NAME,
    DEPLOYMENTS_PATH_DESCRIPTION,
    undefined,
    types.string
  )
  .addFlag(USE_PRIVATE_KEY_PARAM_NAME, USE_PRIVATE_KEY_DESCRIPTION)
  .setAction(async ({ beneficiary, from, deploymentsPath, usePrivateKey }, hre) => {
    try {
      console.log("Starting stakedCelo:account:finishPendingWithdrawals task...");

      setHreConfigs(hre, from, deploymentsPath, usePrivateKey);

      await finishPendingWithdrawals(hre, beneficiary);
    } catch (error) {
      console.log(chalk.red("Error finishing pending withdrawals:"), error);
    }
  });
