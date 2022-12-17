import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION,
  ACCOUNT_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
  VERBOSE_LOG,
  VERBOSE_LOG_DESCRIPTION,
} from "../helpers/staticVariables";
import { ACCOUNT_ACTIVATE_AND_VOTE } from "../tasksNames";
import { activateAndVote } from "./helpers/activateAndVoteHelper";

task(ACCOUNT_ACTIVATE_AND_VOTE, ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .addFlag(VERBOSE_LOG, VERBOSE_LOG_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      console.log(chalk.blue("Starting stakedCelo:account:activateAndvote task..."));

      const signer = await getSignerAndSetDeploymentPath(hre, args);

      await activateAndVote(hre, signer, args.verboseLog);
    } catch (error) {
      console.log(chalk.red("Error activating and voting:"), error);
      return error;
    }
  });
