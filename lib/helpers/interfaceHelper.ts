import { ContractReceipt, Signer } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import chalk from "chalk";

export async function getSigner(
  hre: HardhatRuntimeEnvironment,
  namedAccount: string,
  useLedger: boolean
): Promise<Signer> {
  let signer: Signer;
  if (useLedger) {
    signer = new LedgerSigner(hre.ethers.provider);
  } else {
    if (namedAccount == undefined) {
      throw new Error("NamedAccount is required when not using Ledger wallet.");
    }
    signer = await hre.ethers.getNamedSigner(namedAccount);
  }

  return signer;
}

export function parseEvents(receipt: ContractReceipt, eventName: string) {
  const event = receipt.events?.find((event) => event.event === eventName);
  console.log(chalk.green("new event emitted:"), event?.event, `(${event?.args})`);
}
