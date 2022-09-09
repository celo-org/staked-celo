import chalk from "chalk";
import { task, types } from "hardhat/config";

import { ACCOUNT_WITHDRAW } from "../tasksNames";
import {
  BENEFICIARY_DESCRIPTION,
  BENEFICIARY_PARAM_NAME,
  DEPLOYMENTS_PATH_DESCRIPTION,
  DEPLOYMENTS_PATH_PARAM_NAME,
  FROM_DESCRIPTION,
  FROM_PARAM_NAME,
  USE_PRIVATE_KEY_DESCRIPTION,
  USE_PRIVATE_KEY_PARAM_NAME,
  WITHDRAW_TASK_DESCRIPTION,
} from "./helpers/staticVariables";
import { setHreConfigs } from "./helpers/taskAction";
import { withdraw } from "./helpers/withdrawalHelper";

task(ACCOUNT_WITHDRAW, WITHDRAW_TASK_DESCRIPTION)
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
      console.log("Starting stakedCelo:account:withdraw task...");

      setHreConfigs(hre, from, deploymentsPath, usePrivateKey);

      await withdraw(hre, beneficiary);
    } catch (error) {
      console.log(chalk.red("Error withdrawing CELO:"), error);
    }
  });
