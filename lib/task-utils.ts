import { Contract } from "ethers";

export async function getDefaultGroupsHHTask(defaultStrategy: Contract): Promise<string[]> {
  const activeGroupsLengthPromise = defaultStrategy.getNumberOfGroups();
  let [key] = await defaultStrategy.getGroupsHead();

  const activeGroups = [];

  for (let i = 0; i < (await activeGroupsLengthPromise).toNumber(); i++) {
    activeGroups.push(key);
    [key] = await defaultStrategy.getGroupPreviousAndNext(key);
  }

  return activeGroups;
}

export async function getSpecificGroupsHHTask(specificGroupStrategy: Contract): Promise<string[]> {
  const getSpecificGroupStrategiesLength = specificGroupStrategy.getNumberOfVotedGroups();
  const specificGroupsPromises = [];

  for (let i = 0; i < (await getSpecificGroupStrategiesLength).toNumber(); i++) {
    specificGroupsPromises.push(specificGroupStrategy.getVotedGroup(i));
  }

  return Promise.all(specificGroupsPromises);
}
