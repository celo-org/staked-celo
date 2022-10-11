import chalk from "chalk";
import { task, types } from "hardhat/config";

import { ACCOUNT_WITHDRAW } from "../tasksNames";
import {
  BENEFICIARY_DESCRIPTION,
  BENEFICIARY,
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  ACCOUNT_WITHDRAW_TASK_DESCRIPTION,
  USE_LEDGER,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
  USE_LEDGER_DESCRIPTION,
} from "../helpers/staticVariables";
import { withdraw } from "./helpers/withdrawalHelper";
import { getSignerAndSetDeploymentPath } from "../helpers/interfaceHelper";

task(ACCOUNT_WITHDRAW, ACCOUNT_WITHDRAW_TASK_DESCRIPTION)
  .addParam(BENEFICIARY, BENEFICIARY_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args, hre) => {
    try {
      console.log("Starting stakedCelo:account:withdraw task...");

      const signer = await getSignerAndSetDeploymentPath(
        hre,
        args[ACCOUNT],
        args[USE_LEDGER],
        args[USE_NODE_ACCOUNT]
      );

      await withdraw(hre, signer, args[BENEFICIARY]);
    } catch (error) {
      console.log(chalk.red("Error withdrawing CELO:"), error);
    }
  });
