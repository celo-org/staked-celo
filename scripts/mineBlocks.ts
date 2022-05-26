import hre from "hardhat";
import { JsonRpcProvider } from "@ethersproject/providers";

let devchainProvider: JsonRpcProvider;

function useLocalhostProvider() {
  console.log("switching provider");
  devchainProvider = new hre.ethers.providers.JsonRpcProvider("http://localhost:7545");
}

async function mineNBlocks(n: number) {
  useLocalhostProvider();
  console.log(`Mining ${n} Blocks`);
  for (let index = 0; index < n; index++) {
    await devchainProvider.send("evm_mine", []);
  }
}

mineNBlocks(35);
