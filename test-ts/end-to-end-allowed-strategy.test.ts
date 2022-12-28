import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumberish } from "ethers";
import { formatEther, parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { revoke } from "../lib/account-tasks/helpers/revokeHelper";
import { ACCOUNT_WITHDRAW } from "../lib/tasksNames";
import { Account } from "../typechain-types/Account";
import { Manager } from "../typechain-types/Manager";
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

describe("e2e allowed strategy voting", () => {
  let accountContract: Account;
  let managerContract: Manager;

  const deployerAccountName = "deployer";
  // deposits CELO to default strategy, receives stCELO, but never withdraws it
  let depositor0: SignerWithAddress;
  // deposits CELO to allowed strategy that is different from active groups, receives stCELO, withdraws stCELO including rewards
  let depositor1: SignerWithAddress;
  // deposits CELO after rewards are distributed -> depositor will receive less stCELO than deposited CELO
  let depositor2: SignerWithAddress;
  // only receives stCELO from default and allowed strategy (depositor0 and depositor1)
  let depositor3: SignerWithAddress;
  // deposits CELO to allowed strategy that is same as one of the active groups
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

  let allowedStrategyDifferentFromActive: SignerWithAddress;
  let allowedStrategySameAsActive: SignerWithAddress;

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

    allowedStrategyDifferentFromActive = groups[5];
    allowedStrategySameAsActive = groups[0];
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    stakedCeloContract = await hre.ethers.getContract("StakedCelo");

    multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
    await activateValidators(managerContract, multisigOwner0.address, activatedGroupAddresses);
  });

  it("deposit, rebalance, transfer and withdraw", async () => {
    for (let i = 0; i < 6; i++) {
      console.log(`aaa group[${i}]: ${groups[i].address}`);
    }

    const amountOfCeloToDeposit = hre.ethers.BigNumber.from(parseUnits("1"));

    await allowStrategy(allowedStrategyDifferentFromActive.address);
    await allowStrategy(allowedStrategySameAsActive.address);
    await managerContract
      .connect(depositor1)
      .changeStrategy(allowedStrategyDifferentFromActive.address);
    await managerContract.connect(depositor2).changeStrategy(allowedStrategySameAsActive.address);
    await managerContract.connect(depositor4).changeStrategy(allowedStrategySameAsActive.address);

    const newGroups = await getGroupsSafe(managerContract);

    console.log(
      "realVsExpectedGroups before deposit",
      JSON.stringify(
        (await getRealVsExpectedCeloForGroups(managerContract, newGroups))
          .sort((a, b) => (a.diff.lt(b.diff) ? 1 : -1))
          .map((k) => ({
            group: k.group,
            diff: k.diff.toString(),
            real: k.real.toString(),
            expected: k.expected.toString(),
          }))
      )
    );

    await managerContract.connect(depositor0).deposit({ value: amountOfCeloToDeposit });
    await managerContract.connect(depositor1).deposit({ value: amountOfCeloToDeposit });
    await managerContract.connect(depositor4).deposit({ value: amountOfCeloToDeposit });

    console.log(
      "realVsExpectedGroups after deposit",
      JSON.stringify(
        (await getRealVsExpectedCeloForGroups(managerContract, newGroups))
          .sort((a, b) => (a.diff.lt(b.diff) ? 1 : -1))
          .map((k) => ({
            group: k.group,
            diff: k.diff.toString(),
            real: k.real.toString(),
            expected: k.expected.toString(),
          }))
      )
    );

    // transfer half from both default and allowed strategy to depositor 3 (default strategy)
    await stakedCeloContract
      .connect(depositor0)
      .transfer(depositor3.address, amountOfCeloToDeposit.div(2));
    await stakedCeloContract
      .connect(depositor1)
      .transfer(depositor3.address, amountOfCeloToDeposit.div(2));
    await stakedCeloContract
      .connect(depositor4)
      .transfer(depositor3.address, amountOfCeloToDeposit.div(2));

    console.log(
      "realVsExpectedGroups after transfer",
      JSON.stringify(
        (await getRealVsExpectedCeloForGroups(managerContract, newGroups))
          .sort((a, b) => (a.diff.lt(b.diff) ? 1 : -1))
          .map((k) => ({
            group: k.group,
            diff: formatEther(k.diff),
            real: formatEther(k.real),
            expected: formatEther(k.expected),
          }))
      )
    );
    const election = await hre.kit.contracts.getElection();

    await expectStCeloBalance(depositor0.address, amountOfCeloToDeposit.div(2));
    await expectStCeloBalance(depositor1.address, amountOfCeloToDeposit.div(2));
    await expectStCeloBalance(depositor4.address, amountOfCeloToDeposit.div(2));
    await expectStCeloBalance(depositor3.address, amountOfCeloToDeposit.div(2).mul(3));

    await rebalanceAllAndActivate();
    console.log(
      "realVsExpectedGroups after rebalance",
      JSON.stringify(
        (await getRealVsExpectedCeloForGroups(managerContract, newGroups))
          .sort((a, b) => (a.diff.lt(b.diff) ? 1 : -1))
          .map((k) => ({
            group: k.group,
            diff: formatEther(k.diff),
            real: formatEther(k.real),
            expected: formatEther(k.expected),
          }))
      )
    );

    console.log("ActivateAndVote");

    await activateAndVoteTest();
    await mineToNextEpoch(hre.web3);
    await activateAndVoteTest();
    console.log(
      "group[0] election votes",
      formatEther(
        (
          await election.getTotalVotesForGroupByAccount(groups[0].address, accountContract.address)
        ).toString()
      )
    );
    console.log("getTotalCelo", formatEther(await accountContract.getTotalCelo()));
    console.log(
      "realVsExpectedGroups after activate",
      JSON.stringify(
        (await getRealVsExpectedCeloForGroups(managerContract, newGroups))
          .sort((a, b) => (a.diff.lt(b.diff) ? 1 : -1))
          .map((k) => ({
            group: k.group,
            diff: formatEther(k.diff),
            real: formatEther(k.real),
            expected: formatEther(k.expected),
          }))
      )
    );
    await distributeAllRewards();
    console.log("getTotalCelo", formatEther(await accountContract.getTotalCelo()));
    console.log(
      "realVsExpectedGroups after rewards",
      JSON.stringify(
        (await getRealVsExpectedCeloForGroups(managerContract, newGroups))
          .sort((a, b) => (a.diff.lt(b.diff) ? 1 : -1))
          .map((k) => ({
            group: k.group,
            diff: formatEther(k.diff),
            real: formatEther(k.real),
            expected: formatEther(k.expected),
          }))
      )
    );
    console.log(
      "group[0] election votes",
      formatEther(
        (
          await election.getTotalVotesForGroupByAccount(groups[0].address, accountContract.address)
        ).toString()
      )
    );
    console.log(
      "getEligibleValidatorGroups",
      JSON.stringify(await election["contract"].methods.getEligibleValidatorGroups().call())
    );
    await rebalanceAllAndActivate();
    console.log(
      "realVsExpectedGroups after rebalance",
      JSON.stringify(
        (await getRealVsExpectedCeloForGroups(managerContract, newGroups))
          .sort((a, b) => (a.diff.lt(b.diff) ? 1 : -1))
          .map((k) => ({
            group: k.group,
            diff: formatEther(k.diff),
            real: formatEther(k.real),
            expected: formatEther(k.expected),
          }))
      )
    );
    console.log("HERE2");
    await managerContract.connect(depositor1).withdraw(amountOfCeloToDeposit.div(2));
    console.log("HERE3");
    await expectStCeloBalance(depositor1.address, 0);
    await hre.run(ACCOUNT_WITHDRAW, {
      beneficiary: depositor1.address,
      account: deployerAccountName,
      useNodeAccount: true,
    });
    const depositor1BeforeWithdrawalBalance = await depositor1.getBalance();

    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);

    await finishPendingWithdrawalForAccount(depositor1.address);

    await managerContract.connect(depositor2).deposit({ value: amountOfCeloToDeposit });
    await expectStCeloBalance(
      depositor2.address,
      await managerContract.toStakedCelo(amountOfCeloToDeposit)
    );
    const depositor2StakedCeloBalance = await stakedCeloContract.balanceOf(depositor2.address);
    expect(
      depositor2StakedCeloBalance.gt(0) && depositor2StakedCeloBalance.lt(amountOfCeloToDeposit)
    ).to.be.true;

    const depositor0StakedCeloBalance = await stakedCeloContract.balanceOf(depositor0.address);
    expect(depositor0StakedCeloBalance).to.eq(amountOfCeloToDeposit.div(2));
    const depositor1AfterWithdrawalBalance = await depositor1.getBalance();
    expect(depositor1AfterWithdrawalBalance.gt(depositor1BeforeWithdrawalBalance)).to.be.true;
  });

  async function allowStrategy(strategy: string) {
    await expect(managerContract.connect(depositor1).changeStrategy(strategy)).revertedWith(
      `GroupNotEligible("${strategy}")`
    );
    await allowStrategies(managerContract, multisigOwner0.address, [strategy]);
  }

  async function rebalanceAllAndActivate() {
    await rebalanceGroups(managerContract);
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
    expect(balance).to.eq(expectedAmount);
  }

  async function finishPendingWithdrawalForAccount(account: string) {
    const { timestamps } = await accountContract.getPendingWithdrawals(account);

    for (let i = 0; i < timestamps.length; i++) {
      const finishPendingWithdrawalForAccount = await accountContract.finishPendingWithdrawal(
        account,
        0,
        0
      );
      await finishPendingWithdrawalForAccount.wait();
    }
  }
});
