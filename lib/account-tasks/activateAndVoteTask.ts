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
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { ACCOUNT_ACTIVATE_AND_VOTE } from "../tasksNames";
import { activateAndVote } from "./helpers/activateAndVoteHelper";

task(ACCOUNT_ACTIVATE_AND_VOTE, ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      taskLogger.info("Starting stakedCelo:account:activateAndvote task...");

      const signer = await getSignerAndSetDeploymentPath(hre, args);

      await activateAndVote(hre, signer);
    } catch (error) {
      taskLogger.error("Error activating and voting:", error);
      return error;
    }
  });
