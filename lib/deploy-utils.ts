import { DeployResult } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
import { ContractTransaction } from "ethers";
import { web3 } from "hardhat";

export const executeAndWait = async (operation: Promise<ContractTransaction>) => {
  const tx = await operation;
  await tx.wait();
};

export async function catchNotOwnerForProxy(
  action: Promise<DeployResult> | (() => Promise<DeployResult>)
) {
  try {
    if (action instanceof Promise) {
      await action;
    } else {
      await action();
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (e: any) {
    if (
      ((e.reason as string) ?? e?.data?.stack)?.indexOf("Ownable: caller is not the owner") >= 0
    ) {
      console.log(
        chalk.red(
          "Transaction was reverted since caller is not an owner. Please make sure to update the proxy implementation manually."
        )
      );
      return;
    } else if (e.error?.data) {
      const data = e.error.data;
      const encodedSenderMustBeMultisigWallet = web3.eth.abi.encodeFunctionSignature(
        "SenderMustBeMultisigWallet(address)"
      );
      console.log("encodedSenderMustBeMultisigWallet", encodedSenderMustBeMultisigWallet);
      if (data.indexOf(encodedSenderMustBeMultisigWallet) == 0) {
        console.log(
          chalk.red(
            "Transaction was reverted since caller is not an owner. Please make sure to update the proxy implementation manually."
          )
        );
        return;
      }
      throw e;
    } else if (e?.data?.contract?.method.indexOf("upgradeTo") >= 0) {
      console.log(
        chalk.red(
          "Transaction was reverted since caller is not an owner. Please make sure to update the proxy implementation manually."
        )
      );
      return;
    }

    throw e;
  }
}
