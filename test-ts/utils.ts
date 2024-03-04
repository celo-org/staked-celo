import { AccountsWrapper } from "@celo/contractkit/lib/wrappers/Accounts";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { default as BigNumberJs } from "bignumber.js";
import { BigNumber as EthersBigNumber, Contract, Wallet } from "ethers";
import { formatEther, parseUnits } from "ethers/lib/utils";
import hre, { ethers } from "hardhat";
import Web3 from "web3";
import {
  ACCOUNT_ACTIVATE_AND_VOTE,
  ACCOUNT_REVOKE,
  MULTISIG_EXECUTE_PROPOSAL,
  MULTISIG_SUBMIT_PROPOSAL,
} from "../lib/tasksNames";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { MockGroupHealth__factory } from "../typechain-types/factories/MockGroupHealth__factory";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { MockAccount } from "../typechain-types/MockAccount";
import { MockDefaultStrategy } from "../typechain-types/MockDefaultStrategy";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import electionContractData from "./code/abi/electionAbi.json";
import {
  DefaultGroupContract,
  ExpectVsReal,
  OrderedGroup,
  RebalanceContract,
} from "./utils-interfaces";

export const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";
export const REGISTRY_ADDRESS = "0x000000000000000000000000000000000000ce10";

// This is hardcoded into ganache
export const BLOCKS_PER_EPOCH = 100;

export const MIN_VALIDATOR_LOCKED_CELO = Web3.utils.toWei("10000", "ether");
const HOUR = 60 * 60;
export const DAY = 24 * HOUR;
export const LOCKED_GOLD_UNLOCKING_PERIOD = 3 * DAY;

// ---- Account utils ----

export function randomAddress(): string {
  return ethers.Wallet.createRandom().address;
}

type SignerWithAddressAndWallet = [SignerWithAddress, Wallet];

export async function randomSigner(
  initialBalance: EthersBigNumber = EthersBigNumber.from("0")
): Promise<SignerWithAddressAndWallet> {
  const wallet = ethers.Wallet.createRandom();

  if (initialBalance) {
    await setBalance(wallet.address, initialBalance);
  }
  await impersonateAccount(wallet.address);
  const signerWithAddress = await ethers.getSigner(wallet.address);
  return [signerWithAddress, wallet];
}

export async function getImpersonatedSigner(address: string, initialBalance?: EthersBigNumber) {
  await impersonateAccount(address);
  const signerWithAddress = await ethers.getSigner(address);
  if (initialBalance) {
    await setBalance(address, initialBalance);
  }
  return signerWithAddress;
}

// Some function are finicky about whether they allow the input hex string to
// start with 0x0... This function strips that first zero after 0x so the first
// hex digit is non-0.
function stripLeadingZero(hex: string): string {
  if (hex[2] === "0") {
    return "0x" + hex.slice(3);
  } else {
    return hex;
  }
}

export async function setBalance(address: string, balance: EthersBigNumber) {
  await hre.network.provider.send("hardhat_setBalance", [
    address,
    stripLeadingZero(balance.toHexString()),
  ]);
}

export async function impersonateAccount(address: string) {
  await hre.network.provider.send("hardhat_impersonateAccount", [address]);
}

// ----- Epoch utils -----

export async function mineToNextEpoch(web3: Web3, epochSize: number = BLOCKS_PER_EPOCH) {
  const blockNumber = await web3.eth.getBlockNumber();
  const epochNumber = await currentEpochNumber(web3, epochSize);
  const blocksUntilNextEpoch =
    getFirstBlockNumberForEpoch(epochNumber + 1, epochSize) - blockNumber;
  await mineBlocks(blocksUntilNextEpoch);
}

export async function currentEpochNumber(web3: Web3, epochSize: number = BLOCKS_PER_EPOCH) {
  const blockNumber = await web3.eth.getBlockNumber();

  return getEpochNumberOfBlock(blockNumber, epochSize);
}

