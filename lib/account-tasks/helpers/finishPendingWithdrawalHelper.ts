import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { Contract, Signer } from "ethers";

export async function finishPendingWithdrawals(
  hre: HardhatRuntimeEnvironment,
  signer: Signer,
  beneficiaryAddress: string
) {
  try {
    const accountContract = await hre.ethers.getContract("Account");
    const numberOfPendingWithdrawals = await accountContract.getNumberPendingWithdrawals(
      beneficiaryAddress
    );
    const lockedGoldWrapper = await hre.kit.contracts.getLockedGold();

    console.log(chalk.red("number of pending withdrawal:"), numberOfPendingWithdrawals.toString());

    while (true) {
      const { localIndex, lockedGoldIndex } = await getPendingWithdrawalIndexesAndValidate(
        accountContract,
        lockedGoldWrapper,
        beneficiaryAddress
      );

      if (localIndex < 0) {
        break;
      }

      console.log(chalk.green(`beneficiary: ${beneficiaryAddress}`));
      console.log(chalk.green(`localPendingWithdrawalIndex: ${localIndex}`));
      console.log(chalk.green(`lockedGoldPendingWithdrawalIndex: ${lockedGoldIndex}`));

      const tx = await accountContract
        .connect(signer)
        .finishPendingWithdrawal(beneficiaryAddress, localIndex, lockedGoldIndex);
      const receipt = await tx.wait();

      console.log(chalk.yellow("receipt status"), receipt.status);
    }
  } catch (error) {
    throw error;
  }
}

async function getPendingWithdrawalIndexesAndValidate(
  accountContract: Contract,
  lockedGoldWrapper: LockedGoldWrapper,
  beneficiary: string
): Promise<{ localIndex: number; lockedGoldIndex: number }> {
  try {
    let lockedGoldIndex: number;
    const localIndexPredicate = (timestamp: string) => {
      return Number(timestamp) < Date.now() / 1000;
    };

    // get pending withdrawals
    const localPendingWithdrawals = await accountContract.getPendingWithdrawals(beneficiary);
    const lockedPendingWithdrawals = await lockedGoldWrapper.getPendingWithdrawals(
      accountContract.address
    );

    if (localPendingWithdrawals[0].length != localPendingWithdrawals[1].length) {
      throw new Error("mismatched list");
    }

    const localValueList: string[] = localPendingWithdrawals[0];
    const localTimestampList: string[] = localPendingWithdrawals[1];

    // find index for released funds
    const localIndex: number = localTimestampList.findIndex(localIndexPredicate);

    if (localIndex === -1) {
      lockedGoldIndex = -1;
      return { localIndex, lockedGoldIndex };
    }

    const localValue = localValueList[localIndex];
    const localTimestamp = localTimestampList[localIndex];

    const goldIndexPredicate = (goldIndex: any) =>
      goldIndex.time.toString() == localTimestamp.toString() &&
      goldIndex.value.toString() == localValue.toString();

    // find lockedGold index where timestamps are equal

    lockedGoldIndex = lockedPendingWithdrawals.findIndex(goldIndexPredicate);
    if (lockedGoldIndex === -1) {
      throw "No matching pending withdrawal. Locked Gold index not found.";
    }

    return { localIndex, lockedGoldIndex };
  } catch (error) {
    throw error;
  }
}
