import { HardhatRuntimeEnvironment } from "hardhat/types";

const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

export function setHreConfigs(
  hre: HardhatRuntimeEnvironment,
  from: string,
  deploymentsPath: string,
  usePrivateKey: string
) {
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
    if (from === undefined) {
      throw "Must specify account address when using private key";
    }
    networks[targetNetwork].accounts = [`0x${privateKey}`];
  }
}
