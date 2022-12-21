import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  AMOUNT,
  AMOUNT_DESCRIPTION,
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MANAGER_WITHDRAW_TASK_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MANAGER_WITHDRAW } from "../tasksNames";

task(MANAGER_WITHDRAW, MANAGER_WITHDRAW_TASK_DESCRIPTION)
  .addParam(AMOUNT, AMOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      taskLogger.info("Starting stakedCelo:manager:withdraw task...");
      const signer = await getSignerAndSetDeploymentPath(hre, args);

      const managerContract = await hre.ethers.getContract("Manager");
      const tx = await managerContract.connect(signer).withdraw(args.amount!, { type: 0 });
      const receipt = await tx.wait();

      taskLogger.debug("receipt status", receipt.status);
    } catch (error) {
      taskLogger.error("Error withdrawing stCELO:", error);
    }
  });
