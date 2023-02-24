import { Deployment } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";
import { MULTISIG_UPDATE_V1_V2_DESCRIPTION } from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import {
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD,
  MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES,
  MULTISIG_SUBMIT_PROPOSAL,
  MULTISIG_UPDATE_V1_V2,
} from "../tasksNames";

task(MULTISIG_UPDATE_V1_V2, MULTISIG_UPDATE_V1_V2_DESCRIPTION).setAction(async (_, hre) => {
  try {
    taskLogger.setLogLevel("info");
    taskLogger.info(`${MULTISIG_UPDATE_V1_V2} task...`);
    await setLocalNodeDeploymentPath(hre);
    const destinations: string[] = [];
    const values: number[] = [];
    const payloads: string[] = [];

    await updateAbiOfV1(hre, "MultiSig")
    await updateAbiOfV1(hre, "Manager")
    await updateAbiOfV1(hre, "Account")
    await updateAbiOfV1(hre, "StakedCelo")
    await updateAbiOfV1(hre, "RebasedStakedCelo")

    await generateContractUpdate(hre, "MultiSig", destinations, values, payloads);
    await generateContractUpdate(hre, "Manager", destinations, values, payloads);
    await generateContractUpdate(hre, "Account", destinations, values, payloads);
    await generateContractUpdate(hre, "StakedCelo", destinations, values, payloads);
    await generateContractUpdate(hre, "RebasedStakedCelo", destinations, values, payloads);

    const {destination, value, payload} = await hre.run(MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES)
    if (payload == null) {
      throw Error("There was a problem in task " + MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES)
    }

    destinations.push(destination)
    values.push(value)
    payloads.push(payload)

    taskLogger.info("--destinations", destinations.join(","));
    taskLogger.info("--values", values.join(","));
    taskLogger.info("--payloads", payloads.join(","));

    taskLogger.info(`Use these values with ${MULTISIG_SUBMIT_PROPOSAL} task`);

    taskLogger.info(chalk.green(
      `yarn hardhat ${MULTISIG_SUBMIT_PROPOSAL} --network ${
        hre.network.name
      } --destinations ${destinations.join(",")} --values ${values.join(
        ","
      )} --payloads ${payloads.join(",")} --account '<YOUR_ACCOUNT_ADDRESS>'`
    ));
  } catch (error) {
    taskLogger.error("Error encoding manager setDependencies payload:", error);
  }
});

async function generateContractUpdate(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  destinations: string[],
  values: number[],
  payloads: string[]
) {
  const accountContract = await hre.ethers.getContract(contractName);
  destinations.push(accountContract.address);
  values.push(0);
  payloads.push(
    await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
      contract: contractName,
      function: "upgradeTo",
      args: (await hre.deployments.get(`${contractName}_Implementation`)).address,
    })
  );
}

async function updateAbiOfV1(hre: HardhatRuntimeEnvironment, contract: string) {
  const contractDeployment: Deployment = await hre.deployments.get(contract);
  const artifact = await hre.deployments.getExtendedArtifact(contract);
  if (JSON.stringify(artifact.abi) !== JSON.stringify(contractDeployment.abi)) {
    taskLogger.info(
      chalk.red(
        `Deployment abi differs from artifact abi. This can happen when updating proxy that is owned by multisig. In such case Hardhat deploy plugin will update only ${contract}_Implementation.json but ${contract}.json stays untouched. We will try to update deployment based on ${contract} artifact.`
      )
    );
    contractDeployment.abi = artifact.abi;
    await hre.deployments.save(contract, { ...contractDeployment});
  }
}