import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  activateValidators,
  distributeEpochRewards,
  impersonateAccount,
  LOCKED_GOLD_UNLOCKING_PERIOD,
  mineToNextEpoch,
  randomSigner,
  registerValidator,
  registerValidatorGroup,
  resetNetwork,
  timeTravel,
} from "./utils";
import { Manager } from "../typechain-types/Manager";
import { ACCOUNT_ACTIVATE_AND_VOTE, ACCOUNT_WITHDRAW } from "../lib/tasksNames";
import { StakedCelo } from "../typechain-types/StakedCelo";
import {
  GovernanceWrapper,
  Proposal,
  ProposalTransaction,
} from "@celo/contractkit/lib/wrappers/Governance";

after(() => {
  hre.kit.stop();
});

interface Transaction {
  value: number;
  destination: string;
  data: Buffer;
}

enum VoteValue {
  None = 0,
  Abstain,
  No,
  Yes,
}

describe("e2e governance vote", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let governanceWrapper: GovernanceWrapper;

  // deposits CELO, receives stCELO, but never withdraws it
  let depositor0: SignerWithAddress;
  // deposits CELO, receives stCELO, withdraws stCELO including rewards
  let depositor1: SignerWithAddress;
  // deposits CELO after rewards are distributed -> depositor will receive less stCELO than deposited CELO
  let depositor2: SignerWithAddress;

  let transactionSuccess1: Transaction;

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
      VALIDATOR_GROUPS: "",
    };

    [depositor0] = await randomSigner(parseUnits("300"));
    [depositor1] = await randomSigner(parseUnits("300"));
    [depositor2] = await randomSigner(parseUnits("300"));

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
    governanceWrapper = await hre.kit.contracts.getGovernance();
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    stakedCeloContract = await hre.ethers.getContract("StakedCelo");

    // const minDeposit = await governanceWrapper.minDeposit();

    // const ownertx: ProposalTransaction = {
    //   value: "0",
    //   to: managerContract.address,
    //   input: managerContract.interface.encodeFunctionData("owner"),
    // };

    // const ownertx2: ProposalTransaction = {
    //   value: "0",
    //   to: accountContract.address,
    //   input: accountContract.interface.encodeFunctionData("owner"),
    // };

    // const proposal: Proposal = [ownertx];
    // const proposal2: Proposal = [ownertx2];

    // const dequeueFrequency = await governanceWrapper.dequeueFrequency();

    // await timeTravel(dequeueFrequency.toNumber() + 1);

    // const tx = await governanceWrapper.propose(proposal, "http://www.descriptionUrl.com");
    // await tx.send({ from: depositor1.address, value: minDeposit.toString() });

    // await timeTravel(dequeueFrequency.toNumber() + 1)

    // const tx2 = await governanceWrapper.propose(proposal2, "http://www.descriptionUrl2.com");
    // await tx2.send({ from: depositor1.address, value: minDeposit.toString() });

    // await timeTravel(dequeueFrequency.toNumber() + 1)

    // const tx3 = await governanceWrapper.propose(proposal2, "http://www.descriptionUrl2.com");
    // await tx3.send({ from: depositor1.address, value: minDeposit.toString() });

    // await timeTravel(dequeueFrequency.toNumber() + 1);
    // const dequeueProposalIfReadyTx = await governanceWrapper.dequeueProposalsIfReady();
    // await dequeueProposalIfReadyTx.send({ from: depositor1.address });
    const approver = await governanceWrapper.getApprover();
    impersonateAccount(approver);

    await hre.kit.sendTransaction({
      from: depositor1.address,
      to: approver,
      value: hre.web3.utils.toWei("10"),
    });
    // const approveTx = await governanceWrapper.approve(1);
    // await approveTx.send({ from: approver });

    // const stageDurations = await governanceWrapper.stageDurations();
    // await timeTravel(stageDurations.Approval.toNumber());

    const multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
    await activateValidators(managerContract, multisigOwner0.address, groupAddresses);
  });

  it("vote proposal", async () => {
    const stageDurations = await governanceWrapper.stageDurations();

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

    const minDeposit = await governanceWrapper.minDeposit();

    const ownertx: ProposalTransaction = {
      value: "0",
      to: managerContract.address,
      input: managerContract.interface.encodeFunctionData("owner"),
    };

    const ownertx2: ProposalTransaction = {
      value: "0",
      to: accountContract.address,
      input: accountContract.interface.encodeFunctionData("owner"),
    };

    const proposal: Proposal = [ownertx];
    const proposal2: Proposal = [ownertx2];

    const dequeueFrequency = await governanceWrapper.dequeueFrequency();

    await timeTravel(dequeueFrequency.toNumber() + 1);

    const tx = await governanceWrapper.propose(proposal, "http://www.descriptionUrl.com");
    await tx.send({ from: depositor1.address, value: minDeposit.toString() });

    await timeTravel(dequeueFrequency.toNumber() + 1);

    const tx2 = await governanceWrapper.propose(proposal2, "http://www.descriptionUrl2.com");
    await tx2.send({ from: depositor1.address, value: minDeposit.toString() });

    await timeTravel(dequeueFrequency.toNumber() + 1);

    const tx3 = await governanceWrapper.propose(proposal2, "http://www.descriptionUrl2.com");
    await tx3.send({ from: depositor1.address, value: minDeposit.toString() });

    await timeTravel(dequeueFrequency.toNumber() + 1);
    const dequeueProposalIfReadyTx = await governanceWrapper.dequeueProposalsIfReady();
    await dequeueProposalIfReadyTx.send({ from: depositor1.address });

    // const withdrawStakedCelo = await managerContract
    //   .connect(depositor1)
    //   .withdraw(amountOfCeloToDeposit);
    // await withdrawStakedCelo.wait();

    // depositor1StakedCeloBalance = await stakedCeloContract.balanceOf(depositor1.address);
    // expect(depositor1StakedCeloBalance).to.eq(0);

    // await hre.run(ACCOUNT_WITHDRAW, { beneficiary: depositor1.address });

    // const depositor1BeforeWithdrawalBalance = await depositor1.getBalance();

    const proposalId = 1;
    const index = 0;
    const proposalId2 = 1;
    const index2 = 0;

    const depositor1VotingPower = await managerContract.getVoteWeight(depositor1.address);

    const voteProposalTx = await managerContract
      .connect(depositor1)
      .functions.voteProposal(proposalId, index, [VoteValue.Yes], [depositor1VotingPower]);
    const voteProposalReceipt = await voteProposalTx.wait();

    const voteProposal2Tx = await managerContract
      .connect(depositor1)
      .functions.voteProposal(proposalId2, index2, [VoteValue.Yes], [depositor1VotingPower]);
    await voteProposal2Tx.wait();

    const depositor1StakedCeloBalanceAfterVoting = await stakedCeloContract.balanceOf(
      depositor1.address
    );
    expect(depositor1StakedCeloBalanceAfterVoting).to.eq(amountOfCeloToDeposit);

    const depositor1LockedStakedCeloBalance = await stakedCeloContract.lockedBalanceOf(
      depositor1.address
    );
    expect(depositor1LockedStakedCeloBalance).to.eq(amountOfCeloToDeposit);

    const voteRecord = await managerContract.getVoteRecord(proposalId);

    expect(voteRecord.proposalId.eq(proposalId)).to.be.true;
    const expectedVotingPower = rewardsGroup0
      .add(rewardsGroup1)
      .add(rewardsGroup2)
      .div(2)
      .add(amountOfCeloToDeposit);
    expect(expectedVotingPower).to.eq(depositor1VotingPower);
    expect(voteRecord.yesVotes).to.eq(depositor1VotingPower);

    await expect(
      stakedCeloContract
        .connect(depositor1)
        .transfer(managerContract.address, amountOfCeloToDeposit)
    ).revertedWith("Not enough stCelo");

    await timeTravel(stageDurations.Referendum.toNumber() + 1);

    const unlockReceipt = await (
      await stakedCeloContract.connect(depositor1).unlockBalance(depositor1.address)
    ).wait();

    const transferStCeloTx = await stakedCeloContract
      .connect(depositor1)
      .transfer(managerContract.address, amountOfCeloToDeposit.div(2));
    const receipt1 = await transferStCeloTx.wait();

    const transferStCeloTx2 = await stakedCeloContract
      .connect(depositor1)
      .transfer(managerContract.address, amountOfCeloToDeposit.div(2));
    const receipt2 = await transferStCeloTx2.wait();

    // const unlockStakedCeloTx = await managerContract.unlockStCelo(amountOfCeloToDeposit);
    // await unlockStakedCeloTx.wait()

    // const depositor1StakedCeloBalanceAfterVotingFinished = await stakedCeloContract.balanceOf(depositor1.address);
    // expect(depositor1StakedCeloBalanceAfterVotingFinished).to.eq(amountOfCeloToDeposit);

    // await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);

    // const { timestamps } = await accountContract.getPendingWithdrawals(depositor1.address);

    // for (let i = 0; i < timestamps.length; i++) {
    //   const finishPendingWithdrawal = await accountContract.finishPendingWithdrawal(
    //     depositor1.address,
    //     0,
    //     0
    //   );
    //   await finishPendingWithdrawal.wait();
    // }

    // await managerContract.connect(depositor2).deposit({ value: amountOfCeloToDeposit });
    // const depositor2StakedCeloBalance = await stakedCeloContract.balanceOf(depositor2.address);
    // expect(
    //   depositor2StakedCeloBalance.gt(0) && depositor2StakedCeloBalance.lt(amountOfCeloToDeposit)
    // ).to.be.true;

    // const depositor0StakedCeloBalance = await stakedCeloContract.balanceOf(depositor0.address);
    // expect(depositor0StakedCeloBalance).to.eq(amountOfCeloToDeposit);
    // const depositor1AfterWithdrawalBalance = await depositor1.getBalance();
    // expect(depositor1AfterWithdrawalBalance.gt(depositor1BeforeWithdrawalBalance)).to.be.true;

    // const rewardsReceived = depositor1AfterWithdrawalBalance
    //   .sub(depositor1BeforeWithdrawalBalance)
    //   .sub(amountOfCeloToDeposit);

    // expect(rewardsReceived.eq(rewardsGroup0.add(rewardsGroup1).add(rewardsGroup2).div(2))).to.be
    //   .true;
  });
});
