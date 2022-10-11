import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath } from "../helpers/interfaceHelper";

import { MANAGER_WITHDRAW } from "../tasksNames";
import {
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  AMOUNT_DESCRIPTION,
  AMOUNT,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  MANAGER_WITHDRAW_TASK_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";

task(MANAGER_WITHDRAW, MANAGER_WITHDRAW_TASK_DESCRIPTION)
  .addParam(AMOUNT, AMOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args, hre) => {
    try {
      console.log("Starting stakedCelo:manager:withdraw task...");
      const signer = await getSignerAndSetDeploymentPath(
        hre,
        args[ACCOUNT],
        args[USE_LEDGER],
        args[USE_NODE_ACCOUNT]
      );

      const managerContract = await hre.ethers.getContract("Manager");
      const tx = await managerContract.connect(signer).withdraw(args[AMOUNT], { type: 0 });
      const receipt = await tx.wait();
      console.log(chalk.yellow("receipt status"), receipt.status);
    } catch (error) {
      console.log(chalk.red("Error withdrawing stCELO:"), error);
    }
  });
