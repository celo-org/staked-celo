import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  ACCOUNT_REVOKE_TASK_DESCRIPTION,
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { ACCOUNT_REVOKE } from "../tasksNames";
import { revoke } from "./helpers/revokeHelper";

task(ACCOUNT_REVOKE, ACCOUNT_REVOKE_TASK_DESCRIPTION)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);

    try {
      taskLogger.info("Starting stakedCelo:account:revoke task...");

      const signer = await getSignerAndSetDeploymentPath(hre, args);

      await revoke(hre, signer);
    } catch (error) {
      taskLogger.error("Error revoking CELO:", error);
    }
  });
