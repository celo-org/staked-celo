import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { BigNumber, Contract, Signer } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { taskLogger } from "../../logger";
import { getDefaultGroupsHHTask, getSpecificGroupsHHTask } from "../../task-utils";

const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

export async function withdraw(
  hre: HardhatRuntimeEnvironment,
  signer: Signer,
  beneficiaryAddress: string
) {
  const electionWrapper = await hre.kit.contracts.getElection();
  const accountContract = await hre.ethers.getContract("Account");
  const specificGroupStrategy = await hre.ethers.getContract("SpecificGroupStrategy");
  const defaultStrategy = await hre.ethers.getContract("DefaultStrategy");

  // Use active groups to get the full list of groups with potential withdrawals.
  const activeGroups = await getDefaultGroupsHHTask(defaultStrategy);
  const specificStrategies = await getSpecificGroupsHHTask(specificGroupStrategy);
  const groupList = new Set(activeGroups.concat(specificStrategies)).values();
  taskLogger.debug("DEBUG: groupList:", groupList);

  for (const group of groupList) {
    taskLogger.debug("DEBUG: Current group", group);

    // check what the beneficiary withdrawal amount is for each group.
    const scheduledWithdrawalAmount: BigNumber =
      await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(group, beneficiaryAddress);

    taskLogger.debug(
      `DEBUG: Scheduled withdrawal amount from group: ${scheduledWithdrawalAmount.toString()}. Beneficiary: ${beneficiaryAddress}, group: ${group} `
    );

    if (scheduledWithdrawalAmount.gt(0)) {
      let remainingRevokeAmount: BigNumber = BigNumber.from(0);
      let toRevokeFromPending: BigNumber = BigNumber.from(0);

      let lesserAfterPendingRevoke: string = ADDRESS_ZERO;
      let greaterAfterPendingRevoke: string = ADDRESS_ZERO;
      let lesserAfterActiveRevoke: string = ADDRESS_ZERO;
      let greaterAfterActiveRevoke: string = ADDRESS_ZERO;

      // substract the immediateWithdrawalAmount from scheduledWithdrawalAmount to get the revokable amount
      const immediateWithdrawalAmount: BigNumber = await accountContract.scheduledVotesForGroup(
        group
      );

      taskLogger.debug("DEBUG: ImmediateWithdrawalAmount:", immediateWithdrawalAmount.toString());

      if (immediateWithdrawalAmount.lt(scheduledWithdrawalAmount)) {
        remainingRevokeAmount = scheduledWithdrawalAmount.sub(immediateWithdrawalAmount);

        taskLogger.debug("remainingRevokeAmount:", remainingRevokeAmount.toString());

        // get AccountContract pending votes for group.
        const groupVote = await electionWrapper.getVotesForGroupByAccount(
          accountContract.address,
          group
        );
        const pendingVotes = groupVote.pending;

        taskLogger.debug("pendingVotes:", pendingVotes.toString());

        // amount to revoke from pending
        toRevokeFromPending = BigNumber.from(
          remainingRevokeAmount.lt(BigNumber.from(pendingVotes.toString())) // Math.min
            ? remainingRevokeAmount.toString()
            : pendingVotes.toString()
        );

        taskLogger.debug("toRevokeFromPending:", toRevokeFromPending.toString());

        // find lesser and greater for pending votes
        const lesserAndGreaterAfterPendingRevoke =
          await electionWrapper.findLesserAndGreaterAfterVote(
            group,
            // @ts-ignore: BigNumber types library conflict.
            toRevokeFromPending.mul(-1).toString()
          );
        lesserAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.lesser;
        greaterAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.greater;

        // Given that validators are sorted by total votes and that revoking pending votes happen before active votes.
        // One must account for any pending votes that would get removed from the total votes when revoking active votes
        // in the same transaction.

        // find lesser and greater for active votes
        const lesserAndGreaterAfterActiveRevoke =
          await electionWrapper.findLesserAndGreaterAfterVote(
            group,
            // @ts-ignore: BigNumber types library conflict.
            remainingRevokeAmount.mul(-1).toString()
          );
        lesserAfterActiveRevoke = lesserAndGreaterAfterActiveRevoke.lesser;
        greaterAfterActiveRevoke = lesserAndGreaterAfterActiveRevoke.greater;
      }

      // find index of group
      const index = await findAddressIndex(electionWrapper, group, accountContract.address);

      // use current index
      taskLogger.debug("beneficiaryAddress:", beneficiaryAddress);
      taskLogger.debug("group:", group);
      taskLogger.debug("lesserAfterPendingRevoke:", lesserAfterPendingRevoke);
      taskLogger.debug("greaterAfterPendingRevoke:", greaterAfterPendingRevoke);
      taskLogger.debug("lesserAfterActiveRevoke:", lesserAfterActiveRevoke);
      taskLogger.debug("greaterAfterActiveRevoke:", greaterAfterActiveRevoke);
      taskLogger.debug("group index:", index);

      const tx = await accountContract
        .connect(signer)
        .withdraw(
          beneficiaryAddress,
          group,
          lesserAfterPendingRevoke,
          greaterAfterPendingRevoke,
          lesserAfterActiveRevoke,
          greaterAfterActiveRevoke,
          index
        );

      const receipt = await tx.wait();

      taskLogger.debug("receipt status", receipt.status);
    }
  }
}

// find index of group in list
async function findAddressIndex(
  electionWrapper: ElectionWrapper,
  group: string,
  account: string
): Promise<number> {
  const list = await electionWrapper.getGroupsVotedForByAccount(account);
  return list.indexOf(group);
}

export async function getDefaultGroupsSafe(
  defaultStrategy: Contract
) : Promise<string[]> {
  const activeGroupsLengthPromise = defaultStrategy.getNumberOfGroups();
  let [key] = await defaultStrategy.getGroupsHead();

  const activeGroups = [];

  for (let i = 0; i < (await activeGroupsLengthPromise).toNumber(); i++) {
    activeGroups.push(key);
    [key] = await defaultStrategy.getGroupPreviousAndNext(key);
  }

  return activeGroups
}

export async function getSpecificGroupsSafe(specificGroupStrategy: Contract): Promise<string[]> {
  const getSpecificGroupStrategiesLength = specificGroupStrategy.getNumberOfStrategies();
  const specificGroupsPromises = [];

  for (let i = 0; i < (await getSpecificGroupStrategiesLength).toNumber(); i++) {
    specificGroupsPromises.push(specificGroupStrategy.getStrategy(i));
  }

  return Promise.all(specificGroupsPromises);
}
