import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { Contract } from "ethers";

export async function finishPendingWithdrawals(
  hre: HardhatRuntimeEnvironment,
  beneficiaryAddress: string
) {
  try {
    const accountContract = await hre.ethers.getContract("Account");
    const numberOfPendingWithdrawals = await accountContract.getNumberPendingWithdrawals(
      beneficiaryAddress
    );
    const lockedGoldWrapper = await hre.kit.contracts.getLockedGold();

    console.log(chalk.red("number of pending withdrawal:"), numberOfPendingWithdrawals.toString());

    for (var i = 0; i < numberOfPendingWithdrawals; i++) {
      const { localIndex, lockedGoldIndex } = await getPendingWithdrawalIndexesAndValidate(
        accountContract,
        lockedGoldWrapper,
        beneficiaryAddress
      );

      console.log(chalk.green(`beneficiary: ${beneficiaryAddress}, index: ${i}`));
      console.log(chalk.green(`localPendingWithdrawalIndex: ${localIndex}`));
      console.log(chalk.green(`lockedGoldPendingWithdrawalIndex: ${lockedGoldIndex}`));

      const tx = await accountContract.finishPendingWithdrawal(
        beneficiaryAddress,
        localIndex,
        lockedGoldIndex
      );
      const receipt = await tx.wait();

      console.log("receipt:", receipt);
    }
  } catch (error) {
    throw error;
  }
}

async function getPendingWithdrawalIndexesAndValidate(
  accountContract: Contract,
  lockedGoldWrapper: LockedGoldWrapper,
  beneficiary: string
) {
  try {
    const localIndexPredicate = (timestamp: any) => {
      return timestamp.toNumber() < Date.now() / 1000;
    };
    const goldindexPredicate = (goldIndex: any) =>
      goldIndex.time.toString() == localTimestamp.toString();

    // get pending withdrawals
    const localPendingWithdrawals = await accountContract.getPendingWithdrawals(beneficiary);
    const lockedPendingWithdrawals = await lockedGoldWrapper.getPendingWithdrawals(
      accountContract.address
    );

    if (localPendingWithdrawals[0].length != localPendingWithdrawals[1].length) {
      throw new Error("mismatched list");
    }

    const localTimestampList: [] = localPendingWithdrawals[1];

    // find index for released funds
    const localIndex = localTimestampList.findIndex(localIndexPredicate);
    const localValue = localPendingWithdrawals[0][localIndex];
    const localTimestamp = localPendingWithdrawals[1][localIndex];

    // find lockedGold index where timestamps are equal

    var lockedGoldIndex = lockedPendingWithdrawals.findIndex(goldindexPredicate);

    // verify that values of at both indexes are equal.
    if (lockedPendingWithdrawals[lockedGoldIndex].value.toString() !== localValue.toString()) {
      console.log(chalk.red("values at indexes are not equal."));
    }

    return { localIndex, lockedGoldIndex };
  } catch (error) {
    throw error;
  }
}
