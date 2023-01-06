import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { revoke } from "../lib/account-tasks/helpers/revokeHelper";
import { ACCOUNT_WITHDRAW } from "../lib/tasksNames";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import { StakedCelo } from "../typechain-types/StakedCelo";
import {
  activateAndVoteTest,
  activateValidators,
  allowStrategies,
  distributeEpochRewards,
  electMinimumNumberOfValidators,
  getGroupsSafe,
  getRealVsExpectedCeloForGroups,
  LOCKED_GOLD_UNLOCKING_PERIOD,
  mineToNextEpoch,
  randomSigner,
  rebalanceGroups,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  resetNetwork,
  timeTravel,
} from "./utils";

after(() => {
  hre.kit.stop();
});

describe("e2e specific group strategy voting", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let groupHealthContract: GroupHealth;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategy: DefaultStrategy;

  const deployerAccountName = "deployer";
  // default strategy
  let depositor0: SignerWithAddress;
  // allowed strategy that is different from active groups
  let depositor1: SignerWithAddress;
  // allowed strategy that is same as one of the active groups
  let depositor2: SignerWithAddress;
  // default strategy
  let depositor3: SignerWithAddress;
  // allowed strategy that is same as one of the active groups
  let depositor4: SignerWithAddress;
  let voter: SignerWithAddress;

  let groups: SignerWithAddress[];
  let activatedGroupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let stakedCeloContract: StakedCelo;
  let multisigOwner0: SignerWithAddress;

  const rewardsGroup0 = hre.ethers.BigNumber.from(parseUnits("10"));
  const rewardsGroup1 = hre.ethers.BigNumber.from(parseUnits("20"));
  const rewardsGroup2 = hre.ethers.BigNumber.from(parseUnits("30"));
  const rewardsGroup5 = hre.ethers.BigNumber.from(parseUnits("10"));

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
    [depositor2] = await randomSigner(parseUnits("300"));
    [depositor3] = await randomSigner(parseUnits("300"));
    [depositor4] = await randomSigner(parseUnits("300"));
    [voter] = await randomSigner(parseUnits("300"));
    const accounts = await hre.kit.contracts.getAccounts();
    await accounts.createAccount().sendAndWaitForReceipt({
      from: voter.address,
    });
    groups = [];
    activatedGroupAddresses = [];
    validators = [];
    validatorAddresses = [];
    for (let i = 0; i < 10; i++) {
      const [group] = await randomSigner(parseUnits("11000"));
      groups.push(group);
      if (i < 3) {
        activatedGroupAddresses.push(groups[i].address);
      }
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      validators.push(validator);
      validatorAddresses.push(validators[i].address);

      await registerValidatorGroup(groups[i]);
      await registerValidatorAndAddToGroupMembers(groups[i], validators[i], validatorWallet);
    }
    await electMinimumNumberOfValidators(groups, voter);

    specificGroupStrategyDifferentFromActive = groups[5];
    specificGroupStrategySameAsActive = groups[0];
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    stakedCeloContract = await hre.ethers.getContract("StakedCelo");
    groupHealthContract = await hre.ethers.getContract("GroupHealth");
    specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");
    defaultStrategy = await hre.ethers.getContract("DefaultStrategy");

    multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
    await activateValidators(
      managerContract,
      defaultStrategy,
      groupHealthContract,
      multisigOwner0.address,
      activatedGroupAddresses
    );
  });

  it("deposit, rebalance, transfer and withdraw", async () => {
    const amountOfCeloToDeposit = hre.ethers.BigNumber.from(parseUnits("1"));

    await allowStrategy(specificGroupStrategyDifferentFromActive.address);
    await allowStrategy(specificGroupStrategySameAsActive.address);
    await managerContract
      .connect(depositor1)
      .changeStrategy(specificGroupStrategyDifferentFromActive.address);
    await managerContract
      .connect(depositor2)
      .changeStrategy(specificGroupStrategySameAsActive.address);
    await managerContract
      .connect(depositor4)
      .changeStrategy(specificGroupStrategySameAsActive.address);

    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    await managerContract.connect(depositor0).deposit({ value: amountOfCeloToDeposit });
    await managerContract.connect(depositor1).deposit({ value: amountOfCeloToDeposit });
    await managerContract.connect(depositor4).deposit({ value: amountOfCeloToDeposit });

    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    // default strategy -> default strategy
    await stakedCeloContract
      .connect(depositor0)
      .transfer(depositor3.address, amountOfCeloToDeposit.div(2));
    // specificGroupStrategyDifferentFromActive -> default strategy
    await stakedCeloContract
      .connect(depositor1)
      .transfer(depositor3.address, amountOfCeloToDeposit.div(2));
    // specificGroupStrategySameAsActive -> default strategy
    await stakedCeloContract
      .connect(depositor4)
      .transfer(depositor3.address, amountOfCeloToDeposit.div(2));
    // specificGroupStrategySameAsActive -> specificGroupStrategyDifferentFromActive
    await stakedCeloContract
      .connect(depositor4)
      .transfer(depositor1.address, amountOfCeloToDeposit.div(2));
    // default strategy -> specificGroupStrategySameAsActive
    await stakedCeloContract
      .connect(depositor3)
      .transfer(depositor4.address, amountOfCeloToDeposit.div(2));

    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    await expectStCeloBalance(depositor0.address, amountOfCeloToDeposit.div(2));
    await expectStCeloBalance(depositor1.address, amountOfCeloToDeposit);
    await expectStCeloBalance(depositor3.address, amountOfCeloToDeposit);
    await expectStCeloBalance(depositor4.address, amountOfCeloToDeposit.div(2));

    await rebalanceAllAndActivate();

    await activateAndVoteTest();
    await mineToNextEpoch(hre.web3);
    await activateAndVoteTest();
    await distributeAllRewards();
    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    await rebalanceAllAndActivate();

    const depositor0BeforeWithdrawalStCeloBalance = await stakedCeloContract.balanceOf(
      depositor0.address
    );
    const depositor0ExpectedCeloToBeWithdrawn = await managerContract.toCelo(
      depositor0BeforeWithdrawalStCeloBalance
    );
    const depositor1BeforeWithdrawalStCeloBalance = await stakedCeloContract.balanceOf(
      depositor1.address
    );
    const depositor1ExpectedCeloToBeWithdrawn = await managerContract.toCelo(
      depositor1BeforeWithdrawalStCeloBalance
    );
    const depositor3BeforeWithdrawalStCeloBalance = await stakedCeloContract.balanceOf(
      depositor3.address
    );
    const depositor3ExpectedCeloToBeWithdrawn = await managerContract.toCelo(
      depositor3BeforeWithdrawalStCeloBalance
    );
    const depositor4BeforeWithdrawalStCeloBalance = await stakedCeloContract.balanceOf(
      depositor4.address
    );
    const depositor4ExpectedCeloToBeWithdrawn = await managerContract.toCelo(
      depositor4BeforeWithdrawalStCeloBalance
    );

    await managerContract.connect(depositor0).withdraw(amountOfCeloToDeposit.div(2));
    await managerContract.connect(depositor1).withdraw(amountOfCeloToDeposit);
    await managerContract.connect(depositor3).withdraw(amountOfCeloToDeposit);
    await managerContract.connect(depositor4).withdraw(amountOfCeloToDeposit.div(2));

    await expectStCeloBalance(depositor1.address, 0);

    const depositor0BeforeWithdrawalBalance = await depositor0.getBalance();
    const depositor1BeforeWithdrawalBalance = await depositor1.getBalance();

    const depositor3BeforeWithdrawalBalance = await depositor3.getBalance();
    const depositor4BeforeWithdrawalBalance = await depositor4.getBalance();

    await hre.run(ACCOUNT_WITHDRAW, {
      beneficiary: depositor0.address,
      account: deployerAccountName,
      useNodeAccount: true,
    });
    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);
    await finishPendingWithdrawalForAccount(depositor0.address);

    await hre.run(ACCOUNT_WITHDRAW, {
      beneficiary: depositor1.address,
      account: deployerAccountName,
      useNodeAccount: true,
    });
    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);
    await finishPendingWithdrawalForAccount(depositor1.address);

    await hre.run(ACCOUNT_WITHDRAW, {
      beneficiary: depositor3.address,
      account: deployerAccountName,
      useNodeAccount: true,
    });
    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);
    await finishPendingWithdrawalForAccount(depositor3.address);

    await hre.run(ACCOUNT_WITHDRAW, {
      beneficiary: depositor4.address,
      account: deployerAccountName,
      useNodeAccount: true,
    });
    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);
    await finishPendingWithdrawalForAccount(depositor4.address);

    expect(0).to.eq((await stakedCeloContract.totalSupply()).toNumber());
    expect(0).to.eq(await accountContract.getTotalCelo());

    await managerContract.connect(depositor2).deposit({ value: amountOfCeloToDeposit });
    await expectStCeloBalance(
      depositor2.address,
      await managerContract.toStakedCelo(amountOfCeloToDeposit)
    );

    const depositor0AfterWithdrawalBalance = await depositor0.getBalance();
    const depositor1AfterWithdrawalBalance = await depositor1.getBalance();
    const depositor3AfterWithdrawalBalance = await depositor3.getBalance();
    const depositor4AfterWithdrawalBalance = await depositor4.getBalance();

    expectBigNumberInRange(
      depositor0ExpectedCeloToBeWithdrawn,
      depositor0AfterWithdrawalBalance.sub(depositor0BeforeWithdrawalBalance)
    );
    expectBigNumberInRange(
      depositor1ExpectedCeloToBeWithdrawn,
      depositor1AfterWithdrawalBalance.sub(depositor1BeforeWithdrawalBalance)
    );
    expectBigNumberInRange(
      depositor3ExpectedCeloToBeWithdrawn,
      depositor3AfterWithdrawalBalance.sub(depositor3BeforeWithdrawalBalance)
    );
    expectBigNumberInRange(
      depositor4ExpectedCeloToBeWithdrawn,
      depositor4AfterWithdrawalBalance.sub(depositor4BeforeWithdrawalBalance)
    );
  });

  async function allowStrategy(strategy: string) {
    await expect(managerContract.connect(depositor1).changeStrategy(strategy)).revertedWith(
      `GroupNotEligible("${strategy}")`
    );
    await allowStrategies(
      specificGroupStrategyContract,
      groupHealthContract,
      multisigOwner0.address,
      [strategy]
    );
  }

  async function rebalanceAllAndActivate() {
    await rebalanceGroups(
      managerContract,
      groupHealthContract,
      specificGroupStrategyContract,
      defaultStrategy
    );
    await revoke(hre, depositor0);
    await activateAndVoteTest();
  }

  async function distributeAllRewards() {
    await distributeEpochRewards(groups[0].address, rewardsGroup0.toString());
    await distributeEpochRewards(groups[1].address, rewardsGroup1.toString());
    await distributeEpochRewards(groups[2].address, rewardsGroup2.toString());
    await distributeEpochRewards(groups[5].address, rewardsGroup5.toString());
  }

  async function expectStCeloBalance(account: string, expectedAmount: BigNumberish) {
    const balance = await stakedCeloContract.balanceOf(account);
    expect(expectedAmount, `account ${account} ex: ${expectedAmount} real: ${balance}`).to.eq(
      balance
    );
  }

  async function finishPendingWithdrawalForAccount(account: string) {
    const { timestamps } = await accountContract.getPendingWithdrawals(account);
    let totalGasUsed = hre.ethers.BigNumber.from(0);

    expect(
      timestamps.length,
      `There are no pending withdrawals for account ${account}`
    ).to.greaterThan(0);

    for (let i = 0; i < timestamps.length; i++) {
      const finishPendingWithdrawalForAccount = await accountContract.finishPendingWithdrawal(
        account,
        0,
        0
      );
      const txReceipt = await finishPendingWithdrawalForAccount.wait();
      totalGasUsed = totalGasUsed.add(txReceipt.gasUsed);
    }

    return totalGasUsed;
  }

  // We use range because of possible rounding errors when withdrawing
  function expectBigNumberInRange(real: BigNumber, expected: BigNumber, range = 10) {
    expect(
      real.add(range).gte(expected),
      `Number ${real.toString()} is not in range <${expected.sub(range).toString()}, ${expected
        .add(range)
        .toString()}>`
    ).to.be.true;
    expect(
      real.sub(range).lte(expected),
      `Number ${real.toString()} is not in range <${expected.sub(range).toString()}, ${expected
        .add(range)
        .toString()}>`
    ).to.be.true;
  }

  async function expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy: DefaultStrategy) {
    const allGroups = await getGroupsSafe(defaultStrategy, specificGroupStrategyContract);
    const expectedVsReal = await getRealVsExpectedCeloForGroups(groupHealthContract, allGroups);
    const expectedSum = hre.ethers.BigNumber.from(0);
    const realSum = hre.ethers.BigNumber.from(0);
    for (const group of expectedVsReal) {
      expectedSum.add(group.expected);
      realSum.add(group.real);
    }
    expect(expectedSum).to.deep.eq(realSum);
  }
});