export function getEpochNumberOfBlock(blockNumber: number, epochSize: number = BLOCKS_PER_EPOCH) {
  // Follows GetEpochNumber from celo-blockchain/blob/master/consensus/istanbul/utils.go
  const epochNumber = Math.floor(blockNumber / epochSize);
  if (blockNumber % epochSize === 0) {
    return epochNumber;
  } else {
    return epochNumber + 1;
  }
}

// Follows GetEpochFirstBlockNumber from celo-blockchain/blob/master/consensus/istanbul/utils.go
export function getFirstBlockNumberForEpoch(
  epochNumber: number,
  epochSize: number = BLOCKS_PER_EPOCH
) {
  if (epochNumber === 0) {
    // No first block for epoch 0
    return 0;
  }
  return (epochNumber - 1) * epochSize + 1;
}

// `useGanache` allows for mining block directly on the ganache network
export async function mineBlocks(blocks: number, useGanache?: boolean) {
  // TODO: add type back once we update to latest hardhat
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let localProvider: any;
  if (useGanache) {
    localProvider = new ethers.providers.JsonRpcProvider("http://localhost:7545");
  } else {
    localProvider = ethers.provider;
  }

  for (let i = 0; i < blocks; i++) {
    await localProvider.send("evm_mine", []);
  }
}

export async function timeTravel(seconds: number) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

// items stored in the LinkedList.List have extra zeros appended to them
// we are forced to convert to the regular 42 characters ethereum address
// e.g 0xf684493ae197ceb94dbf2fe0dd004e9480badf1e000000000000000000000000
// becomes 0xf684493ae197ceb94dbf2fe0dd004e9480badf1e
export function toAddress(address: string) {
  return address.substring(0, 42);
}

export async function resetNetwork() {
  await hre.network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: "http://localhost:7545",
          blockNumber: 399,
        },
      },
    ],
  });
}

export async function distributeEpochRewards(group: string, amount: string) {
  const electionWrapper = await hre.kit.contracts.getElection();
  const electionContract = electionWrapper["contract"];

  await impersonateAccount(ADDRESS_ZERO);

  const { lesser, greater } = await electionWrapper.findLesserAndGreaterAfterVote(
    group,
    // @ts-ignore: BigNumber types library conflict.
    amount
  );

  await electionContract.methods.distributeEpochRewards(group, amount, lesser, greater).send({
    from: ADDRESS_ZERO,
  });
}

export async function submitAndExecuteProposal(
  account: string,
  destinations: string[],
  values: string[],
  payloads: string[],
  timeTravelBeforeExecuting = 5
) {
  const proposalId = await hre.run(MULTISIG_SUBMIT_PROPOSAL, {
    destinations: destinations.join(","),
    values: values.join(","),
    payloads: payloads.join(","),
    account: account,
    useNodeAccount: true,
  });

  try {
    await timeTravel(timeTravelBeforeExecuting);
    await hre.run(MULTISIG_EXECUTE_PROPOSAL, {
      proposalId: proposalId,
      account: account,
      useNodeAccount: true,
    });
  } catch (error) {
    throw new Error(`execute proposal failed ${JSON.stringify(error)}`);
  }
}

export async function waitForEvent(
  contract: Contract,
  eventName: string,
  expectedValue: string,
  timeout = 10000
) {
  await new Promise<void>((resolve, reject) => {
    setTimeout(() => {
      reject(
        `Event ${eventName} with expectedValue: ${expectedValue} wasn't emitted in timely manner.`
      );
    }, timeout);
    contract.on(eventName, (implementation) => {
      if (implementation == expectedValue) {
        resolve();
      }
    });
  });
}

export async function activateAndVoteTest(deployerAccountName = "deployer") {
  try {
    await hre.run(ACCOUNT_ACTIVATE_AND_VOTE, {
      account: deployerAccountName,
      useNodeAccount: true,
    });
  } catch (error) {
    throw Error(`Activate and vote failed! ${JSON.stringify(error)}`);
  }
}

