import { ContractKit, newKitFromWeb3 } from "@celo/contractkit";
import { extendEnvironment } from "hardhat/config";
import { lazyObject } from "hardhat/plugins";

declare module "hardhat/types/runtime" {
  export interface HardhatRuntimeEnvironment {
    kit: ContractKit;
  }
}

extendEnvironment((hre) => {
  hre.kit = lazyObject(() => {
    const kit = newKitFromWeb3(hre.web3);
    kit.connection.defaultGasPrice = 1000000000;
    return kit;
  });
});
