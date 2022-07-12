import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";

export async function withdraw(hre: HardhatRuntimeEnvironment, beneficiaryAddress: string) {
  try {
    const electionWrapper = await hre.kit.contracts.getElection();

    const accountContract = await hre.ethers.getContract("Account");
    const managerContract = await hre.ethers.getContract("Manager");

    // Use deprecated and active groups to get the full list of groups with potential withdrawals.
    const deprecatedGroups: [] = await managerContract.getDeprecatedGroups();
    const activeGroups: [] = await managerContract.getGroups();

    const groupList = deprecatedGroups.concat(activeGroups);
    console.log("groupList:", groupList);

    for (var group of groupList) {
      console.log(chalk.yellow("current group", group));

      // check what the beneficiary withdrawal amount is for each group.
      const scheduledWithdrawalAmount =
        await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(group, beneficiaryAddress);
      console.log(
        chalk.green("scheduled withdrawal amount from group:", scheduledWithdrawalAmount)
      );

      if (scheduledWithdrawalAmount > 0) {
        // substract the immediateWithdrawalAmount from scheduledWithdrawalAmount to get the revokable amount
        const immediateWithdrawalAmount = await accountContract.scheduledVotesForGroup(group);
        console.log("immediateWithdrawalAmount:", immediateWithdrawalAmount);

        const revokeAmount = scheduledWithdrawalAmount - immediateWithdrawalAmount;
        console.log("revokeAmount:", revokeAmount);

        // get AccountContract pending votes for group.
        const groupVote = await electionWrapper.getVotesForGroupByAccount(
          accountContract.address,
          group
        );
        const pendingVotes = groupVote.pending;

        console.log("pendingVotes:", pendingVotes);

        // amount to revoke from pending
        const toRevokeFromPending = Math.min(revokeAmount, pendingVotes.toNumber());

        console.log("toRevokeFromPending:", toRevokeFromPending);

        // find lesser and greater for pending votes
        // @ts-ignore
        const lesserAndGreaterAfterPendingRevoke =
          await electionWrapper.findLesserAndGreaterAfterVote(
            group,
            // @ts-ignore
            (toRevokeFromPending * -1).toString() //TODO: can you use Bignumber here?
          );
        const lesserAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.lesser;
        const greaterAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.greater;

        // find amount to revoke from active votes
        const toRevokeFromActive = revokeAmount - toRevokeFromPending;

        console.log("toRevokeFromActive:", toRevokeFromActive);

        // find lesser and greater for active votes
        // @ts-ignore
        const lesserAndGreaterAfterActiveRevoke =
          await electionWrapper.findLesserAndGreaterAfterVote(
            group,
            // @ts-ignore
            (toRevokeFromActive * -1).toString() //TODO: can you use Bignumber here?
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

        //TODO: uncomment these

        // const tx = await accountContract.withdraw(beneficiaryAddress, group, lesserAfterPendingRevoke, greaterAfterPendingRevoke, lesserAfterActiveRevoke, greaterAfterActiveRevoke, index);

        // const receipt = await tx.wait();

        // console.log(receipt)
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
