import { JsonRpcProvider } from "@ethersproject/providers";
import BigNumber from "bignumber.js";
import { Wallet, BigNumber as EthersBigNumber, Contract } from "ethers";
import Web3 from "web3";
import hre, { ethers, kit } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MULTISIG_EXECUTE_PROPOSAL, MULTISIG_SUBMIT_PROPOSAL } from "../lib/tasksNames";
import { Manager } from "../typechain-types/Manager";
import { CeloTxReceipt } from "@celo/connect";
import { parseUnits } from "ethers/lib/utils";
import BigNumberJs from "bignumber.js";
import { MockRegistry } from "../typechain-types/MockRegistry";
import { MockLockedGold } from "../typechain-types/MockLockedGold";
import { MockValidators } from "../typechain-types/MockValidators";

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
export async function registerValidatorGroup(account: SignerWithAddress, members: number = 1) {
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
  let txs: Promise<CeloTxReceipt>[] = [];
  for (let validator of validatorGroup.members) {
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
  managerContract: Manager,
  multisigOwner: string,
  groupAddresses: string[]
) {
  const payloads: string[] = [];
  const destinations: string[] = [];
  const values: string[] = [];

  for (let i = 0; i < 3; i++) {
    destinations.push(managerContract.address);
    values.push("0");
    payloads.push(
      managerContract.interface.encodeFunctionData("activateGroup", [groupAddresses[i]])
    );
  }
  await submitAndExecuteProposal(multisigOwner, destinations, values, payloads);
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

export async function electMinimumNumberOfValidators(
  groups: SignerWithAddress[],
  voter: SignerWithAddress
) {
  const election = await kit.contracts.getElection();
  const { min } = await election.electableValidators();
  const txs: Promise<void>[] = [];
  for (let i = 0; i < min.toNumber(); i++) {
    const tx = voteForGroup(groups[i].address, voter);
    txs.push(tx);
  }

  await Promise.all(txs);
  await mineToNextEpoch(kit.web3);
  await activateVotesForGroup(voter);
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
  await hre.run(MULTISIG_SUBMIT_PROPOSAL, {
    destinations: destinations.join(","),
    values: values.join(","),
    payloads: payloads.join(","),
    account: account,
    useNodeAccount: true,
  });

  await hre.run(MULTISIG_EXECUTE_PROPOSAL, {
    proposalId: 0,
    account: account,
    useNodeAccount: true,
  });
}

export async function waitForEvent(
  contract: Contract,
  eventName: string,
  expectedValue: string,
  timeout: number = 10000
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
