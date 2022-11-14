import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  activateAndVoteTest,
  activateValidators,
  distributeEpochRewards,
  electMinimumNumberOfValidators,
  impersonateAccount,
  mineToNextEpoch,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorAndOnlyAffiliateToGroup,
  registerValidatorGroup,
  resetNetwork,
  timeTravel,
} from "./utils";
import { Manager } from "../typechain-types/Manager";
import { StakedCelo } from "../typechain-types/StakedCelo";
import {
  GovernanceWrapper,
  Proposal,
  ProposalTransaction,
} from "@celo/contractkit/lib/wrappers/Governance";
import { Vote } from "../typechain-types/Vote";
import { BigNumber } from "ethers";

after(() => {
  hre.kit.stop();
});

describe("e2e governance vote", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let voteContract: Vote;
  let governanceWrapper: GovernanceWrapper;

  let depositor0: SignerWithAddress;
  let depositor1: SignerWithAddress;
  let voter: SignerWithAddress;

  let groups: SignerWithAddress[];
  let groupAddresses: string[];
  let activatedGroupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let stakedCeloContract: StakedCelo;

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
    [voter] = await randomSigner(parseUnits("300"));
    const accounts = await hre.kit.contracts.getAccounts();
    await accounts.createAccount().sendAndWaitForReceipt({
      from: voter.address,
    });

    groups = [];
    activatedGroupAddresses = [];
    groupAddresses = [];
    validators = [];
    validatorAddresses = [];
    for (let i = 0; i < 10; i++) {
      const [group] = await randomSigner(parseUnits("11000"));
      groups.push(group);
      if (i < 3) {
        activatedGroupAddresses.push(groups[i].address);
      }
      groupAddresses.push(groups[i].address);
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      validators.push(validator);
      validatorAddresses.push(validators[i].address);

      await registerValidatorGroup(groups[i]);
      await registerValidatorAndAddToGroupMembers(groups[i], validators[i], validatorWallet);
    }

    await electMinimumNumberOfValidators(groups, voter);
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    governanceWrapper = await hre.kit.contracts.getGovernance();
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    voteContract = await hre.ethers.getContract("Vote");
    stakedCeloContract = await hre.ethers.getContract("StakedCelo");

    const approver = await governanceWrapper.getApprover();
    impersonateAccount(approver);

    await hre.kit.sendTransaction({
      from: depositor1.address,
      to: approver,
      value: hre.web3.utils.toWei("10"),
    });

    const multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
    await activateValidators(managerContract, multisigOwner0.address, activatedGroupAddresses);
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

    await activateAndVoteTest();
    await mineToNextEpoch(hre.web3);
    await activateAndVoteTest();

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

    const proposalId = 1;
    const index = 0;
    const proposalId2 = 2;
    const index2 = 1;

    const depositor0NonVotedVotes = 100000;

    const depositor0VotingPower = await voteContract.getVoteWeight(depositor0.address);
    const depositor0VotedWeight = depositor0VotingPower.sub(depositor0NonVotedVotes);
    const depositor1VotingPower = await voteContract.getVoteWeight(depositor1.address);

    const voteProposalTx = await managerContract
      .connect(depositor1)
      .functions.voteProposal(proposalId, index, depositor1VotingPower, 0, 0);
    await voteProposalTx.wait();

    const voteProposal2Tx = await managerContract
      .connect(depositor1)
      .functions.voteProposal(proposalId2, index2, depositor1VotingPower, 0, 0);
    await voteProposal2Tx.wait();

    const voteProposal2Depositor0Tx = await managerContract
      .connect(depositor0)
      .functions.voteProposal(proposalId2, index2, depositor0VotedWeight, 0, 0);
    await voteProposal2Depositor0Tx.wait();

    const depositor1StakedCeloBalanceAfterVoting = await stakedCeloContract.balanceOf(
      depositor1.address
    );
    expect(depositor1StakedCeloBalanceAfterVoting).to.eq(0);

    const depositor1LockedStakedCeloBalance = await stakedCeloContract.lockedBalanceOf(
      depositor1.address
    );
    expect(depositor1LockedStakedCeloBalance).to.eq(amountOfCeloToDeposit);

    const voteRecord = await voteContract.getVoteRecord(proposalId);

    expect(voteRecord.proposalId.eq(proposalId)).to.be.true;

    const depositor1StCeloBalance = await stakedCeloContract.balanceOf(depositor1.address);
    const expectedVotingPower = await managerContract.toCelo(depositor1StCeloBalance);
    expect(expectedVotingPower.toString(), depositor1VotingPower.toString());
    expect(voteRecord.yesVotes).to.eq(depositor1VotingPower);

    const governanceContract = governanceWrapper["contract"];

    const totalVotesProposal1 = await governanceContract.methods.getVoteTotals(proposalId).call();
    const yesVotesProposal1 = totalVotesProposal1[0];
    expect(yesVotesProposal1).to.eq(depositor1VotingPower);

    const totalVotesProposal2 = await governanceContract.methods.getVoteTotals(proposalId2).call();
    const yesVotesProposal2 = totalVotesProposal2[0];
    expect(yesVotesProposal2).to.eq(depositor1VotingPower.add(depositor0VotedWeight));

    const voteProposal2Depositor0TxChangeVotesToNo = await managerContract
      .connect(depositor0)
      .functions.voteProposal(proposalId2, index2, 0, depositor0VotedWeight, 0);
    await voteProposal2Depositor0TxChangeVotesToNo.wait();

    const totalVotesProposal2AfterChangeToNo = await governanceContract.methods
      .getVoteTotals(proposalId2)
      .call();
    const yesVotesProposal2AfterChangeToNo = totalVotesProposal2AfterChangeToNo[0];
    const noVotesProposal2AfterChangeToNo = totalVotesProposal2AfterChangeToNo[1];
    expect(yesVotesProposal2AfterChangeToNo).to.eq(depositor1VotingPower);
    expect(noVotesProposal2AfterChangeToNo).to.eq(depositor0VotedWeight);

    await expect(
      stakedCeloContract
        .connect(depositor1)
        .transfer(managerContract.address, amountOfCeloToDeposit)
    ).revertedWith("ERC20: transfer amount exceeds balance");

    await timeTravel(stageDurations.Referendum.toNumber() + 1);

    await (await managerContract.unlockBalance(depositor1.address)).wait();

    const transferStCeloTx = await stakedCeloContract
      .connect(depositor1)
      .transfer(managerContract.address, amountOfCeloToDeposit.div(2));
    await transferStCeloTx.wait();

    const transferStCeloTx2 = await stakedCeloContract
      .connect(depositor1)
      .transfer(managerContract.address, amountOfCeloToDeposit.div(2));
    await transferStCeloTx2.wait();

    const lockedStakedCeloDepositor0 = await stakedCeloContract.lockedBalanceOf(depositor0.address);
    const lockedStakedCeloDepositor1 = await stakedCeloContract.lockedBalanceOf(depositor1.address);

    expect(lockedStakedCeloDepositor1).to.eq(BigNumber.from(0));

    const depositor0StCeloVotedWith = await managerContract.toStakedCelo(depositor0VotedWeight);
    expect(lockedStakedCeloDepositor0).to.eq(depositor0StCeloVotedWith);
  });
});
