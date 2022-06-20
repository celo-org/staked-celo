import { task, types } from "hardhat/config";
const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

task("stakedCelo:deploy", "Deploys contracts with custom hardhat config options.")
  .addParam(
    "overrideNetwork",
    "(Required)The target network to deploy the contracts.",
    undefined,
    types.string
  )
  .addOptionalParam("url", "Host url.", undefined, types.string)
  .addOptionalParam(
    "tags",
    "Target deployment of contracts with given tags.",
    undefined,
    types.string
  )
  .addOptionalParam("from", "Account used to deploy the contracts", undefined, types.string)
  .addFlag(
    "usePrivateKey",
    "Determines if private key in .env is used or not. Private key will be used automatically if network url is a remote."
  )
  .setAction(async (taskArgs, hre) => {
    try {
      console.log("Starting stakedCelo:deploy task...");
      const networks = hre.config.networks;
      console.log("accounts", networks.alfajores.accounts);
      const targetNetwork = taskArgs["overrideNetwork"];
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
