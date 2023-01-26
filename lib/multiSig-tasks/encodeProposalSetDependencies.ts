import { task } from "hardhat/config";
import { setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";
import { MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES_DESCRIPTION } from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import {
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD,
  MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES,
  MULTISIG_SUBMIT_PROPOSAL,
} from "../tasksNames";

task(
  MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES,
  MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES_DESCRIPTION
).setAction(async (_, hre) => {
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
    taskLogger.error("Error encoding manager setDependencies payload:", error);
  }
});
