import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  distributeEpochRewards,
  LOCKED_GOLD_UNLOCKING_PERIOD,
  mineToNextEpoch,
  randomSigner,
  registerValidator,
  registerValidatorGroup,
  resetNetwork,
  submitAndExecuteProposal,
  timeTravel,
} from "./utils";
import { Manager } from "../typechain-types/Manager";
import {
  ACCOUNT_ACTIVATE_AND_VOTE,
  ACCOUNT_WITHDRAW,
  MULTISIG_EXECUTE_PROPOSAL,
  MULTISIG_SUBMIT_PROPOSAL,
} from "../lib/tasksNames";
import { StakedCelo } from "../typechain-types/StakedCelo";
import { MultiSig } from "../typechain-types/MultiSig";

after(() => {
  hre.kit.stop();
});

describe("e2e", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let multisigContract: MultiSig;

  // deposits CELO, receives stCELO, but never withdraws it
  let depositor0: SignerWithAddress;
  // deposits CELO, receives stCELO, withdraws stCELO including rewards
  let depositor1: SignerWithAddress;
  // deposits CELO after rewards are distributed -> depositor will receive less stCELO than deposited CELO
  let depositor2: SignerWithAddress;

  let owner: SignerWithAddress;

  let groups: SignerWithAddress[];
  let groupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let stakedCeloContract: StakedCelo;

  before(async () => {
    await resetNetwork();

    process.env = {
      ...process.env,
      TIME_LOCK_MIN_DELAY: "1",
      TIME_LOCK_DELAY: "1",
      MULTISIG_REQUIRED_CONFIRMATIONS: "1",
    };

    [depositor0] = await randomSigner(parseUnits("300"));
    [depositor1] = await randomSigner(parseUnits("300"));
    [depositor2] = await randomSigner(parseUnits("300"));
    [owner] = await randomSigner(parseUnits("100"));

    groups = [];
    groupAddresses = [];
    validators = [];
    validatorAddresses = [];
    for (let i = 0; i < 3; i++) {
      const [group] = await randomSigner(parseUnits("11000"));
      groups.push(group);
      groupAddresses.push(groups[i].address);
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      validators.push(validator);
      validatorAddresses.push(validators[i].address);

      await registerValidatorGroup(groups[i]);
      await registerValidator(groups[i], validators[i], validatorWallet);
    }
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    managerContract = managerContract.attach(await accountContract.manager());
    multisigContract = await hre.ethers.getContract("MultiSig");
    stakedCeloContract = await hre.ethers.getContract("StakedCelo");

    const multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");

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
    await submitAndExecuteProposal(multisigOwner0.address, destinations, values, payloads);
  });

  it("deposit and withdraw", async () => {
    const amountOfCeloToDeposit = hre.ethers.BigNumber.from("10000000000000000");
    const rewardsGroup0 = hre.ethers.BigNumber.from("1000000000000000000");
    const rewardsGroup1 = hre.ethers.BigNumber.from("2000000000000000000");
    const rewardsGroup2 = hre.ethers.BigNumber.from("3500000000000000000");

    await managerContract.connect(depositor0).deposit({ value: amountOfCeloToDeposit });
    await managerContract.connect(depositor1).deposit({ value: amountOfCeloToDeposit });
    let depositor1StakedCeloBalance = await stakedCeloContract.balanceOf(depositor1.address);
    expect(depositor1StakedCeloBalance).to.eq(amountOfCeloToDeposit);

    await hre.run(ACCOUNT_ACTIVATE_AND_VOTE);
    await mineToNextEpoch(hre.web3);
    await hre.run(ACCOUNT_ACTIVATE_AND_VOTE);

    await distributeEpochRewards(groups[0].address, rewardsGroup0.toString());
    await distributeEpochRewards(groups[1].address, rewardsGroup1.toString());
    await distributeEpochRewards(groups[2].address, rewardsGroup2.toString());

    const withdrawStakedCelo = await managerContract
      .connect(depositor1)
      .withdraw(amountOfCeloToDeposit);
    await withdrawStakedCelo.wait();

    depositor1StakedCeloBalance = await stakedCeloContract.balanceOf(depositor1.address);
    expect(depositor1StakedCeloBalance).to.eq(0);

    await hre.run(ACCOUNT_WITHDRAW, { beneficiary: depositor1.address });

    const depositor1BeforeWithdrawalBalance = await depositor1.getBalance();

    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);

    const { timestamps } = await accountContract.getPendingWithdrawals(depositor1.address);

    for (let i = 0; i < timestamps.length; i++) {
      const finishPendingWithdrawal = await accountContract.finishPendingWithdrawal(
        depositor1.address,
        0,
        0
      );
      await finishPendingWithdrawal.wait();
    }

    await managerContract.connect(depositor2).deposit({ value: amountOfCeloToDeposit });
    const depositor2StakedCeloBalance = await stakedCeloContract.balanceOf(depositor2.address);
    expect(
      depositor2StakedCeloBalance.gt(0) && depositor2StakedCeloBalance.lt(amountOfCeloToDeposit)
    ).to.be.true;

    const depositor0StakedCeloBalance = await stakedCeloContract.balanceOf(depositor0.address);
    expect(depositor0StakedCeloBalance).to.eq(amountOfCeloToDeposit);
    const depositor1AfterWithdrawalBalance = await depositor1.getBalance();
    expect(depositor1AfterWithdrawalBalance.gt(depositor1BeforeWithdrawalBalance)).to.be.true;

    const rewardsReceived = depositor1AfterWithdrawalBalance
      .sub(depositor1BeforeWithdrawalBalance)
      .sub(amountOfCeloToDeposit);

    expect(rewardsReceived.eq(rewardsGroup0.add(rewardsGroup1).add(rewardsGroup2).div(2))).to.be
      .true;
  });
});
