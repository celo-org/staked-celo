import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_ACTIVATE_AND_VOTE } from "../tasksNames";
import { activateAndvote } from "../activateAndVoteHelper";

const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
task(ACCOUNT_ACTIVATE_AND_VOTE, "Activate CELO and vote for validator groups")
  .addOptionalParam("from", "Address to send transactions from", undefined, types.string)
  .addFlag("usePrivateKey", "Use private key stored in .env file to sign transactions")
  .setAction(async ({ from, usePrivateKey }, hre) => {
    try {
      let hostUrl;
      const networks = hre.config.networks;
      const targetNetwork = hre.network.name;

      if (from !== undefined) {
        networks[targetNetwork].from = from;
      }

      //@ts-ignore Property 'url' does not exist on type 'NetworkConfig'.
      hostUrl = String(networks[targetNetwork].url);
      // If deploying via remote host, then deployment will use private key from .env automatically.
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
