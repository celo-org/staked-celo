import { ContractReceipt, Signer } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import chalk from "chalk";

const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

export async function getSigner(
  hre: HardhatRuntimeEnvironment,
  account: string,
  useLedger: boolean,
  useNodeAccount: boolean
): Promise<Signer> {
  let signer: Signer;
  try {
    if (useLedger) {
      signer = new LedgerSigner(hre.ethers.provider);
    } else {
      if (account === undefined) {
        throw "Account is required when not using Ledger device.";
      }
      if (!useNodeAccount) {
        if (privateKey === undefined) {
          throw "Private key not found.";
        }
        // Will default to using a private key if found.
        const networks = hre.config.networks;
        const targetNetwork = hre.network.name;
        networks[targetNetwork].accounts = [`0x${privateKey}`];
      }

      if (hre.ethers.utils.isAddress(account)) {
        signer = await hre.ethers.getSigner(account);
      } else {
        signer = await hre.ethers.getNamedSigner(account);
      }
    }

    return signer;
  } catch (error) {
    throw error;
  }
}

export function parseEvents(receipt: ContractReceipt, eventName: string) {
  const event = receipt.events?.find((event) => event.event === eventName);
  console.log(chalk.green("new event emitted:"), event?.event, `(${event?.args})`);
}

export async function setLocalNodeDeploymentPath(hre: HardhatRuntimeEnvironment) {
  try {
    const targetNetwork = hre.network;
    if (targetNetwork.name !== "local") {
      return;
    }
    const currentNetworkId = await hre.ethers.provider.getNetwork();

    switch (currentNetworkId.chainId) {
      case 44787:
        setAlfajoresDeploymentPath(hre);
        break;
      case 1101:
        setStagingDeploymentPath(hre);
        break;
      case 42220:
        setMainnetDeploymentPath(hre);
        break;
      case 1337: // devchain chain ID
        break;

      default:
        throw new Error(`Unsupported Network ID: ${currentNetworkId.chainId}`);
    }
  } catch (error) {
    throw error;
  }
}

function setAlfajoresDeploymentPath(hre: HardhatRuntimeEnvironment) {
  hre.config.external = {
    deployments: {
      local: ["deployments/alfajores"],
    },
  };
}

function setStagingDeploymentPath(hre: HardhatRuntimeEnvironment) {
  hre.config.external = {
    deployments: {
      local: ["deployments/staging"],
    },
  };
}

function setMainnetDeploymentPath(hre: HardhatRuntimeEnvironment) {
  hre.config.external = {
    deployments: {
      local: ["deployments/mainnet"],
    },
  };
}
