import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { BigNumber } from "ethers";

export async function withdraw(hre: HardhatRuntimeEnvironment, beneficiaryAddress: string) {
  try {
    const electionWrapper = await hre.kit.contracts.getElection();
    const accountContract = await hre.ethers.getContract("Account");
    const managerContract = await hre.ethers.getContract("Manager");

    // Use deprecated and active groups to get the full list of groups with potential withdrawals.
    const deprecatedGroups: [] = await managerContract.getDeprecatedGroups();
    const activeGroups: [] = await managerContract.getGroups();
    const groupList = deprecatedGroups.concat(activeGroups);
    console.log("DEBUG: groupList:", groupList);

    for (var group of groupList) {
      console.log(chalk.yellow("DEBUG: Current group", group));

      // check what the beneficiary withdrawal amount is for each group.
      const scheduledWithdrawalAmount: BigNumber =
        await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(group, beneficiaryAddress);

      console.log(
        chalk.green(`DEBUG: Scheduled withdrawal amount from group: ${scheduledWithdrawalAmount}`)
      );

      if (scheduledWithdrawalAmount.gt(0)) {
        // substract the immediateWithdrawalAmount from scheduledWithdrawalAmount to get the revokable amount
        const immediateWithdrawalAmount: BigNumber = await accountContract.scheduledVotesForGroup(
          group
        );
        console.log("DEBUG: ImmediateWithdrawalAmount:", immediateWithdrawalAmount);

        let remainingRevokeAmount;
        if (immediateWithdrawalAmount.gt(scheduledWithdrawalAmount)) {
          remainingRevokeAmount = BigNumber.from(0);
          console.log(`DEBUG: setting remainingRevokeAmount to: ${remainingRevokeAmount}`);
        } else {
          remainingRevokeAmount = scheduledWithdrawalAmount.sub(immediateWithdrawalAmount);
        }

        // const revokeAmount = scheduledWithdrawalAmount - immediateWithdrawalAmount;
        console.log("remainingRevokeAmount:", remainingRevokeAmount);

        // get AccountContract pending votes for group.
        const groupVote = await electionWrapper.getVotesForGroupByAccount(
          accountContract.address,
          group
        );
        const pendingVotes = groupVote.pending;

        console.log("pendingVotes:", pendingVotes);

        // amount to revoke from pending
        const toRevokeFromPending: BigNumber = BigNumber.from(
          Math.min(remainingRevokeAmount.toNumber(), pendingVotes.toNumber())
        );

        console.log("toRevokeFromPending:", toRevokeFromPending);

        // find lesser and greater for pending votes

        const lesserAndGreaterAfterPendingRevoke =
          await electionWrapper.findLesserAndGreaterAfterVote(
            group,
            // @ts-ignore: BigNumber types library conflict.
            toRevokeFromPending.mul(-1).toString()
          );
        const lesserAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.lesser;
        const greaterAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.greater;

        /// Given that validators are sorted by total votes and that revoking pending votes happen before active votes.
        /// One must acccount for any pending votes that would get removed from the total votes when revoking active votes
        /// in the same transaction.
        const toRevokeFromActive = remainingRevokeAmount;

        console.log("toRevokeFromActive:", toRevokeFromActive);

        // find lesser and greater for active votes
        const lesserAndGreaterAfterActiveRevoke =
          await electionWrapper.findLesserAndGreaterAfterVote(
            group,
            // @ts-ignore: BigNumber types library conflict.
            toRevokeFromActive.mul(-1).toString()
          );
        const lesserAfterActiveRevoke = lesserAndGreaterAfterActiveRevoke.lesser;
        const greaterAfterActiveRevoke = lesserAndGreaterAfterActiveRevoke.greater;

        // // find index of group
        const index = await findAddressIndex(electionWrapper, group, accountContract.address);

        // use current index
        console.log("beneficiaryAddress:", beneficiaryAddress);
        console.log("group:", group);
        console.log("lesserAfterPendingRevoke:", lesserAfterPendingRevoke);
        console.log("greaterAfterPendingRevoke:", greaterAfterPendingRevoke);
        console.log("lesserAfterActiveRevoke:", lesserAfterActiveRevoke);
        console.log("greaterAfterActiveRevoke:", greaterAfterActiveRevoke);
        console.log("index:", index);

        const tx = await accountContract.withdraw(
          beneficiaryAddress,
          group,
          lesserAfterPendingRevoke,
          greaterAfterPendingRevoke,
          lesserAfterActiveRevoke,
          greaterAfterActiveRevoke,
          index
        );

        const receipt = await tx.wait();

        console.log(receipt);
      }
    }
  } catch (error) {
    throw error;
  }
}

// find index of group in list
async function findAddressIndex(
  electionWrapper: ElectionWrapper,
  group: string,
  account: string
): Promise<number> {
  try {
    const list = await electionWrapper.getGroupsVotedForByAccount(account);
    return list.indexOf(group);
  } catch (error) {
    throw error;
  }
}
