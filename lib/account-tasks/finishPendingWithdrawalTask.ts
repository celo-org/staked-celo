import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_FINISH_PENDING_WITHDRAWAL } from "../tasksNames";
import { finishPendingWithdrawals } from "./helpers/finishPendingWithdrawalHelper";
import { setHreConfigs } from "./helpers/taskAction";
import {
  BENEFICIARY_DESCRIPTION,
  BENEFICIARY,
  DEPLOYMENTS_PATH_DESCRIPTION,
  DEPLOYMENTS_PATH,
  ACCOUNT_FINISH_PENDING_WITHDRAWAL_TASK_DESCRIPTION,
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  USE_PRIVATE_KEY_DESCRIPTION,
  USE_PRIVATE_KEY,
} from "../helpers/staticVariables";

task(ACCOUNT_FINISH_PENDING_WITHDRAWAL, ACCOUNT_FINISH_PENDING_WITHDRAWAL_TASK_DESCRIPTION)
  .addParam(BENEFICIARY, BENEFICIARY_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(DEPLOYMENTS_PATH, DEPLOYMENTS_PATH_DESCRIPTION, undefined, types.string)
  .addFlag(USE_PRIVATE_KEY, USE_PRIVATE_KEY_DESCRIPTION)
  .setAction(async (args, hre) => {
    try {
      console.log("Starting stakedCelo:account:finishPendingWithdrawals task...");

      setHreConfigs(hre, args[ACCOUNT], args[DEPLOYMENTS_PATH], args[USE_PRIVATE_KEY]);

      await finishPendingWithdrawals(hre, args[BENEFICIARY]);
    } catch (error) {
      console.log(chalk.red("Error finishing pending withdrawals:"), error);
    }
  });
