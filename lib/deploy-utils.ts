import { HardhatRuntimeEnvironment } from "hardhat/types";
import hre, { ethers, kit, web3 } from "hardhat";

export const executeAndWait = async (operation: any) => {
  const tx = await operation;
  await tx.wait();
};

export async function catchNotOwnerForProxy(action: Promise<any> | (() => Promise<any>)) {
  try {
    if (action instanceof Promise) {
      await action;
    } else {
      await action();
    }
  } catch (e: any) {
    if ((e.reason as string)?.indexOf("Ownable: caller is not the owner") >= 0) {
      console.log(
        "Transaction was reverted since caller is not an owner. Please make sure to update the proxy implementation manually."
      );
      return;
    } else if (e.error?.data) {
      const data = e.error.data;
      const encodedSenderMustBeMultisigWallet = web3.eth.abi.encodeFunctionSignature(
        "SenderMustBeMultisigWallet(address)"
      );
      if (data.indexOf(encodedSenderMustBeMultisigWallet) == 0) {
        console.log(
          "Transaction was reverted since caller is not an owner. Please make sure to update the proxy implementation manually."
        );
        return;
      }
      throw e;
    }
    throw e;
  }
}
