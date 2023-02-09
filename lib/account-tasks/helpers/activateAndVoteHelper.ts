import { Contract, Signer } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { taskLogger } from "../../logger";

export async function activateAndVote(hre: HardhatRuntimeEnvironment, signer: Signer) {
  const accountContract = await hre.ethers.getContract("Account");
  const specificGroupStrategy = await hre.ethers.getContract("SpecificGroupStrategy");
  const defaultStrategy = await hre.ethers.getContract("DefaultStrategy");

  const electionWrapper = await hre.kit.contracts.getElection();
  const electionContract = await hre.ethers.getContractAt("IElection", electionWrapper.address);

  const activeGroups = await getDefaultGroupsSafe(defaultStrategy)
  const specificStrategies = await getSpecificGroupsSafe(specificGroupStrategy)
  const groupList = new Set<string>(activeGroups.concat(specificStrategies)).values();
  taskLogger.debug("groups:", groupList);
  
  for (const group of groupList) {
    // Using election contract to make this `hasActivatablePendingVotes` call.
    // This allows to check activatable pending votes for a specified group,
    // as opposed to using the `ElectionWrapper.hasActivatablePendingVotes`
    // which checks if account has activatable pending votes from any group.
    const canActivateForGroup = await electionContract.hasActivatablePendingVotes(
      accountContract.address,
      group
    );
    const amountScheduled = await accountContract.scheduledVotesForGroup(group);

    taskLogger.debug("current group:", group);
    taskLogger.debug("can activate for group:", canActivateForGroup);
    taskLogger.debug("amount scheduled for group:", amountScheduled.toString());

    if (amountScheduled > hre.ethers.BigNumber.from(0) || canActivateForGroup) {
      const { lesser, greater } = await electionWrapper.findLesserAndGreaterAfterVote(
        group,
        amountScheduled.toString()
      );

      taskLogger.debug("lesser:", lesser);

      taskLogger.debug("greater:", greater);

      const tx = await accountContract.connect(signer).activateAndVote(group, lesser, greater);

      const receipt = await tx.wait();

      taskLogger.debug("receipt status", receipt.status);
    }
  }
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
