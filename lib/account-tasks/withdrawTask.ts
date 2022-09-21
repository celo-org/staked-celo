import chalk from "chalk";
import { task, types } from "hardhat/config";

import { ACCOUNT_WITHDRAW } from "../tasksNames";
import {
  BENEFICIARY_DESCRIPTION,
  BENEFICIARY,
  DEPLOYMENTS_PATH_DESCRIPTION,
  DEPLOYMENTS_PATH,
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  USE_PRIVATE_KEY_DESCRIPTION,
  USE_PRIVATE_KEY,
  ACCOUNT_WITHDRAW_TASK_DESCRIPTION,
} from "../helpers/staticVariables";
import { setHreConfigs } from "./helpers/taskAction";
import { withdraw } from "./helpers/withdrawalHelper";

task(ACCOUNT_WITHDRAW, ACCOUNT_WITHDRAW_TASK_DESCRIPTION)
  .addParam(BENEFICIARY, BENEFICIARY_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(DEPLOYMENTS_PATH, DEPLOYMENTS_PATH_DESCRIPTION, undefined, types.string)
  .addFlag(USE_PRIVATE_KEY, USE_PRIVATE_KEY_DESCRIPTION)
  .setAction(async (args, hre) => {
    try {
      console.log("Starting stakedCelo:account:withdraw task...");

      setHreConfigs(hre, args[ACCOUNT], args[DEPLOYMENTS_PATH], args[USE_PRIVATE_KEY]);

      await withdraw(hre, args[BENEFICIARY]);
    } catch (error) {
      console.log(chalk.red("Error withdrawing CELO:"), error);
    }
  });
