import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { AccountsWrapper } from "@celo/contractkit/lib/wrappers/Accounts";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
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
  let accountsInstance: AccountsWrapper;
  let lockedGold: LockedGoldWrapper;
  let election: ElectionWrapper;

  let account: Account;
  let managerContract: Manager;
  let multisigContract: MultiSig;

  let depositor0: SignerWithAddress;
  let depositor1: SignerWithAddress;
  let depositor2: SignerWithAddress;
  let owner: SignerWithAddress;

  let groups: SignerWithAddress[];
  let groupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let stakedCelo: StakedCelo;

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

    accountsInstance = await hre.kit.contracts.getAccounts();
    lockedGold = await hre.kit.contracts.getLockedGold();
    election = await hre.kit.contracts.getElection();
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    account = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    managerContract = managerContract.attach(await account.manager());
    multisigContract = await hre.ethers.getContract("MultiSig");

    stakedCelo = await hre.ethers.getContract("StakedCelo");

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

    await hre.run(MULTISIG_SUBMIT_PROPOSAL, {
      destinations: destinations.join(","),
      values: values.join(","),
      payloads: payloads.join(","),
      account: multisigOwner0.address,
    });

    await hre.run(MULTISIG_EXECUTE_PROPOSAL, {
      proposalId: 0,
      account: multisigOwner0.address,
    });
  });

  it("deposit and withdraw", async () => {
    const amountOfCeloToDeposit = hre.ethers.BigNumber.from("10000000000000000");
    const rewardsGroup0 = hre.ethers.BigNumber.from("1000000000000000000");
    const rewardsGroup1 = hre.ethers.BigNumber.from("2000000000000000000");
    const rewardsGroup2 = hre.ethers.BigNumber.from("3500000000000000000");

    await managerContract.connect(depositor1).deposit({ value: amountOfCeloToDeposit });
    let stCelo = await stakedCelo.balanceOf(depositor1.address);
    expect(stCelo).to.eq(amountOfCeloToDeposit);

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

    stCelo = await stakedCelo.balanceOf(depositor1.address);
    expect(stCelo).to.eq(0);

    await hre.run(ACCOUNT_WITHDRAW, { beneficiary: depositor1.address });

    const depositorBeforeWithdrawalBalance = await depositor1.getBalance();

    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);

    for (let i = 0; i < groups.length; i++) {
      const finishPendingWithdrawal = await account.finishPendingWithdrawal(
        depositor1.address,
        0,
        0
      );
      await finishPendingWithdrawal.wait();
    }

    const depositorAfterWithdrawalBalance = await depositor1.getBalance();
    expect(depositorAfterWithdrawalBalance.gt(depositorBeforeWithdrawalBalance)).to.be.true;

    const rewardsReceived = depositorAfterWithdrawalBalance
      .sub(depositorBeforeWithdrawalBalance)
      .sub(amountOfCeloToDeposit);
    expect(rewardsReceived.eq(rewardsGroup0.add(rewardsGroup1).add(rewardsGroup2))).to.be.true;
  });
});
