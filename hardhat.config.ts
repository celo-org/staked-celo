// --- Hardhat plugins ---
import { HardhatUserConfig } from "hardhat/types";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@typechain/hardhat";
import "hardhat-deploy";
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
    local: {
      url: "http://localhost:8545",
      gas: 13000000,
      gasPrice: 100000000000,
    },
    devchain: {
      url: "http://localhost:7545",
      // Having to set a default value for gas, as the provider does not estimate
      // gas properly when signing using ledger HW, resulting in an error.
      gas: 2100000,
      gasPrice: 8000000000,
    },
    hardhat: {
      forking: {
        // Local ganache
        url: "http://localhost:7545",
        blockNumber: 399,
      },
    },
    alfajores: {
      url: `https://alfajores-forno.celo-testnet.org/`,
      gas: 13000000,
      gasPrice: 100000000000,
    },
    staging: {
      url: `https://staging-forno.celo-networks-dev.org/`,
      gas: 13000000,
      gasPrice: 100000000000,
    },
    mainnet: {
      url: `https://forno.celo.org/`,
      gas: 13000000,
      gasPrice: 20000000000,
    },
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
          metadata: { useLiteralContent: true },
        },
      },
    ],
  },
} as HardhatUserConfig;
