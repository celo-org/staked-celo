import { Deployment } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { TransactionArguments, getSignerAndSetDeploymentPath, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";
import { ACCOUNT, ACCOUNT_DESCRIPTION, MULTISIG_UPDATE_V1_V2_DESCRIPTION } from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import {
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD,
  MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES,
  MULTISIG_SUBMIT_PROPOSAL,
  MULTISIG_UPDATE_V1_V2,
} from "../tasksNames";
import { Contract, Signer } from "ethers";

const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

task(MULTISIG_UPDATE_V1_V2, MULTISIG_UPDATE_V1_V2_DESCRIPTION)
.addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
.setAction(async (args: TransactionArguments, hre) => {
  try {
    taskLogger.setLogLevel("info");
    taskLogger.info(`${MULTISIG_UPDATE_V1_V2} task...`);
    await setLocalNodeDeploymentPath(hre);
    const destinations: string[] = [];
    const values: number[] = [];
    const payloads: string[] = [];

    const signer = await getSignerAndSetDeploymentPath(hre, args);
    await generateGroupActivate(hre, destinations, values, payloads, signer);

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
    await generateAllowedToVoteOverMaxNumberOfGroups(hre, destinations, values, payloads);

    const { destination, value, payload } = await hre.run(MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES)
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
      `yarn hardhat ${MULTISIG_SUBMIT_PROPOSAL} --network ${hre.network.name
      } --destinations ${destinations.join(",")} --values ${values.join(
        ","
      )} --payloads ${payloads.join(",")} --account '${await signer.getAddress()}'`
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
  ``
  taskLogger.info(`Generating contract upgrade for ${contractName}`)
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

async function generateAllowedToVoteOverMaxNumberOfGroups(
  hre: HardhatRuntimeEnvironment,
  destinations: string[],
  values: number[],
  payloads: string[]
) {
  taskLogger.info(`generating allowed to vote over maximum number of groups`)
  const accountContract = await hre.ethers.getContract("Account");
  destinations.push(accountContract.address);
  values.push(0);
  payloads.push(
    await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
      contract: "Account",
      function: "setAllowedToVoteOverMaxNumberOfGroups",
      args: "true",
    })
  );
}

const parseValidatorGroups = (validatorGroupsString: string | undefined) =>
  validatorGroupsString ? validatorGroupsString.split(",") : [];

async function generateGroupActivate(
  hre: HardhatRuntimeEnvironment,
  destinations: string[],
  values: number[],
  payloads: string[],
  signer: Signer
) {
  const groupHealthContract = await hre.ethers.getContract("GroupHealth");

  const validatorGroups = parseValidatorGroups(process.env.VALIDATOR_GROUPS);
  if (validatorGroups.length == 0) {
    return;
  }

  const defaultStrategyContract = await hre.ethers.getContract("DefaultStrategy");
  const accountContract = await hre.ethers.getContract("Account");



  const validatorGroupsWithCelo = await Promise.all(
    validatorGroups.map(async (validatorGroup) => ({
      group: validatorGroup,
      celo: (await accountContract.getCeloForGroup(validatorGroup)),
    }))
  );

  const validatorGroupsSortedDesc = validatorGroupsWithCelo.sort((a, b) =>
    a.celo.lt(b.celo) ? 1 : -1
  );

  let nextGroup = ADDRESS_ZERO;
  for (let i = 0; i < validatorGroupsSortedDesc.length; i++) {
    let healthy = await checkGroupHealth(groupHealthContract, validatorGroupsSortedDesc[i].group)

    if (!healthy) {
      taskLogger.warning(chalk.yellow(`Updating group health ${validatorGroupsSortedDesc[i].group}`));
      const tx = await groupHealthContract.connect(signer).updateGroupHealth(validatorGroupsSortedDesc[i].group)
      await tx.wait()

      healthy = await checkGroupHealth(groupHealthContract, validatorGroupsSortedDesc[i].group)
      if (!healthy) {
        continue;
      } else {
        taskLogger.info(chalk.green(`Group ${validatorGroupsSortedDesc[i].group} is healthy`))
      }
    }
    ``
    taskLogger.info(`Generating activeGroup for ${validatorGroupsSortedDesc[i].group}`)

    destinations.push(defaultStrategyContract.address);
    values.push(0);
    payloads.push(
      await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
        contract: "DefaultStrategy",
        function: "activateGroup",
        args: `${validatorGroupsSortedDesc[i].group},${ADDRESS_ZERO},${nextGroup}`,
      })
    );

    nextGroup = validatorGroupsSortedDesc[i].group;
  }
}

async function checkGroupHealth(groupHealthContract: Contract, group: string) {
  const healthy = await groupHealthContract.isGroupValid(group);
  if (!healthy) {
    console.log(
      chalk.red(
        `Group ${group} is not healthy - it cannot be activated!`
      )
    );
  }
  return healthy
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
    await hre.deployments.save(contract, { ...contractDeployment });
  }
}
