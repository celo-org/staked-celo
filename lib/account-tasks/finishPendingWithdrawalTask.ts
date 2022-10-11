import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_FINISH_PENDING_WITHDRAWAL } from "../tasksNames";
import { finishPendingWithdrawals } from "./helpers/finishPendingWithdrawalHelper";
import {
  BENEFICIARY_DESCRIPTION,
  BENEFICIARY,
  ACCOUNT_FINISH_PENDING_WITHDRAWAL_TASK_DESCRIPTION,
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_LEDGER,
} from "../helpers/staticVariables";
import { getSigner, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";

task(ACCOUNT_FINISH_PENDING_WITHDRAWAL, ACCOUNT_FINISH_PENDING_WITHDRAWAL_TASK_DESCRIPTION)
  .addParam(BENEFICIARY, BENEFICIARY_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args, hre) => {
    try {
      console.log("Starting stakedCelo:account:finishPendingWithdrawals task...");

      const signer = await getSigner(hre, args[ACCOUNT], args[USE_LEDGER], args[USE_NODE_ACCOUNT]);
      await setLocalNodeDeploymentPath(hre);

      await finishPendingWithdrawals(hre, signer, args[BENEFICIARY]);
    } catch (error) {
      console.log(chalk.red("Error finishing pending withdrawals:"), error);
    }
  });
