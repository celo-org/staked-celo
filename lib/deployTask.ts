import { task, types } from "hardhat/config";
import { STAKED_CELO_DEPLOY } from "./tasksNames";
const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

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
      console.log("Starting stakedCelo:deploy task...");
      const networks = hre.config.networks;
      const targetNetwork = hre.network.name;
      //@ts-ignore Property 'url' does not exist on type 'NetworkConfig'.
      const hostUrl = String(network.url);

      if (taskArgs["from"] !== undefined) {
        networks[targetNetwork].from = taskArgs["from"];
      }

      if (taskArgs["url"] !== undefined) {
        //@ts-ignore Property 'url' does not exist on type 'NetworkConfig'.
        networks[targetNetwork].url = taskArgs["url"];
      }

      // If deploying to a remote network, then deployment will use private key from .env automatically.
      if (!hostUrl.includes("localhost") || !hostUrl.includes("127.0.0.1")) {
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      // User can optionally specify using a private key irrespective of deploying to remote network or port-forwarded.
      if (taskArgs["usePrivateKey"]) {
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      hre.config.networks = networks;
      return await hre.run("deploy", taskArgs);
    } catch (error) {
      console.log(error);
    }
  });
