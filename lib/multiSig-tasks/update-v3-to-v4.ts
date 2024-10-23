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

task(MULTISIG_UPDATE_V2_V3, MULTISIG_UPDATE_V2_V3_DESCRIPTION)
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

      await generateContractUpdate(hre, "Manager", destinations, values, payloads);
      await generateContractUpdate(hre, "SpecificGroupStrategy", destinations, values, payloads);
      await generateContractUpdate(hre, "DefaultStrategy", destinations, values, payloads);
      await generateContractUpdate(hre, "Account", destinations, values, payloads);

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

