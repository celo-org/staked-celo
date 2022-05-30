// --- Hardhat plugins ---
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@typechain/hardhat";
import "hardhat-deploy";
import "./lib/contractkit.plugin";

// --- Monkey-patching ---
import "./lib/bignumber-monkeypatch";

const privateKey = "";
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
    // Temp to get some deployments working
    manager: {
      default: 2,
    },
    multisigOwner0: {
      default: 3,
      alfajores: "0x0a692a271DfAf2d36E46f50269c932511B55e871",
    },
    multisigOwner1: {
      default: 4,
      alfajores: "0x2B73d814BA2231606f9d856C7C20423915F96711",
    },
    multisigOwner2: {
      default: 5,
      alfajores: "0xF4BB4Aa6AAD00E9B660B744736B7092816704CB9",
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