export async function revokeTest(deployerAccountName = "deployer") {
  try {
    await hre.run(ACCOUNT_REVOKE, {
      account: deployerAccountName,
      useNodeAccount: true,
    });
  } catch (error) {
    throw Error(`Revoke failed! ${JSON.stringify(error)}`);
  }
}

export async function setGovernanceConcurrentProposals(count: number) {
  const governanceWrapper = await hre.kit.contracts.getGovernance();
  const governanceContract = governanceWrapper["contract"];

  const governanceOwner = await (await governanceContract.methods.owner()).call();
  const setConcurrentProposalsTx = await governanceContract.methods.setConcurrentProposals(count);
  await impersonateAccount(governanceOwner);
  await setConcurrentProposalsTx.send({
    from: governanceOwner,
  });
}

export async function getDefaultGroups(defaultStrategy: DefaultGroupContract): Promise<string[]> {
  const activeGroupsLengthPromise = defaultStrategy.getNumberOfGroups();
  let [key] = await defaultStrategy.getGroupsHead();

  const activeGroups = [];

  for (let i = 0; i < (await activeGroupsLengthPromise).toNumber(); i++) {
    activeGroups.push(key);
    [key] = await defaultStrategy.getGroupPreviousAndNext(key);
  }

  return activeGroups;
}

export async function getSpecificGroups(
  specificGroupStrategy: SpecificGroupStrategy
): Promise<string[]> {
  const getSpecificGroupStrategiesLength = specificGroupStrategy.getNumberOfVotedGroups();
  const specificGroupsPromises = [];

  for (let i = 0; i < (await getSpecificGroupStrategiesLength).toNumber(); i++) {
    specificGroupsPromises.push(specificGroupStrategy.getVotedGroup(i));
  }

  return Promise.all(specificGroupsPromises);
}

export async function getGroupsOfAllStrategies(
  defaultStrategy: DefaultStrategy,
  specificGroupStrategy: SpecificGroupStrategy
) {
  const activeGroups = getDefaultGroups(defaultStrategy);
  const specificGroupsPromise = getSpecificGroups(specificGroupStrategy);

  const allGroups = await Promise.all([activeGroups, specificGroupsPromise]);
  const allGroupsSet = new Set([...allGroups[0], ...allGroups[1]]);

  return [...allGroupsSet];
}

export async function getBlockedSpecificGroupStrategies(
  specificGroupStrategy: SpecificGroupStrategy
) {
  const blockedStrategiesLength = await specificGroupStrategy.getNumberOfBlockedGroups();
  const promises: Promise<string>[] = [];
  for (let i = 0; i < blockedStrategiesLength.toNumber(); i++) {
    promises.push(specificGroupStrategy.getBlockedGroup(i));
  }

  return await Promise.all(promises);
}

export async function getRealVsExpectedCeloForGroups(managerContract: Manager, groups: string[]) {
  const expectedVsRealPromises = groups.map(async (group) => {
    const expectedVsReal = await managerContract.getExpectedAndActualCeloForGroup(group);
    return {
      group,
      expected: expectedVsReal[0],
      real: expectedVsReal[1],
      diff: expectedVsReal[1].sub(expectedVsReal[0]),
    };
  });

  return await Promise.all(expectedVsRealPromises);
}

export async function getRealVsExpectedStCeloForGroupsDefaultStrategy(
  defaultStrategyContract: DefaultStrategy,
  groups: string[]
) {
  const expectedVsRealPromises = groups.map(async (group) => {
    const expectedVsReal = await defaultStrategyContract.getExpectedAndActualStCeloForGroup(group);
    return {
      group,
      expected: expectedVsReal[0],
      real: expectedVsReal[1],
      diff: expectedVsReal[1].sub(expectedVsReal[0]),
    };
  });

  return await Promise.all(expectedVsRealPromises);
}

export async function rebalanceDefaultGroups(defaultStrategy: DefaultStrategy) {
  const activeGroups = await getDefaultGroups(defaultStrategy);
  const expectedVsReal = await getRealVsExpectedStCeloForGroupsDefaultStrategy(
    defaultStrategy,
    activeGroups
  );

  await rebalanceInternal(defaultStrategy, expectedVsReal);
}

