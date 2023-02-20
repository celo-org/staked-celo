import { Deployment } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
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

    const managerDeployment: Deployment = await hre.deployments.get("Manager");
    const managerAddress = managerDeployment.address;

    const artifact = await hre.deployments.getExtendedArtifact("Manager");
    if (JSON.stringify(artifact.abi) !== JSON.stringify(managerDeployment.abi)) {
      taskLogger.info(
        chalk.red(
          "Deployment abi differs from artifact abi. This can happen when updating proxy that is owned by multisig. In such case Hardhat deploy plugin will update only Manager_Implementation.json but Manager.json stays untouched. We will try to update deployment based on Manager artifact."
        )
      );
      await hre.deployments.save("Manager", { ...artifact, address: managerAddress });
    }

    await setLocalNodeDeploymentPath(hre);
    const payload = await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
      contract: "Manager",
      function: "setDependencies",
      args: `${(await hre.deployments.get("StakedCelo")).address},${
        (
          await hre.deployments.get("Account")
        ).address
      },${(await hre.deployments.get("Vote")).address},${
        (
          await hre.deployments.get("GroupHealth")
        ).address
      },${(await hre.deployments.get("SpecificGroupStrategy")).address},${
        (
          await hre.deployments.get("DefaultStrategy")
        ).address
      }`,
    });

    taskLogger.info("--destinations", managerAddress);
    taskLogger.info("--values", "0");
    taskLogger.info("--payloads", payload);

    taskLogger.info(`Use these values with ${MULTISIG_SUBMIT_PROPOSAL} task`);

    return {
      destination: managerAddress,
      value: 0,
      payload: payload,
    };
  } catch (error) {
    taskLogger.error("Error encoding manager setDependencies payload:", error);
  }
});
