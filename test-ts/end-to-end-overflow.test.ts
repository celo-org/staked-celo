import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BigNumberJs from "bignumber.js";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { ACCOUNT_REVOKE } from "../lib/tasksNames";
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
  rebalanceDefaultGroups,
  rebalanceGroups,
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
  const deployerAccountName = "deployer";
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategy: DefaultStrategy;
  let election: ElectionWrapper;
  let lockedGold: LockedGoldWrapper;

  // deposits to specific strategy without overflowing
  let depositor0: SignerWithAddress;
  // deposits to specific strategy with overflow, changes to different specific strategy and returns back to original one
  let depositor1: SignerWithAddress;
  let depositor2: SignerWithAddress;
  let voter: SignerWithAddress;

  let groups: SignerWithAddress[];
  let activatedGroupAddresses: string[];
  let multisigOwner0: SignerWithAddress;

  let specGroupDifferentFromActive: SignerWithAddress;
  let specGroupSameAsActive: SignerWithAddress;

  const ZERO = BigNumber.from(0);

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
    [depositor2] = await randomSigner(parseUnits("300"));
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

    specGroupDifferentFromActive = groups[5];
    specGroupSameAsActive = groups[0];
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
      multisigOwner0,
      activatedGroupAddresses
    );
  });

  const firstGCapacity = parseUnits("40.166666666666666666");
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
    await expectCeloForGroup(groups[0].address, ZERO);
    await expectCeloForGroup(groups[1].address, ZERO);
    await expectCeloForGroup(groups[2].address, ZERO);
    await expectCeloForGroup(specGroupDifferentFromActive.address, ZERO);
    await expectReceivableVotes(groups[0].address, firstGCapacity);
    await expectReceivableVotes(groups[1].address, secondGroupCapacity);
    await expectReceivableVotes(groups[2].address, thirdGroupCapacity);
    const celoDeposit = hre.ethers.BigNumber.from(parseUnits("10"));
    const overflow = celoDeposit;

    await managerContract.connect(depositor0).changeStrategy(specGroupSameAsActive.address);
    await managerContract.connect(depositor1).changeStrategy(specGroupSameAsActive.address);
    await managerContract.connect(depositor2).changeStrategy(groups[1].address);

    await managerContract.connect(depositor0).deposit({ value: celoDeposit });
    await expectCeloForGroup(groups[0].address, celoDeposit);
    await expectReceivableVotes(groups[0].address, firstGCapacity.sub(celoDeposit));
    await expectSpecGStCelo(specGroupSameAsActive.address, celoDeposit, BigNumber.from("0"));

    const [tail] = await defaultStrategy.getGroupsTail();
    expect(tail).to.eq(groups[2].address);

    await managerContract.connect(depositor1).deposit({ value: firstGCapacity });
    await expectCeloForGroup(groups[0].address, firstGCapacity);
    await expectReceivableVotes(groups[0].address, ZERO);
    await expectSpecGStCelo(
      specGroupSameAsActive.address,
      celoDeposit.add(firstGCapacity),
      celoDeposit
    );
    await expectVotes(groups[0].address, ZERO, firstGCapacity, ZERO, ZERO);
    await expectVotes(groups[1].address, ZERO, ZERO, ZERO, ZERO);
    await expectVotes(groups[2].address, ZERO, overflow, ZERO, ZERO);

    const [head] = await defaultStrategy.getGroupsHead();

    await managerContract.connect(depositor1).changeStrategy(specGroupDifferentFromActive.address);
    await rebalanceAllAndActivate();
    await expectCeloForGroup(groups[0].address, celoDeposit);

    await expectVotes(specGroupDifferentFromActive.address, firstGCapacity, ZERO, ZERO, ZERO);
    await expectVotes(groups[0].address, celoDeposit, ZERO, ZERO, ZERO);
    await expectVotes(head, ZERO, ZERO, ZERO, ZERO);

    const g0ReceivableVotes = await managerContract.getReceivableVotesForGroup(
      specGroupSameAsActive.address
    );
    const g0ExpectedOverflow = firstGCapacity.sub(g0ReceivableVotes);
    await managerContract.connect(depositor1).changeStrategy(specGroupSameAsActive.address);

    await expectSpecGStCelo(specGroupDifferentFromActive.address, ZERO, ZERO);
    await expectSpecGStCelo(
      specGroupSameAsActive.address,
      celoDeposit.add(firstGCapacity),
      g0ExpectedOverflow
    );

    await rebalanceAllAndActivate();
    await expectCeloForGroup(
      groups[0].address,
      firstGCapacity.add(celoDeposit).sub(g0ExpectedOverflow)
    );
    await expectVotes(
      specGroupSameAsActive.address,
      celoDeposit.add(g0ReceivableVotes),
      ZERO,
      ZERO,
      ZERO
    );
    await expectVotes(groups[1].address, g0ExpectedOverflow.div(3), ZERO, ZERO, ZERO);
    await expectVotes(groups[2].address, g0ExpectedOverflow.div(3), ZERO, ZERO, ZERO);
    // since default group[0] is overflowing - it is not possible to move Celo there
    // this celo stays in the specific strategy
    await expectVotes(
      specGroupDifferentFromActive.address,
      g0ExpectedOverflow.div(3),
      ZERO,
      ZERO,
      ZERO
    );

    await activateAndVoteTest();

    // since new CELO was deposited, capacity was changed
    const newSecondGroupCapacity = await managerContract.getReceivableVotesForGroup(
      groups[1].address
    );
    const newDeposit = newSecondGroupCapacity.div(2);
    await lockedGold.lock().sendAndWaitForReceipt({
      from: voter.address,
      value: newDeposit.mul(10).toString(),
    });

    const newSecondGroupCapacityAfterLock = await managerContract.getReceivableVotesForGroup(
      groups[1].address
    );
    await managerContract.connect(depositor2).deposit({ value: newDeposit });
    await expectReceivableVotes(groups[1].address, newSecondGroupCapacityAfterLock.sub(newDeposit));

    // someone made deposit outside of the protocol and scheduled votes are not activatable anymore
    const receivableByGroup1 = await managerContract.getReceivableVotesForGroup(groups[1].address);
    const scheduledForGroup1 = await accountContract.scheduledVotesForGroup(groups[1].address);

    const voteTx = await election.vote(
      groups[1].address,
      new BigNumberJs(receivableByGroup1.add(scheduledForGroup1).toString())
    );
    await voteTx.sendAndWaitForReceipt({ from: voter.address });
    await expectVotes(groups[1].address, g0ExpectedOverflow.div(3), newDeposit, ZERO, ZERO);
    await expectVotes(groups[2].address, g0ExpectedOverflow.div(3), ZERO, ZERO, ZERO);

    await managerContract.rebalanceOverflow(groups[1].address, groups[2].address);

    await expectVotes(groups[1].address, g0ExpectedOverflow.div(3), ZERO, ZERO, ZERO);
    await expectVotes(groups[2].address, g0ExpectedOverflow.div(3), scheduledForGroup1, ZERO, ZERO);
  });

  async function expectVotes(
    group: string,
    votes: BigNumber | null,
    toVote: BigNumber,
    toRevoke: BigNumber,
    toWithdraw: BigNumber
  ) {
    const [actualVotes, scheduledVotes, actualToRevoke, actualToWithdraw] = await getVotes(group);
    if (votes != null) {
      expectBigNumberInRange(actualVotes, votes, `${group} actualVotes`);
    }
    expectBigNumberInRange(scheduledVotes, toVote, `${group} scheduledVotes`);
    expectBigNumberInRange(actualToRevoke, toRevoke, `${group} actualToRevoke`);
    expectBigNumberInRange(actualToWithdraw, toWithdraw, `${group} actualToWithdraw`);
  }

  async function getVotes(group: string) {
    const votesPromise = accountContract.votesForGroup(group);
    const toVotePromise = accountContract.scheduledVotesForGroup(group);
    const toRevokePromise = accountContract.scheduledRevokeForGroup(group);
    const toWithdrawPromise = accountContract.scheduledWithdrawalsForGroup(group);

    const [actualVotes, scheduledVotes, actualToRevoke, actualToWithdraw] = await Promise.all([
      votesPromise,
      toVotePromise,
      toRevokePromise,
      toWithdrawPromise,
    ]);

    return [actualVotes, scheduledVotes, actualToRevoke, actualToWithdraw];
  }

  async function expectCeloForGroup(group: string, amount: BigNumber) {
    const celoForGroup = await accountContract.getCeloForGroup(group);
    expect(celoForGroup).to.deep.eq(amount);
  }

  async function expectReceivableVotes(group: string, amount: BigNumber) {
    const receivableAmount = await managerContract.getReceivableVotesForGroup(group);
    expect(receivableAmount).to.deep.eq(amount);
  }

  async function expectSpecGStCelo(strategy: string, total?: BigNumber, overflow?: BigNumber) {
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

  async function rebalanceAllAndActivate() {
    await rebalanceDefaultGroups(defaultStrategy);
    await rebalanceGroups(managerContract, specificGroupStrategyContract, defaultStrategy);
    await hre.run(ACCOUNT_REVOKE, {
      account: deployerAccountName,
      useNodeAccount: true,
      logLevel: "info",
    });
    await activateAndVoteTest();
  }

  function expectBigNumberInRange(
    real: BigNumber,
    expected: BigNumber,
    message?: string,
    range = 1
  ) {
    expect(
      real.add(range).gte(expected),
      `${message} Number ${real.toString()} is not ${expected.toString()} in range <${expected
        .sub(range)
        .toString()}, ${expected.add(range).toString()}>}`
    ).to.be.true;
    expect(
      real.sub(range).lte(expected),
      `${message} Number ${real.toString()} is not ${expected.toString()}  in range <${expected
        .sub(range)
        .toString()}, ${expected.add(range).toString()}>}`
    ).to.be.true;
  }
});