async function rebalanceInternal(
  rebalanceContract: RebalanceContract,
  expectedVsReal: ExpectVsReal[]
) {
  const unbalanced = expectedVsReal.filter((k) => k.diff.abs().gt(0));
  if (unbalanced.length == 0) {
    return;
  }

  const sortedUnbalancedDesc = unbalanced.sort((a, b) => (a.diff.lt(b.diff) ? 1 : -1));

  let firstIndex = 0;
  let lastIndex = sortedUnbalancedDesc.length - 1;

  while (firstIndex < lastIndex) {
    await rebalanceContract.rebalance(
      sortedUnbalancedDesc[firstIndex].group,
      sortedUnbalancedDesc[lastIndex].group
    );

    const sumDiff = sortedUnbalancedDesc[firstIndex].diff.add(sortedUnbalancedDesc[lastIndex].diff);

    if (sumDiff.lt(0)) {
      sortedUnbalancedDesc[lastIndex].diff = sumDiff;
      firstIndex++;
    } else if (sumDiff.gt(0)) {
      sortedUnbalancedDesc[firstIndex].diff = sumDiff;
      lastIndex--;
    } else {
      sortedUnbalancedDesc[firstIndex].diff = sortedUnbalancedDesc[lastIndex].diff =
        EthersBigNumber.from(0);
      firstIndex++;
      lastIndex--;
    }
  }
}

export async function rebalanceGroups(
  managerContract: Manager,
  specificGroupStrategy: SpecificGroupStrategy,
  defaultStrategy: DefaultStrategy
) {
  const allGroups = await getGroupsOfAllStrategies(defaultStrategy, specificGroupStrategy);
  const expectedVsReal = await getRealVsExpectedCeloForGroups(managerContract, allGroups);

  await rebalanceInternal(managerContract, expectedVsReal);
}

export async function revokeElectionOnMockValidatorGroupsAndUpdate(
  validators: ValidatorsWrapper,
  accounts: AccountsWrapper,
  groupHealthContract: MockGroupHealth,
  validatorGroups: string[],
  update = true
) {
  const allValidatorsInValGroup = await Promise.all(
    validatorGroups.map(async (vg) => {
      const valGroup = await validators.getValidatorGroup(vg);

      return await Promise.all(
        valGroup.members.map(async (member) => accounts.getValidatorSigner(member))
      );
    })
  );

  const flattened = allValidatorsInValGroup.flat();
  const valGroupsSet = new Set(flattened);
  for (let i = 0; i < (await groupHealthContract.numberOfValidators()).toNumber(); i++) {
    const electedValidator = await groupHealthContract.electedValidators(i);
    if (valGroupsSet.has(electedValidator)) {
      await groupHealthContract.setElectedValidator(i, ADDRESS_ZERO);
    }
  }
  if (!update) {
    return;
  }

  for (let j = 0; j < validatorGroups.length; j++) {
    await groupHealthContract.updateGroupHealth(validatorGroups[j]);
  }
}

// Since Ganache doesn't support Celo pre-compiles we need to mock some methods to be able to use GroupHealth in e2e tests
export async function upgradeToMockGroupHealthE2E(
  multisigOwner: SignerWithAddress,
  groupHealthContract: GroupHealth
) {
  const mockGroupHealthFactory: MockGroupHealth__factory = (
    await hre.ethers.getContractFactory("MockGroupHealth")
  ).connect(multisigOwner) as MockGroupHealth__factory;
  const mockGroupHealth = await mockGroupHealthFactory.deploy();

  await submitAndExecuteProposal(
    multisigOwner.address,
    [groupHealthContract.address],
    ["0"],
    [groupHealthContract.interface.encodeFunctionData("upgradeTo", [mockGroupHealth.address])]
  );

  return mockGroupHealthFactory.attach(groupHealthContract.address);
}

