import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_ACTIVATE_AND_VOTE } from "../tasksNames";
import { activateAndvote } from "./helpers/activateAndVoteHelper";

const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
task(ACCOUNT_ACTIVATE_AND_VOTE, "Activate CELO and vote for validator groups")
  .addOptionalParam("from", "Address to send transactions from", undefined, types.string)
  .addOptionalParam(
    "deploymentsPath",
    "Path of deployed contracts data. Used when connecting to a local node.",
    undefined,
    types.string
  )
  .addFlag("usePrivateKey", "Determines if private key in environment is used or not.")
  .setAction(async ({ from, deploymentsPath, usePrivateKey }, hre) => {
    try {
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
      // If transacting via remote host, then use private key from .env automatically.
      if (hostUrl.includes("https")) {
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      if (usePrivateKey) {
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      await activateAndvote(hre);
    } catch (error) {
      console.log(chalk.red("Error activating and voting"), error);
    }
  });
