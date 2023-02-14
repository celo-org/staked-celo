import { CeloTxReceipt } from "@celo/connect";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { default as BigNumber, default as BigNumberJs } from "bignumber.js";
import { BigNumber as EthersBigNumber, Contract, Wallet } from "ethers";
import { formatEther, parseUnits } from "ethers/lib/utils";
import hre, { ethers, kit } from "hardhat";
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
import { MockDefaultStrategy } from "../typechain-types/MockDefaultStrategy";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { MockLockedGold } from "../typechain-types/MockLockedGold";
import { MockRegistry } from "../typechain-types/MockRegistry";
import { MockValidators } from "../typechain-types/MockValidators";
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

const MIN_VALIDATOR_LOCKED_CELO = Web3.utils.toWei("10000", "ether");
const HOUR = 60 * 60;
export const DAY = 24 * HOUR;
export const LOCKED_GOLD_UNLOCKING_PERIOD = 3 * DAY;

// ---- Validator utils ----

// Locks the required CELO and registers as a validator group.
export async function registerValidatorGroup(account: SignerWithAddress, members = 1) {
  const accounts = await kit.contracts.getAccounts();
  const tx = accounts.createAccount();
  await tx.sendAndWaitForReceipt({
    from: account.address,
  });

  const lockedGold = await kit.contracts.getLockedGold();

  // lock up the minimum of 10k per validator
  await lockedGold.lock().sendAndWaitForReceipt({
    from: account.address,
    value: EthersBigNumber.from(MIN_VALIDATOR_LOCKED_CELO).mul(members).toString(),
  });

  const validators = await kit.contracts.getValidators();

  await (
    await validators.registerValidatorGroup(new BigNumber("0"))
  ).sendAndWaitForReceipt({
    from: account.address,
  });
}

// Locks the required CELO and registers as a validator in the group `groupAddress`
export async function registerValidatorAndAddToGroupMembers(
  group: SignerWithAddress,
  validator: SignerWithAddress,
  validatorWallet: Wallet
) {
  await registerValidatorAndOnlyAffiliateToGroup(group, validator, validatorWallet);
  await addValidatorToGroupMembers(group, validator);
}

export async function registerValidatorAndOnlyAffiliateToGroup(
  group: SignerWithAddress,
  validator: SignerWithAddress,
  validatorWallet: Wallet
) {
  const accounts = await kit.contracts.getAccounts();

  await accounts.createAccount().sendAndWaitForReceipt({
    from: validator.address,
  });

  const lockedGold = await kit.contracts.getLockedGold();

  // lock up the 10k minimum
  await lockedGold.lock().sendAndWaitForReceipt({
    from: validator.address,
    value: MIN_VALIDATOR_LOCKED_CELO,
  });

  const validators = await kit.contracts.getValidators();

  // Validators.sol needs a 64 byte public key, the one stored in a Wallet is 65
  // bytes. The first byte is unnecessary, and we also want to strip the leading
  // 0x, so we `.slice(4)`.
  const publicKey = validatorWallet.publicKey.slice(4);
  // A random 64 byte hex string. Taken from the monorepo.
  const blsPublicKey =
    "0x4fa3f67fc913878b068d1fa1cdddc54913d3bf988dbe5a36a20fa888f20d4894c408a6773f3d7bde11154f2a3076b700d345a42fd25a0e5e83f4db5586ac7979ac2053cd95d8f2efd3e959571ceccaa743e02cf4be3f5d7aaddb0b06fc9aff00";
  const blsPoP =
    "0xcdb77255037eb68897cd487fdd85388cbda448f617f874449d4b11588b0b7ad8ddc20d9bb450b513bb35664ea3923900";

  await validators.registerValidator(publicKey, blsPublicKey, blsPoP).sendAndWaitForReceipt({
    from: validator.address,
  });

  // Affiliate validator with the group
  await validators.affiliate(group.address).sendAndWaitForReceipt({
    from: validator.address,
  });
}

