// --- Hardhat plugins ---
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@typechain/hardhat";
import "hardhat-deploy";
import "./lib/contractkit.plugin";
import "dotenv/config";

// --- Monkey-patching ---
import "./lib/bignumber-monkeypatch";

const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

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
    },
    // Temp to get some deployments working
    manager: {
      default: 2,
    },
    multisigOwner0: {
      default: 3,
      // on alfajores, multisig will be a 1 of 1 since the network tag is only provided in one place.
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
        // url: "https://alfajores-forno.celo-testnet.org"
      },
    },
    alfajores: {
      url: `https://alfajores-forno.celo-testnet.org/`,
      accounts: [`${privateKey}`],
      gas: 4000000,
    },
    staging: {
      url: `https://staging-forno.celo-networks-dev.org/`,
      accounts: [`${privateKey}`],
      gas: 4000000,
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
};
