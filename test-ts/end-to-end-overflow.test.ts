import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BigNumberJs from "bignumber.js";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import {
  activateAndVoteTest,
  prepareOverflow,
  randomSigner,
  resetNetwork,
  upgradeToMockGroupHealthE2E,
} from "./utils";
import {
  activateValidators,
  electMockValidatorGroupsAndUpdate,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
} from "./utils-validators";

after(() => {
  hre.kit.stop();
});

describe("e2e overflow test", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let groupHealthContract: MockGroupHealth;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategy: DefaultStrategy;
  let election: ElectionWrapper;
  let lockedGold: LockedGoldWrapper;

  // deposits to specific strategy without overflowing
  let depositor0: SignerWithAddress;
  // deposits to specific strategy with overflow, changes to different specific strategy and returns back to original one
  let depositor1: SignerWithAddress;
  let voter: SignerWithAddress;

  let groups: SignerWithAddress[];
  let activatedGroupAddresses: string[];
  let multisigOwner0: SignerWithAddress;

  let specificGroupStrategyDifferentFromActive: SignerWithAddress;
  let specificGroupStrategySameAsActive: SignerWithAddress;

  // eslint-disable-next-line no-unused-vars, @typescript-eslint/no-explicit-any
  before(async function (this: any) {
    this.timeout(0); // Disable test timeout
    await resetNetwork();

    process.env = {
      ...process.env,
      TIME_LOCK_MIN_DELAY: "1",
      TIME_LOCK_DELAY: "1",
      MULTISIG_REQUIRED_CONFIRMATIONS: "1",
      VALIDATOR_GROUPS: "",
    };

    [depositor0] = await randomSigner(parseUnits("300"));
    [depositor1] = await randomSigner(parseUnits("300"));
    [voter] = await randomSigner(parseUnits("10000000000"));
    const accounts = await hre.kit.contracts.getAccounts();
    await accounts.createAccount().sendAndWaitForReceipt({
      from: voter.address,
    });
    groups = [];
    activatedGroupAddresses = [];

    groups = [];
    for (let i = 0; i < 11; i++) {
      const [group] = await randomSigner(parseUnits("21000"));
      groups.push(group);
    }
    for (let i = 0; i < 11; i++) {
      if (i == 1) {
        // For groups[1] we register an extra validator so it has a higher voting limit.
        await registerValidatorGroup(groups[i], 2);
        const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
        await registerValidatorAndAddToGroupMembers(groups[i], validator, validatorWallet);
      } else {
        await registerValidatorGroup(groups[i], 1);
      }
      if (i < 3) {
        activatedGroupAddresses.push(groups[i].address);
      }
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      await registerValidatorAndAddToGroupMembers(groups[i], validator, validatorWallet);
    }

    specificGroupStrategyDifferentFromActive = groups[5];
    specificGroupStrategySameAsActive = groups[0];
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    groupHealthContract = await hre.ethers.getContract("GroupHealth");
    specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");
    defaultStrategy = await hre.ethers.getContract("DefaultStrategy");
    lockedGold = await hre.kit.contracts.getLockedGold();
    election = await hre.kit.contracts.getElection();

    multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");

    groupHealthContract = await upgradeToMockGroupHealthE2E(
      multisigOwner0,
      groupHealthContract as unknown as GroupHealth
    );
    const validatorWrapper = await hre.kit.contracts.getValidators();
    await electMockValidatorGroupsAndUpdate(validatorWrapper, groupHealthContract, [
      ...activatedGroupAddresses,
      groups[5].address,
    ]);

    await activateValidators(
      defaultStrategy,
      groupHealthContract as unknown as GroupHealth,
      multisigOwner0.address,
      activatedGroupAddresses
    );
  });

  const firstGroupCapacity = parseUnits("40.166666666666666666");
  const secondGroupCapacity = parseUnits("99.25");
  const thirdGroupCapacity = parseUnits("200.166666666666666666");

  it("deposit, transfer and activate", async () => {
    await prepareOverflow(
      defaultStrategy,
      election,
      lockedGold,
      voter,
      activatedGroupAddresses,
      false
    );

    await expectCeloForGroup(groups[0].address, BigNumber.from(0));
    await expectCeloForGroup(groups[1].address, BigNumber.from(0));
    await expectCeloForGroup(groups[2].address, BigNumber.from(0));
    await expectCeloForGroup(specificGroupStrategyDifferentFromActive.address, BigNumber.from(0));

    await expectReceivableVotes(groups[0].address, firstGroupCapacity);
    await expectReceivableVotes(groups[1].address, secondGroupCapacity);
    await expectReceivableVotes(groups[2].address, thirdGroupCapacity);

    const amountOfCeloToDeposit = hre.ethers.BigNumber.from(parseUnits("1"));

    await managerContract
      .connect(depositor0)
      .changeStrategy(specificGroupStrategySameAsActive.address);
    await managerContract
      .connect(depositor1)
      .changeStrategy(specificGroupStrategySameAsActive.address);

    await managerContract.connect(depositor0).deposit({ value: amountOfCeloToDeposit });
    await expectCeloForGroup(groups[0].address, amountOfCeloToDeposit);
    await expectReceivableVotes(groups[0].address, firstGroupCapacity.sub(amountOfCeloToDeposit));
    await expectSpecificGroupOverflow(
      specificGroupStrategySameAsActive.address,
      amountOfCeloToDeposit,
      BigNumber.from("0")
    );

    const [tail] = await defaultStrategy.getGroupsTail();
    expect(tail).to.eq(groups[2].address);

    await managerContract.connect(depositor1).deposit({ value: firstGroupCapacity });
    await expectCeloForGroup(groups[0].address, firstGroupCapacity);
    await expectReceivableVotes(groups[0].address, BigNumber.from(0));
    const overflow = amountOfCeloToDeposit;
    await expectSpecificGroupOverflow(
      specificGroupStrategySameAsActive.address,
      amountOfCeloToDeposit.add(firstGroupCapacity),
      amountOfCeloToDeposit
    );

    await expectAccountVotes(
      groups[0].address,
      firstGroupCapacity,
      BigNumber.from(0),
      BigNumber.from(0)
    );
    await expectAccountVotes(
      groups[1].address,
      BigNumber.from(0),
      BigNumber.from(0),
      BigNumber.from(0)
    );
    await expectAccountVotes(groups[2].address, overflow, BigNumber.from(0), BigNumber.from(0));

    const [head] = await defaultStrategy.getGroupsHead();

    await managerContract
      .connect(depositor1)
      .changeStrategy(specificGroupStrategyDifferentFromActive.address);
    await expectCeloForGroup(groups[0].address, amountOfCeloToDeposit);

    await expectAccountVotes(
      specificGroupStrategyDifferentFromActive.address,
      firstGroupCapacity,
      BigNumber.from(0),
      BigNumber.from(0)
    );
    await expectAccountVotes(
      groups[0].address,
      amountOfCeloToDeposit,
      BigNumber.from(0),
      BigNumber.from(0)
    );
    await expectAccountVotes(head, BigNumber.from(0), BigNumber.from(0), BigNumber.from(0));

    const [newTail] = await defaultStrategy.getGroupsTail();
    await managerContract
      .connect(depositor1)
      .changeStrategy(specificGroupStrategySameAsActive.address);

    await expectCeloForGroup(groups[0].address, firstGroupCapacity);

    await expectAccountVotes(
      specificGroupStrategyDifferentFromActive.address,
      BigNumber.from(0),
      BigNumber.from(0),
      BigNumber.from(0)
    );
    await expectCeloForGroup(specificGroupStrategySameAsActive.address, firstGroupCapacity);
    await expectAccountVotes(newTail, overflow, BigNumber.from(0), BigNumber.from(0));

    await activateAndVoteTest();

    // since new CELO was deposited, capacity was changed
    const newDeposit = parseUnits("6");
    await lockedGold.lock().sendAndWaitForReceipt({
      from: voter.address,
      value: newDeposit.toString(),
    });
    const newFirstGroupCapacity = parseUnits("7.861111111111111111");
    await expectReceivableVotes(groups[0].address, newFirstGroupCapacity);

    await managerContract.connect(depositor1).deposit({ value: newDeposit });

    await expectReceivableVotes(groups[0].address, newFirstGroupCapacity.sub(newDeposit));

    // someone made deposit outside of the protocol and scheduled votes are not activatable anymore

    const voteTx = await election.vote(groups[0].address, new BigNumberJs(newDeposit.toString()));
    await voteTx.sendAndWaitForReceipt({ from: voter.address });

    await expectAccountVotes(groups[0].address, newDeposit, BigNumber.from(0), BigNumber.from(0));
    await expectAccountVotes(
      groups[1].address,
      BigNumber.from(0),
      BigNumber.from(0),
      BigNumber.from(0)
    );

    await managerContract.rebalanceOverflow(groups[0].address, groups[1].address);

    await expectAccountVotes(
      groups[0].address,
      newFirstGroupCapacity.sub(newDeposit),
      BigNumber.from(0),
      BigNumber.from(0)
    );
    await expectAccountVotes(
      groups[1].address,
      newDeposit.sub(newFirstGroupCapacity.sub(newDeposit)),
      BigNumber.from(0),
      BigNumber.from(0)
    );
  });

  async function expectAccountVotes(
    group: string,
    toVote: BigNumber,
    toRevoke: BigNumber,
    toWithdraw: BigNumber
  ) {
    const toVotePromise = await accountContract.scheduledVotesForGroup(group);
    const toRevokePromise = await accountContract.scheduledRevokeForGroup(group);
    const toWithdrawPromise = await accountContract.scheduledWithdrawalsForGroup(group);

    const [actualToVote, actualToRevoke, actualToWithdraw] = await Promise.all([
      toVotePromise,
      toRevokePromise,
      toWithdrawPromise,
    ]);

    expect(actualToVote).to.deep.eq(toVote);
    expect(actualToRevoke).to.deep.eq(toRevoke);
    expect(actualToWithdraw).to.deep.eq(toWithdraw);
  }

  async function expectCeloForGroup(group: string, amount: BigNumber) {
    const celoForGroup = await accountContract.getCeloForGroup(group);
    expect(celoForGroup).to.deep.eq(amount);
  }

  async function expectReceivableVotes(group: string, amount: BigNumber) {
    const receivableAmount = await managerContract.getReceivableVotesForGroup(group);
    expect(receivableAmount).to.deep.eq(amount);
  }

  async function expectSpecificGroupOverflow(
    strategy: string,
    total?: BigNumber,
    overflow?: BigNumber
  ) {
    const [totalActual, overflowActual] = await specificGroupStrategyContract.getStCeloInGroup(
      strategy
    );
    if (total != undefined) {
      expect(totalActual).to.deep.eq(total);
    }
    if (overflow != undefined) {
      expect(overflowActual).to.deep.eq(overflow);
    }
  }
});
