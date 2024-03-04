import { CeloTxReceipt } from "@celo/connect";
import { stringToSolidityBytes } from "@celo/contractkit/lib/wrappers/BaseWrapper";
import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { default as BigNumber, default as BigNumberJs } from "bignumber.js";
import { BigNumber as EthersBigNumber, Wallet } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre, { kit } from "hardhat";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { MockLockedGold } from "../typechain-types/MockLockedGold";
import { MockRegistry } from "../typechain-types/MockRegistry";
import { MockValidators } from "../typechain-types/MockValidators";
import {
  ADDRESS_ZERO,
  DAY,
  impersonateAccount,
  mineToNextEpoch,
  MIN_VALIDATOR_LOCKED_CELO,
  submitAndExecuteProposal,
  timeTravel,
} from "./utils";

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

export async function electMockValidatorGroupsAndUpdate(
  validators: ValidatorsWrapper,
  groupHealthContract: MockGroupHealth,
  validatorGroups: string[],
  revoke = false,
  update = true,
  makeOneValidatorGroupUseSigner = true
): Promise<number[]> {
  let validatorsProcessed = 0;
  const mockedIndexes: number[] = [];

  for (let j = 0; j < validatorGroups.length; j++) {
    const validatorGroup = validatorGroups[j];
    const isValidatorGroup = await validators.isValidatorGroup(validatorGroup);

    if (isValidatorGroup) {
      const validatorGroupDetail = await validators.getValidatorGroup(validatorGroup);
      for (let i = 0; i < validatorGroupDetail.members.length; i++) {
        const memberOriginalAccount = validatorGroupDetail.members[i];
        const signer = makeOneValidatorGroupUseSigner
          ? await makeValidatorUseSigner(memberOriginalAccount)
          : memberOriginalAccount;
        const mockIndex = validatorsProcessed++;
        await groupHealthContract.setElectedValidator(mockIndex, revoke ? ADDRESS_ZERO : signer);
        mockedIndexes.push(mockIndex);
      }
    }
    if (update) {
      await groupHealthContract.updateGroupHealth(validatorGroup);
    }

    makeOneValidatorGroupUseSigner = false;
  }
  return mockedIndexes;
}

async function makeValidatorUseSigner(validatorAddress: string) {
  const newAccountWallet = hre.ethers.Wallet.createRandom();
  const newSignerAddress = await newAccountWallet.getAddress();

  const accounts = await hre.kit.contracts.getAccounts();

  const pop = await accounts.generateProofOfKeyPossessionLocally(
    validatorAddress,
    newSignerAddress,
    newAccountWallet.privateKey
  );
  const publicKey = stringToSolidityBytes(newAccountWallet.publicKey.slice(4));
  const authWithPubKey = await accounts["contract"].methods.authorizeValidatorSignerWithPublicKey(
    newSignerAddress,
    pop.v,
    pop.r,
    pop.s,
    publicKey
  );
  await authWithPubKey.send({ from: validatorAddress });
  return newSignerAddress;
}
