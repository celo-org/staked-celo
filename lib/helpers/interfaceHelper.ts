import { ContractReceipt, Signer } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import chalk from "chalk";

export async function getSigner(
  hre: HardhatRuntimeEnvironment,
  account: string,
  useLedger: boolean
): Promise<Signer> {
  let signer: Signer;
  try {
    if (useLedger) {
      signer = new LedgerSigner(hre.ethers.provider);
    } else {
      if (account === undefined) {
        throw new Error("Account is required when not using Ledger wallet.");
      }
      if (hre.ethers.utils.isAddress(account)) {
        signer = await hre.ethers.getSigner(account);
      } else {
        signer = await hre.ethers.getNamedSigner(account);
      }
    }

    return signer;
  } catch (error) {
    throw error;
  }
}

export function parseEvents(receipt: ContractReceipt, eventName: string) {
  const event = receipt.events?.find((event) => event.event === eventName);
  console.log(chalk.green("new event emitted:"), event?.event, `(${event?.args})`);
}
