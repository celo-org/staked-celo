// --- Hardhat plugins ---
import { HardhatUserConfig } from "hardhat/types";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@typechain/hardhat";
import "@celo/staked-celo-hardhat-deploy";
import "./lib/contractkit.plugin";
import minimist from "minimist";
import { config } from "dotenv";
// --- Monkey-patching ---
import "./lib/bignumber-monkeypatch";

const argv = minimist(process.argv.slice(2));
const { network } = argv;
config({ path: network === "" || !network || network === "devchain" ? ".env" : `.env.${network}` });

import "./lib/deployTask";
import "./lib/account-tasks/accountTask";
import "./lib/multiSig-tasks/multiSigTask";
import "./lib/manager-tasks/managerTask";

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  paths: {
    tests: "test-ts",
  },
  typechain: {
    target: "ethers-v5",
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    multisigOwner0: {
      default: 3,
    },
    multisigOwner1: {
      default: 4,
    },
    multisigOwner2: {
      default: 5,
    },
    multisigOwner3: {
      default: 6,
    },
    multisigOwner4: {
      default: 7,
    },
    // Used as owner in test fixtures instead of multisig
    owner: {
      default: 6,
    },
  },
  networks: {
    hardhat: {
      chainId: 42220,
      forking: {
        // Local ganache
        url: "https://celo-mainnet.infura.io/v3/8778434b8aab43b29430bc46ecc5ae69"
      },
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.5.13",
        settings: {
          evmVersion: "istanbul",
          metadata: { useLiteralContent: true },
        },
      },
      {
        version: "0.8.11",
        settings: {
          evmVersion: "istanbul",
          metadata: { useLiteralContent: true }
        },
      },
    ],
  },
} as HardhatUserConfig;
