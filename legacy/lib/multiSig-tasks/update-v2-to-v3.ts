import chalk from "chalk";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  getSignerAndSetDeploymentPath,
  setLocalNodeDeploymentPath,
  TransactionArguments,
} from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  MULTISIG_UPDATE_V2_V3_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import {
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD,
  MULTISIG_SUBMIT_PROPOSAL,
  MULTISIG_UPDATE_V2_V3,
} from "../tasksNames";

const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

task(MULTISIG_UPDATE_V2_V3, MULTISIG_UPDATE_V2_V3_DESCRIPTION)
  // .addParam(OWNER_ADDRESS, OWNER_ADDRESS_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      taskLogger.setLogLevel("info");
      taskLogger.info(`${MULTISIG_UPDATE_V2_V3} task...`);
      await setLocalNodeDeploymentPath(hre);
      const destinations: string[] = [];
      const values: number[] = [];
      const payloads: string[] = [];

      const signer = await getSignerAndSetDeploymentPath(hre, args);

      await generateContractUpdate(hre, "MultiSig", destinations, values, payloads);
      await generateContractUpdate(hre, "Manager", destinations, values, payloads);
      await generateContractUpdate(hre, "Account", destinations, values, payloads);
      await generateContractUpdate(hre, "StakedCelo", destinations, values, payloads);
      await generateContractUpdate(hre, "Vote", destinations, values, payloads);
      await generateContractUpdate(hre, "GroupHealth", destinations, values, payloads);
      await generateContractUpdate(hre, "SpecificGroupStrategy", destinations, values, payloads);
      await generateContractUpdate(hre, "DefaultStrategy", destinations, values, payloads);
      await generateContractUpdate(hre, "RebasedStakedCelo", destinations, values, payloads);

      await generateMultiSigSetPauser(hre, "MultiSig", destinations, values, payloads);
      await generateSetPauser(hre, "Manager", destinations, values, payloads);
      await generateSetPauser(hre, "Account", destinations, values, payloads);
      await generateSetPauser(hre, "StakedCelo", destinations, values, payloads);
      await generateSetPauser(hre, "Vote", destinations, values, payloads);
      await generateSetPauser(hre, "GroupHealth", destinations, values, payloads);
      await generateSetPauser(hre, "SpecificGroupStrategy", destinations, values, payloads);
      await generateSetPauser(hre, "DefaultStrategy", destinations, values, payloads);
      await generateSetPauser(hre, "RebasedStakedCelo", destinations, values, payloads);

      await generateSetMinCountOfActiveGroups(hre, destinations, values, payloads);
      await generateMultiSigAddOwner(
        hre,
        "0x01AAe13F65fB90B490E6614adE0bffFA57AC5bbc",
        destinations,
        values,
        payloads
      );

      taskLogger.info("--destinations", destinations.join(","));
      taskLogger.info("--values", values.join(","));
      taskLogger.info("--payloads", payloads.join(","));

      taskLogger.info(`Use these values with ${MULTISIG_SUBMIT_PROPOSAL} task`);

      taskLogger.info(
        chalk.green(
          `yarn hardhat ${MULTISIG_SUBMIT_PROPOSAL} --network ${
            hre.network.name
          } --destinations '${destinations.join(",")}' --values '${values.join(
            ","
          )}' --payloads '${payloads.join(",")}' --account '${await signer.getAddress()}'`
        )
      );
    } catch (error) {
      taskLogger.error("Error encoding Multisig proposal payload:", error);
    }
  });

async function generateSetPauser(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  destinations: string[],
  values: number[],
  payloads: string[]
) {
  taskLogger.info(`Generating setPauser payload for ${contractName}`);
  const contract = await hre.ethers.getContract(contractName);
  destinations.push(contract.address);
  values.push(0);
  payloads.push(
    await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
      contract: contractName,
      function: "setPauser",
      args: "",
    })
  );
}
async function generateMultiSigSetPauser(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  destinations: string[],
  values: number[],
  payloads: string[]
) {
  taskLogger.info(`Generating setPauser payload for ${contractName}`);
  const multiSigContract = await hre.ethers.getContract(contractName);
  destinations.push(multiSigContract.address);
  values.push(0);
  payloads.push(
    await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
      contract: contractName,
      function: "setPauser",
      args: multiSigContract.address,
    })
  );
}
async function generateContractUpdate(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  destinations: string[],
  values: number[],
  payloads: string[]
) {
  taskLogger.info(`Generating contract upgrade for ${contractName}`);
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

async function generateMultiSigAddOwner(
  hre: HardhatRuntimeEnvironment,
  ownerAddress: string,
  destinations: string[],
  values: number[],
  payloads: string[]
) {
  if (hre.network.name === "alfajores") {
    return;
  }
  if (ownerAddress === ADDRESS_ZERO || !hre.ethers.utils.isAddress(ownerAddress)) {
    throw `Invalid Owner address ${ownerAddress}`;
  }

  taskLogger.info(`generating MultiSig addOwner payload`);
  const multiSigContract = await hre.ethers.getContract("MultiSig");
  destinations.push(multiSigContract.address);
  values.push(0);
  payloads.push(
    await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
      contract: "MultiSig",
      function: "addOwner",
      args: ownerAddress,
    })
  );
}
async function generateSetMinCountOfActiveGroups(
  hre: HardhatRuntimeEnvironment,
  destinations: string[],
  values: number[],
  payloads: string[]
) {
  taskLogger.info(`generating setMinCountOfActiveGroups payload`);
  const DefaultStrategyContract = await hre.ethers.getContract("DefaultStrategy");
  destinations.push(DefaultStrategyContract.address);
  values.push(0);
  payloads.push(
    await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
      contract: "DefaultStrategy",
      function: "setMinCountOfActiveGroups",
      args: "3",
    })
  );
}