export async function getIndexesOfElectedValidatorGroupMembers(
  election: ElectionWrapper,
  validators: ValidatorsWrapper,
  validatorGroup: string
) {
  const validatorGroupDetail = await validators.getValidatorGroup(validatorGroup);
  const currentValidatorSigners = await election.getCurrentValidatorSigners();
  const finalIndexes: number[] = [];
  for (const member of validatorGroupDetail.members) {
    const index = currentValidatorSigners.indexOf(member);
    finalIndexes.push(index === -1 ? currentValidatorSigners.length : index);
  }
  return finalIndexes;
}

export async function getOrderedActiveGroups(
  defaultStrategyContract: MockDefaultStrategy,
  account?: Account
): Promise<OrderedGroup[]> {
  let [head] = await defaultStrategyContract.getGroupsHead();
  const groupsForLog = [];

  for (let i = 0; i < (await defaultStrategyContract.getNumberOfGroups()).toNumber(); i++) {
    const [prev] = await defaultStrategyContract.getGroupPreviousAndNext(head);
    const stCelo = await defaultStrategyContract.stCeloInGroup(head);
    const realCelo = await account?.getCeloForGroup(head);
    groupsForLog.unshift({
      group: head,
      stCelo: formatEther(stCelo),
      realCelo: formatEther(realCelo ?? 0),
    });
    head = prev;
  }
  return groupsForLog;
}

export async function getUnsortedGroups(defaultStrategyContract: MockDefaultStrategy) {
  const length = await defaultStrategyContract.getNumberOfUnsortedGroups();

  const unsortedGroupsPromises = [];

  for (let i = 0; i < length.toNumber(); i++) {
    unsortedGroupsPromises.push(defaultStrategyContract.getUnsortedGroupAt(i));
  }
  return await Promise.all(unsortedGroupsPromises);
}

export async function prepareOverflow(
  defaultStrategyContract: DefaultGroupContract,
  election: ElectionWrapper,
  lockedGold: LockedGoldWrapper,
  voter: SignerWithAddress,
  groupAddresses: string[],
  activateGroups = true
) {
  if (groupAddresses.length < 3) {
    throw Error("It is necessary to provide at least 3 groups");
  }
  // These numbers are derived from a system of linear equations such that
  // given 12 validators registered and elected, as above, we have the following
  // limits for the first three groups:
  // group[0] and group[2]: 95864 Locked CELO
  // group[1]: 143797 Locked CELO
  // and the remaining receivable votes are [40, 100, 200] (in CELO) for
  // the three groups, respectively.
  const votes = [parseUnits("95824"), parseUnits("143697"), parseUnits("95664")];

  for (let i = 2; i >= 0; i--) {
    const [head] = await defaultStrategyContract.getGroupsHead();
    if (activateGroups) {
      await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
    }

    await lockedGold.lock().sendAndWaitForReceipt({
      from: voter.address,
      value: votes[i].toString(),
    });
  }

  // We have to do this in a separate loop because the voting limits
  // depend on total locked CELO. The votes we want to cast are very close
  // to the final limit we'll arrive at, so we first lock all CELO, then
  // cast it as votes.
  for (let i = 0; i < 3; i++) {
    const voteTx = await election.vote(groupAddresses[i], new BigNumberJs(votes[i].toString()));
    await voteTx.sendAndWaitForReceipt({ from: voter.address });
  }
}

export async function updateMaxNumberOfGroups(
  accountAddress: string,
  election: ElectionWrapper,
  signerWithCelo: SignerWithAddress,
  updateValue: boolean
) {
  const sendFundsTx = await signerWithCelo.sendTransaction({
    value: parseUnits("1"),
    to: accountAddress,
  });
  await sendFundsTx.wait();
  await impersonateAccount(accountAddress);

  const accountsContract = await hre.kit.contracts.getAccounts();
  const createAccountTxObject = accountsContract.createAccount();
  await createAccountTxObject.send({
    from: accountAddress,
  });
  // TODO: once contractkit updated - use just election contract from contractkit
  const electionContract = new hre.kit.web3.eth.Contract(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    electionContractData.abi as any,
    election.address
  );
  const setAllowedToVoteOverMaxNumberOfGroupsTxObject =
    electionContract.methods.setAllowedToVoteOverMaxNumberOfGroups(updateValue);
  await setAllowedToVoteOverMaxNumberOfGroupsTxObject.send({
    from: accountAddress,
  });
}

