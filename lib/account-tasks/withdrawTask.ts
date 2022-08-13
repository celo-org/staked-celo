import chalk from "chalk";
import { task, types } from "hardhat/config";

import { ACCOUNT_WITHDRAW } from "../tasksNames";
import { withdraw } from "./helpers/withdrawalHelpter";

const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

task(ACCOUNT_WITHDRAW, "Withdraws CELO from account contract.")
  .addParam("beneficiary", "The address of the account to withdraw for.", undefined, types.string)
  .addOptionalParam(
    "from",
    "The address of the account used to sign transactions.",
    undefined,
    types.string
  )
  .addOptionalParam(
    "deploymentsPath",
    "Path of deployed contracts data. Used when connecting to a local node.",
    undefined,
    types.string
  )
  .addFlag(
    "usePrivateKey",
    "Determines if private key in environment is used or not. Private key will be used automatically if network url is a remote host."
  )
  .setAction(async ({ beneficiary, from, deploymentsPath, usePrivateKey }, hre) => {
    try {
      console.log("Starting stakedCelo:withdraw task...");
      let hostUrl;
      const networks = hre.config.networks;
      const targetNetwork = hre.network.name;

      if (targetNetwork == "local") {
        if (deploymentsPath === undefined) {
          throw new Error("Must specify contracts deployment data file path.");
        } else {
          hre.config.external = {
            deployments: {
              local: [deploymentsPath],
            },
          };
        }
      }

      if (from !== undefined) {
        networks[targetNetwork].from = from;
      }

      //@ts-ignore Property 'url' does not exist on type 'NetworkConfig'.

      hostUrl = String(networks[targetNetwork].url);
      // If deploying via remote host, then deployment will use private key from .env automatically.
      if (hostUrl.includes("https")) {
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      // User can optionally specify using a private key irrespective of deploying to remote network or not.
      if (usePrivateKey) {
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      await withdraw(hre, beneficiary);
    } catch (error) {
      console.log(chalk.red("Error withdrawing CELO:"), error);
    }
  });
