import chalk from "chalk";
import { task, types } from "hardhat/config";
import { STAKED_CELO_DEPLOY } from "./tasksNames";
const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

// Defaults
const DEPLOYER = process.env.DEPLOYER;
const MULTISIG_SIGNER_0 = process.env.MULTISIG_SIGNER_0;
const MULTISIG_SIGNER_1 = process.env.MULTISIG_SIGNER_1;
const MULTISIG_SIGNER_2 = process.env.MULTISIG_SIGNER_2;
const MULTISIG_SIGNER_3 = process.env.MULTISIG_SIGNER_3;
const MULTISIG_SIGNER_4 = process.env.MULTISIG_SIGNER_4;

task(STAKED_CELO_DEPLOY, "Deploys contracts with custom hardhat config options.")
  .addOptionalParam("url", "Host url.", undefined, types.string)
  .addOptionalParam(
    "tags",
    "Target deployment of contracts with provided tags.",
    undefined,
    types.string
  )
  .addOptionalParam(
    "from",
    "The address of the account used to deploy the contracts.",
    undefined,
    types.string
  )
  .addFlag(
    "usePrivateKey",
    "Determines if private key in environment is used or not. Private key will be used automatically if network url is a remote host."
  )
  .setAction(async (taskArgs, hre) => {
    try {
      console.log(chalk.blue("Starting stakedCelo:deploy task..."));
      const networks = hre.config.networks;
      const targetNetwork = hre.network.name;

      if (targetNetwork !== "hardhat") {
        const deployer = { [targetNetwork]: DEPLOYER };
        const multisigOwner0 = { [targetNetwork]: MULTISIG_SIGNER_0 };
        const multisigOwner1 = { [targetNetwork]: MULTISIG_SIGNER_1 };
        const multisigOwner2 = { [targetNetwork]: MULTISIG_SIGNER_2 };
        const multisigOwner3 = { [targetNetwork]: MULTISIG_SIGNER_3 };
        const multisigOwner4 = { [targetNetwork]: MULTISIG_SIGNER_4 };
        hre.config.namedAccounts = {
          //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
          ...hre.config.namedAccounts,
          //@ts-ignore Computed Property [targetNetwork]
          deployer: { ...hre.config.namedAccounts.deployer, ...deployer },
        };
        hre.config.namedAccounts = {
          //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
          ...hre.config.namedAccounts,
          //@ts-ignore Computed Property [targetNetwork]
          multisigOwner0: { ...hre.config.namedAccounts.multisigOwner0, ...multisigOwner0 },
        };
        hre.config.namedAccounts = {
          //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
          ...hre.config.namedAccounts,
          //@ts-ignore Computed Property [targetNetwork]
          multisigOwner1: { ...hre.config.namedAccounts.multisigOwner1, ...multisigOwner1 },
        };
        hre.config.namedAccounts = {
          //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
          ...hre.config.namedAccounts,
          //@ts-ignore Computed Property [targetNetwork]
          multisigOwner2: { ...hre.config.namedAccounts.multisigOwner2, ...multisigOwner2 },
        };
        hre.config.namedAccounts = {
          //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
          ...hre.config.namedAccounts,
          //@ts-ignore Computed Property [targetNetwork]
          multisigOwner3: { ...hre.config.namedAccounts.multisigOwner3, ...multisigOwner3 },
        };
        hre.config.namedAccounts = {
          //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
          ...hre.config.namedAccounts,
          //@ts-ignore Computed Property [targetNetwork]
          multisigOwner4: { ...hre.config.namedAccounts.multisigOwner4, ...multisigOwner4 },
        };
        hre.config.networks[targetNetwork].from = DEPLOYER;
      }

      if (taskArgs["from"] !== undefined) {
        networks[targetNetwork].from = taskArgs["from"];
        hre.config.namedAccounts = {
          //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
          ...hre.config.namedAccounts,
          //@ts-ignore Computed Property [targetNetwork]
          deployer: { ...hre.config.namedAccounts.deployer, [targetNetwork]: taskArgs["from"] },
        };
      }

      if (taskArgs["url"] !== undefined) {
        //@ts-ignore Property 'url' does not exist on type 'NetworkConfig'.
        networks[targetNetwork].url = taskArgs["url"];
      }

      //@ts-ignore Property 'url' does not exist on type 'NetworkConfig'.
      const hostUrl = String(networks[targetNetwork].url);
      // If deploying via remote host, then deployment will use private key from .env automatically.
      if (hostUrl.includes("https")) {
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      // User can optionally specify using a private key irrespective of deploying to remote network or not.
      if (taskArgs["usePrivateKey"]) {
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      hre.config.networks = networks;
      console.log("Deploying with the following network settings...", hre.config.namedAccounts);
      return await hre.run("deploy", taskArgs);
    } catch (error) {
      console.log(error);
    }
  });
