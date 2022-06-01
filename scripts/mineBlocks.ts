import hre from "hardhat";
import { JsonRpcProvider } from "@ethersproject/providers";

import { mineBlocks } from "../test-ts/utils";

let devchainProvider: JsonRpcProvider;

// Switch provider to mine block on ganache instead of the default hardhat fork
function useLocalhostProvider() {
  console.log("switching provider");
  devchainProvider = new hre.ethers.providers.JsonRpcProvider("http://localhost:7545");
}

async function mineNBlocks(n: number) {
  useLocalhostProvider();
  mineBlocks(n);
}

mineNBlocks(35);