export async function addValidatorToGroupMembers(
  group: SignerWithAddress,
  validator: SignerWithAddress
) {
  const validators = await kit.contracts.getValidators();
  const tx = await validators.addMember(group.address, validator.address);
  await tx.sendAndWaitForReceipt({
    from: group.address,
  });
}

export async function removeMembersFromGroup(group: SignerWithAddress) {
  // get validators contract
  const validators = await kit.contracts.getValidators();

  // get validator group
  const validatorGroup = await validators.getValidatorGroup(group.address);

  // deaffiliate then deregister
  const txs: Promise<CeloTxReceipt>[] = [];
  for (const validator of validatorGroup.members) {
    const tx = validators.removeMember(validator).sendAndWaitForReceipt({ from: group.address });
    txs.push(tx);
  }

  await Promise.all(txs);
}

export async function deregisterValidatorGroup(group: SignerWithAddress) {
  const validators = await kit.contracts.getValidators();
  await removeMembersFromGroup(group);
  const groupRequirementEndTime = await validators.getGroupLockedGoldRequirements();

  await timeTravel(groupRequirementEndTime.duration.toNumber() + 2 * DAY);

  await (
    await validators.deregisterValidatorGroup(group.address)
  ).sendAndWaitForReceipt({ from: group.address });
}

export async function activateValidators(
  defaultStrategyContract: DefaultStrategy,
  groupHealthContract: GroupHealth,
  multisigOwner: string,
  groupAddresses: string[]
) {
  let [nextGroup] = await defaultStrategyContract.getGroupsTail();
  for (let i = 0; i < groupAddresses.length; i++) {
    const isGroupValid = await groupHealthContract.isGroupValid(groupAddresses[i]);
    if (!isGroupValid) {
      throw new Error(`Group ${groupAddresses[i]} is not valid group!`);
    }
    await submitAndExecuteProposal(
      multisigOwner,
      [defaultStrategyContract.address],
      ["0"],
      [
        defaultStrategyContract.interface.encodeFunctionData("activateGroup", [
          groupAddresses[i],
          ADDRESS_ZERO,
          nextGroup,
        ]),
      ]
    );
    nextGroup = groupAddresses[i];
  }
}

export async function voteForGroup(groupAddress: string, voter: SignerWithAddress) {
  const lockedGold = await kit.contracts.getLockedGold();
  const election = await kit.contracts.getElection();
  await lockedGold.lock().sendAndWaitForReceipt({
    from: voter.address,
    value: parseUnits("1").toString(),
  });

  const voteTx = await election.vote(groupAddress, new BigNumberJs(parseUnits("1").toString()));
  await voteTx.sendAndWaitForReceipt({ from: voter.address });
}

export async function activateVotesForGroup(voter: SignerWithAddress) {
  const election = await kit.contracts.getElection();
  const activateTxs = await election.activate(voter.address);
  const txs: Promise<CeloTxReceipt>[] = [];
  for (let i = 0; i < activateTxs.length; i++) {
    const tx = activateTxs[i].sendAndWaitForReceipt({ from: voter.address });
    txs.push(tx);
  }
  await Promise.all(txs);
}

export async function electGroup(groupAddress: string, voter: SignerWithAddress) {
  await voteForGroup(groupAddress, voter);
  await mineToNextEpoch(kit.web3);
  await activateVotesForGroup(voter);
}

export async function updateGroupSlashingMultiplier(
  registryContract: MockRegistry,
  lockedGoldContract: MockLockedGold,
  validatorsContract: MockValidators,
  group: SignerWithAddress,
  mockSlasher: SignerWithAddress
) {
  const coreContractsOwnerAddr = await registryContract.owner();

  await impersonateAccount(coreContractsOwnerAddr);
  const coreContractsOwner = await hre.ethers.getSigner(coreContractsOwnerAddr);

  await registryContract
    .connect(coreContractsOwner)
    .setAddressFor("MockSlasher", mockSlasher.address);

  await lockedGoldContract.connect(coreContractsOwner).addSlasher("MockSlasher");
  await validatorsContract.connect(mockSlasher).halveSlashingMultiplier(group.address);

  await mineToNextEpoch(hre.web3);
}

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

