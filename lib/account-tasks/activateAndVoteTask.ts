import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_ACTIVATE_AND_VOTE } from "../tasksNames";
import { activateAndvote } from "./helpers/activateAndVoteHelper";
import {
  ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION,
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";

task(ACCOUNT_ACTIVATE_AND_VOTE, ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      console.log("Starting stakedCelo:account:activateAndvote task...");

      const signer = await getSignerAndSetDeploymentPath(hre, args);

      await activateAndvote(hre, signer);
    } catch (error) {
      console.log(chalk.red("Error activating and voting"), error);
    }
  });
