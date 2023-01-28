import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { formatEther, parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { ACCOUNT_REVOKE, ACCOUNT_WITHDRAW } from "../lib/tasksNames";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import { StakedCelo } from "../typechain-types/StakedCelo";
import {
  activateAndVoteTest,
  activateValidators,
  distributeEpochRewards,
  electMockValidatorGroupsAndUpdate,
  LOCKED_GOLD_UNLOCKING_PERIOD,
  mineToNextEpoch,
  randomSigner,
  rebalanceDefaultGroups,
  rebalanceGroups,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  resetNetwork,
  timeTravel,
  upgradeToMockGroupHealthE2E,
} from "./utils";

after(() => {
  hre.kit.stop();
});

describe("e2e", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let defaultStrategyContract: DefaultStrategy;
  let groupHealthContract: MockGroupHealth;
  let specificGroupStrategyContract: SpecificGroupStrategy;

  const deployerAccountName = "deployer";
  // deposits CELO, receives stCELO, but never withdraws it
  let depositor0: SignerWithAddress;
  // deposits CELO, receives stCELO, withdraws stCELO including rewards
  let depositor1: SignerWithAddress;
  // deposits CELO after rewards are distributed -> depositor will receive less stCELO than deposited CELO
  let depositor2: SignerWithAddress;
  let voter: SignerWithAddress;

  let groups: SignerWithAddress[];
  let activatedGroupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let stakedCeloContract: StakedCelo;

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
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    stakedCeloContract = await hre.ethers.getContract("StakedCelo");
    groupHealthContract = await hre.ethers.getContract("GroupHealth");
    defaultStrategyContract = await hre.ethers.getContract("DefaultStrategy");
    specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");

    const multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");

    groupHealthContract = await upgradeToMockGroupHealthE2E(
      multisigOwner0,
      groupHealthContract as unknown as GroupHealth
    );
    const validatorWrapper = await hre.kit.contracts.getValidators();
    await electMockValidatorGroupsAndUpdate(
      validatorWrapper,
      groupHealthContract,
      activatedGroupAddresses
    );

    await activateValidators(
      defaultStrategyContract,
      groupHealthContract as unknown as GroupHealth,
      multisigOwner0.address,
      activatedGroupAddresses
    );
  });

  const rewardsGroup0 = hre.ethers.BigNumber.from(parseUnits("100"));
  const rewardsGroup1 = hre.ethers.BigNumber.from(parseUnits("2"));
  const rewardsGroup2 = hre.ethers.BigNumber.from(parseUnits("3.5"));

  it("deposit and withdraw", async () => {
    const amountOfCeloToDeposit = hre.ethers.BigNumber.from(parseUnits("0.01"));
    for (let i = 0; i < 3; i++) {
      console.log(`group[${i}] ${groups[i].address}`);
    }
    await managerContract.connect(depositor0).deposit({ value: amountOfCeloToDeposit });
    await managerContract.connect(depositor1).deposit({ value: amountOfCeloToDeposit });

    expect(await stakedCeloContract.balanceOf(depositor1.address)).to.eq(amountOfCeloToDeposit);

    await activateAndVoteTest();
    await mineToNextEpoch(hre.web3);
    await activateAndVoteTest();

    await distributeAllRewards();
    await rebalanceDefaultGroups(defaultStrategyContract);
    await rebalanceGroups(managerContract, specificGroupStrategyContract, defaultStrategyContract);
    await hre.run(ACCOUNT_REVOKE, {
      account: deployerAccountName,
      useNodeAccount: true,
      logLevel: "info",
    });
    await activateAndVoteTest();

    const election = await hre.kit.contracts.getElection();
    const eligableGroups = election.getEligibleValidatorGroupsVotes();
    console.log("eligableGroups", JSON.stringify(eligableGroups));
    console.log("group 0", groups[0].address);
    for (let i = 0; i < 3; i++) {
      const votesForGroupByAccount = await election.getTotalVotesForGroupByAccount(
        groups[i].address,
        accountContract.address
      );
      console.log("votesForGroupByAccount", i, formatEther(votesForGroupByAccount.toString()));
    }

    await managerContract.connect(depositor1).withdraw(amountOfCeloToDeposit);
    expect(await stakedCeloContract.balanceOf(depositor1.address)).to.eq(0);

    await hre.run(ACCOUNT_WITHDRAW, {
      beneficiary: depositor1.address,
      account: deployerAccountName,
      useNodeAccount: true,
    });

    const depositor1BeforeWithdrawalBalance = await depositor1.getBalance();

    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);

    await finishPendingWithdrawals(depositor1.address);

    await managerContract.connect(depositor2).deposit({ value: amountOfCeloToDeposit });

    expect(await stakedCeloContract.balanceOf(depositor2.address)).to.eq(
      await managerContract.toStakedCelo(amountOfCeloToDeposit)
    );

    expect(await stakedCeloContract.balanceOf(depositor0.address)).to.eq(amountOfCeloToDeposit);

    const depositor1AfterWithdrawalBalance = await depositor1.getBalance();
    expect(depositor1AfterWithdrawalBalance.gt(depositor1BeforeWithdrawalBalance)).to.be.true;

    const rewardsReceived = depositor1AfterWithdrawalBalance
      .sub(depositor1BeforeWithdrawalBalance)
      .sub(amountOfCeloToDeposit);

    expect(rewardsReceived).to.deep.eq(rewardsGroup0.add(rewardsGroup1).add(rewardsGroup2).div(2));
  });

  async function distributeAllRewards() {
    await distributeEpochRewards(groups[1].address, rewardsGroup0.toString());
    await distributeEpochRewards(groups[1].address, rewardsGroup1.toString());
    await distributeEpochRewards(groups[2].address, rewardsGroup2.toString());
  }

  async function finishPendingWithdrawals(address: string) {
    const { timestamps } = await accountContract.getPendingWithdrawals(address);

    for (let i = 0; i < timestamps.length; i++) {
      await accountContract.finishPendingWithdrawal(address, 0, 0);
    }
  }
});
