import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_ACTIVATE_AND_VOTE } from "../tasksNames";
import { activateAndvote } from "./helpers/activateAndVoteHelper";
import { setHreConfigs } from "./helpers/taskAction";
import {
  ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION,
  DEPLOYMENTS_PATH_DESCRIPTION,
  DEPLOYMENTS_PATH,
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  USE_PRIVATE_KEY_DESCRIPTION,
  USE_PRIVATE_KEY,
} from "../helpers/staticVariables";

task(ACCOUNT_ACTIVATE_AND_VOTE, ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(DEPLOYMENTS_PATH, DEPLOYMENTS_PATH_DESCRIPTION, undefined, types.string)
  .addFlag(USE_PRIVATE_KEY, USE_PRIVATE_KEY_DESCRIPTION)
  .setAction(async (args, hre) => {
    try {
      console.log("Starting stakedCelo:account:activateAndvote task...");
      setHreConfigs(hre, args[ACCOUNT], args[DEPLOYMENTS_PATH], args[USE_PRIVATE_KEY]);

      await activateAndvote(hre);
    } catch (error) {
      console.log(chalk.red("Error activating and voting"), error);
    }
  });
