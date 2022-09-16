import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_ACTIVATE_AND_VOTE } from "../tasksNames";
import { activateAndvote } from "./helpers/activateAndVoteHelper";
import { setHreConfigs } from "./helpers/taskAction";
import {
  ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION,
  DEPLOYMENTS_PATH_DESCRIPTION,
  DEPLOYMENTS_PATH_PARAM_NAME,
  FROM_DESCRIPTION,
  FROM_PARAM_NAME,
  USE_PRIVATE_KEY_DESCRIPTION,
  USE_PRIVATE_KEY_PARAM_NAME,
} from "../helpers/staticVariables";

task(ACCOUNT_ACTIVATE_AND_VOTE, ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION)
  .addOptionalParam(FROM_PARAM_NAME, FROM_DESCRIPTION, undefined, types.string)
  .addOptionalParam(
    DEPLOYMENTS_PATH_PARAM_NAME,
    DEPLOYMENTS_PATH_DESCRIPTION,
    undefined,
    types.string
  )
  .addFlag(USE_PRIVATE_KEY_PARAM_NAME, USE_PRIVATE_KEY_DESCRIPTION)
  .setAction(async ({ from, deploymentsPath, usePrivateKey }, hre) => {
    try {
      console.log("Starting stakedCelo:account:activateAndvote task...");
      setHreConfigs(hre, from, deploymentsPath, usePrivateKey);

      await activateAndvote(hre);
    } catch (error) {
      console.log(chalk.red("Error activating and voting"), error);
    }
  });
