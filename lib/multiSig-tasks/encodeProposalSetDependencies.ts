import chalk from "chalk";
import { task, types } from "hardhat/config";
import { setLocalNodeDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";
import {
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD,
  MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES,
  MULTISIG_SUBMIT_PROPOSAL,
} from "../tasksNames";

task(MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES, MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES_DESCRIPTION)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      console.log(`${MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES} task...`);
      await setLocalNodeDeploymentPath(hre);
      const payload = await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
        contract: "Manager",
        function: "setDependencies",
        args: `${(await hre.deployments.get("StakedCelo")).address},${
          (
            await hre.deployments.get("Account")
          ).address
        },${(await hre.deployments.get("Vote")).address}`,
      });
      const managerAddress = (await hre.deployments.get("Manager")).address;
      console.log(chalk.green("--destinations"), managerAddress);
      console.log(chalk.green("--values"), "0");
      console.log(chalk.green("--payloads"), payload);

      console.log(chalk.yellow(`Use these values with ${MULTISIG_SUBMIT_PROPOSAL} task`));
    } catch (error) {
      console.log(chalk.red("Error getting groups:"), error);
    }
  });
