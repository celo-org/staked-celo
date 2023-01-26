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
import { taskLogger } from "../logger";
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
      taskLogger.setLogLevel("info");
      taskLogger.info(`${MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES} task...`);
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
      taskLogger.info("--destinations", managerAddress);
      taskLogger.info("--values", "0");
      taskLogger.info("--payloads", payload);

      taskLogger.info(`Use these values with ${MULTISIG_SUBMIT_PROPOSAL} task`);
    } catch (error) {
      taskLogger.error("Error getting groups:", error);
    }
  });