async function setBalance(address: string, balance: EthersBigNumber) {
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
  payloads: string[]
) {
  const proposalId = await hre.run(MULTISIG_SUBMIT_PROPOSAL, {
    destinations: destinations.join(","),
    values: values.join(","),
    payloads: payloads.join(","),
    account: account,
    useNodeAccount: true,
  });

  try {
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

export async function getDefaultGroupsSafe(
  defaultStrategy: DefaultGroupContract
): Promise<string[]> {
  const activeGroupsLengthPromise = defaultStrategy.getNumberOfGroups();
  let [key] = await defaultStrategy.getGroupsHead();

  const activeGroups = [];

  for (let i = 0; i < (await activeGroupsLengthPromise).toNumber(); i++) {
    activeGroups.push(key);
    [key] = await defaultStrategy.getGroupPreviousAndNext(key);
  }

  return activeGroups;
}

export async function getSpecificGroupsSafe(
  specificGroupStrategy: SpecificGroupStrategy
): Promise<string[]> {
  const getSpecificGroupStrategiesLength = specificGroupStrategy.getNumberOfStrategies();
  const specificGroupsPromises = [];

  for (let i = 0; i < (await getSpecificGroupStrategiesLength).toNumber(); i++) {
    specificGroupsPromises.push(specificGroupStrategy.getStrategy(i));
  }

  return Promise.all(specificGroupsPromises);
}

export async function getGroupsOfAllStrategies(
  defaultStrategy: DefaultStrategy,
  specificGroupStrategy: SpecificGroupStrategy
) {
  const activeGroups = getDefaultGroupsSafe(defaultStrategy);
  const specificGroupsPromise = getSpecificGroupsSafe(specificGroupStrategy);

  const allGroups = await Promise.all([activeGroups, specificGroupsPromise]);
  const allGroupsSet = new Set([...allGroups[0], ...allGroups[1]]);

  return [...allGroupsSet];
}

export async function getBlockedSpecificGroupStrategies(
  specificGroupStrategy: SpecificGroupStrategy
) {
  const blockedStrategiesLength = await specificGroupStrategy.getNumberOfBlockedStrategies();
  const promises: Promise<string>[] = [];
  for (let i = 0; i < blockedStrategiesLength.toNumber(); i++) {
    promises.push(specificGroupStrategy.getBlockedStrategy(i));
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
  const activeGroups = await getDefaultGroupsSafe(defaultStrategy);
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

  rebalanceInternal(managerContract, expectedVsReal);
}

export async function electMockValidatorGroupsAndUpdate(
  validators: ValidatorsWrapper,
  groupHealthContract: MockGroupHealth,
  validatorGroups: string[],
  revoke = false,
  update = true
): Promise<number[]> {
  let validatorsProcessed = 0;
  const mockedIndexes: number[] = [];

  for (let j = 0; j < validatorGroups.length; j++) {
    const validatorGroup = validatorGroups[j];
    const isValidatorGroup = await validators.isValidatorGroup(validatorGroup);

    if (isValidatorGroup) {
      const validatorGroupDetail = await validators.getValidatorGroup(validatorGroup);
      for (let i = 0; i < validatorGroupDetail.members.length; i++) {
        const mockIndex = validatorsProcessed++;
        await groupHealthContract.setElectedValidator(
          mockIndex,
          revoke ? ADDRESS_ZERO : validatorGroupDetail.members[i]
        );
        mockedIndexes.push(mockIndex);
      }
    }
    if (update) {
      await groupHealthContract.updateGroupHealth(validatorGroup);
    }
  }
  return mockedIndexes;
}

export async function revokeElectionOnMockValidatorGroupsAndUpdate(
  validators: ValidatorsWrapper,
  groupHealthContract: MockGroupHealth,
  validatorGroups: string[]
) {
  const allValidatorsInValGroup = await Promise.all(
    validatorGroups.map(async (vg) => {
      const valGroup = await validators.getValidatorGroup(vg);
      return valGroup.members;
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
  console.log("unsorted groups length", length.toString());

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
  const activeGroups = await getDefaultGroupsSafe(defaultStrategy);
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
