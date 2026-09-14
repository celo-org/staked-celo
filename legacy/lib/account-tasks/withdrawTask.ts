import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  ACCOUNT_WITHDRAW_TASK_DESCRIPTION,
  BENEFICIARY,
  BENEFICIARY_DESCRIPTION,
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { ACCOUNT_WITHDRAW } from "../tasksNames";
import { withdraw } from "./helpers/withdrawalHelper";

task(ACCOUNT_WITHDRAW, ACCOUNT_WITHDRAW_TASK_DESCRIPTION)
  .addParam(BENEFICIARY, BENEFICIARY_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);

    try {
      taskLogger.info("Starting stakedCelo:account:withdraw task...");

      const signer = await getSignerAndSetDeploymentPath(hre, args);

      await withdraw(hre, signer, args.beneficiary!);
    } catch (error) {
      taskLogger.error("Error withdrawing CELO:", error);
    }
  });
