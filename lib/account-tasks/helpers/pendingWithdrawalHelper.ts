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

    for (var i = 0; i < numberOfPendingWithdrawals; i++) {
      const { localIndex, lockedGoldIndex } = await getPendingWithdrawalIndexesAndValidate(
        accountContract,
        lockedGoldWrapper,
        beneficiaryAddress
      );

      console.log(chalk.green(`beneficiary: ${beneficiaryAddress}`));
      console.log(chalk.green(`localPendingWithdrawalIndex: ${localIndex}`));
      console.log(chalk.green(`lockedGoldPendingWithdrawalIndex: ${lockedGoldIndex}`));
      //TODO: uncomment below
      // const tx = await accountContract.finishPendingWithdrawal(beneficiaryAddress, localIndex, lockedGoldIndex);
      // const receipt = await tx.wait()

      // console.log("receipt:", receipt)
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
    const localIndex = 0;

    // get pending withdrawals
    const localIndexData = await accountContract.getPendingWithdrawals(beneficiary);
    const lockedPendingWithdrawals = await lockedGoldWrapper.getPendingWithdrawals(
      accountContract.address
    );

    if (localIndexData[0].length != localIndexData[1].length) {
      throw new Error("mismatched list");
    }

    const localValue = localIndexData[0][0];
    const localTimestamp = localIndexData[1][0];

    var t = new Date(1970, 0, 1);
    const localTimestampInSeconds = t.setSeconds(localTimestamp.toString());

    if (localTimestampInSeconds > Date.now()) {
      const remainingTime = localTimestampInSeconds - Date.now();
      throw new Error(
        `Cannot finalize withdraw at the moment. Wait your ${remainingTime} more seconds.`
      );
    }
    // find index where timestmps are equal
    const res = (goldIndex: any) => goldIndex.time.toString() == localTimestamp.toString();

    var lockedGoldIndex = lockedPendingWithdrawals.findIndex(res);

    // verify that values of at both indexes are equal.
    if (lockedPendingWithdrawals[lockedGoldIndex].value.toString() !== localValue.toString()) {
      console.log(chalk.red("values at indexes are not equal."));
    }

    return { localIndex, lockedGoldIndex };
  } catch (error) {
    throw error;
  }
}
