import { task, types } from "hardhat/config";
import chalk from "chalk";

import { ACCOUNT_FINISH_PENDING_WITHDRAWAL } from "../tasksNames";
import { finishPendingWithdrawals } from "./helpers/pendingWithdrawalHelper";

const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
task(
  ACCOUNT_FINISH_PENDING_WITHDRAWAL,
  "Finish a pending withdrawal created as a result of a `withdraw` call."
)
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
      console.log("Starting stakedCelo:finishPendingWithdrawals task...");
      const networks = hre.config.networks;
      const targetNetwork = hre.network.name;
      let hostUrl;

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

      const res = await finishPendingWithdrawals(hre, beneficiary);
    } catch (error) {
      console.log(chalk.red("Error finishing pending withdrawals:"), error);
    }
  });
