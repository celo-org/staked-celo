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

const argv = minimist(process.argv.slice(2));
const { network } = argv;
config({ path: network === "" || !network ? ".env" : `.env.${network}` });

// --- Monkey-patching ---
import "./lib/bignumber-monkeypatch";
import "./lib/deployTask";

const ALFAJORES_FROM = "0x5bC1C4C1D67C5E4384189302BC653A611568a788";
const STAGING_FROM = "0x5bC1C4C1D67C5E4384189302BC653A611568a788";
const MAINNET_FROM = "0xE23a4c6615669526Ab58E9c37088bee4eD2b2dEE";

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
      alfajores: 0,
      staging: 0,
    },
    // Temp to get some deployments working
    manager: {
      default: 2,
    },
    multisigOwner0: {
      default: 3,
      // on alfajores and staging, multisig will be a 1 of 1 since the network tag is only provided here.
      alfajores: "0x0a692a271DfAf2d36E46f50269c932511B55e871",
      staging: "0x0a692a271DfAf2d36E46f50269c932511B55e871",
    },
    multisigOwner1: {
      default: 4,
    },
    multisigOwner2: {
      default: 5,
    },
    // Used as owner in test fixtures instead of multisig
    owner: {
      default: 6,
    },
  },
  networks: {
    local: {
      url: "http://localhost:8545",
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
      gas: 4000000,
      from: ALFAJORES_FROM,
    },
    staging: {
      url: `https://staging-forno.celo-networks-dev.org/`,
      gas: 4000000,
      from: STAGING_FROM,
    },
    mainnet: {
      url: `https://forno.celo.org/`,
      gas: 4000000,
      from: MAINNET_FROM,
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