export async function getDefaultGroupsWithStCelo(defaultStrategy: DefaultStrategy) {
  const activeGroups = await getDefaultGroups(defaultStrategy);
  return await Promise.all(
    activeGroups.map(async (ag) => {
      const stCelo = await defaultStrategy.stCeloInGroup(ag);
      return {
        group: ag,
        stCelo,
      };
    })
  );
}

export async function sortActiveGroups(defaultStrategy: DefaultStrategy) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const unsortedGroups = await getUnsortedGroups(defaultStrategy as any);
  let defaultGroupsWithStCelo = await getDefaultGroupsWithStCelo(defaultStrategy);
  const defaultGroupsWithStCeloRecord = defaultGroupsWithStCelo.reduce(
    (prev, current) => ({ ...prev, [current.group]: current.stCelo }),
    {} as Record<string, EthersBigNumber>
  );

  while (unsortedGroups.length > 0) {
    const uGroup = unsortedGroups.pop();
    let prev = ADDRESS_ZERO;
    let next = ADDRESS_ZERO;
    let i = 0;
    while (i++ < defaultGroupsWithStCelo.length) {
      prev = next;
      next = defaultGroupsWithStCelo?.[i]?.group ?? ADDRESS_ZERO;

      if (
        defaultGroupsWithStCelo[i] == null ||
        defaultGroupsWithStCelo[i].stCelo.gt(defaultGroupsWithStCeloRecord[uGroup!])
      ) {
        break;
      }

      if (defaultGroupsWithStCelo[i].group == uGroup) {
        next = defaultGroupsWithStCelo?.[i - 1].group ?? ADDRESS_ZERO;
        continue;
      }
    }
    await defaultStrategy.updateActiveGroupOrder(uGroup!, prev, next);
    defaultGroupsWithStCelo = await getDefaultGroupsWithStCelo(defaultStrategy);
  }
}

export async function updateGroupCeloBasedOnProtocolStCelo(
  defaultStrategy: MockDefaultStrategy,
  specificStrategy: SpecificGroupStrategy,
  account: MockAccount,
  manager: Manager
) {
  const defaultGroupsPromise = getDefaultGroups(defaultStrategy);
  const specificGroupsPromise = getSpecificGroups(specificStrategy);

  const defaultGroups = await defaultGroupsPromise;
  const specificGroups = await specificGroupsPromise;

  const defaultGroupsWithStCeloPromise = defaultGroups.map(async (g) => ({
    group: g,
    amount: await defaultStrategy.stCeloInGroup(g),
  }));

  const specificGroupsWithStCeloPromise = specificGroups.map(async (g) => {
    const [total, overflow, unhealthy] = await specificStrategy.getStCeloInGroup(g);
    return {
      group: g,
      amount: total.sub(overflow).sub(unhealthy),
    };
  });

  const defaultGroupsWithStCelo = await Promise.all(defaultGroupsWithStCeloPromise);
  const specificGroupsWithStCelo = await Promise.all(specificGroupsWithStCeloPromise);

  const groups: Record<string, EthersBigNumber> = {};

  for (let i = 0; i < defaultGroupsWithStCelo.length; i++) {
    groups[defaultGroupsWithStCelo[i].group] = defaultGroupsWithStCelo[i].amount;
  }

  for (let i = 0; i < specificGroupsWithStCelo.length; i++) {
    groups[specificGroupsWithStCelo[i].group] = (
      groups[specificGroupsWithStCelo[i].group] ?? EthersBigNumber.from(0)
    ).add(specificGroupsWithStCelo[i].amount);
  }

  await Promise.all(
    Object.keys(groups).map(async (key) => {
      const celoInGroup = await manager.toCelo(groups[key].toString());
      await account.setCeloForGroup(key, celoInGroup);
    })
  );
}
