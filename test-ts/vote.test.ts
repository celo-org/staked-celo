import hre, { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { StakedCelo } from "../typechain-types/StakedCelo";

import {
  activateValidators,
  ADDRESS_ZERO,
  mineToNextEpoch,
  randomSigner,
  registerValidator,
  registerValidatorGroup,
  resetNetwork,
  timeTravel,
} from "./utils";
import {
  GovernanceWrapper,
  Proposal,
  ProposalTransaction,
} from "@celo/contractkit/lib/wrappers/Governance";
import { BigNumber, BigNumberish, Signer, Transaction } from "ethers";
import manager from "../deploy/test/manager";
import { Account } from "../typechain-types/Account";
import { Manager } from "../typechain-types/Manager";
import { Vote } from "../typechain-types/Vote";
import { ACCOUNT_ACTIVATE_AND_VOTE } from "../lib/tasksNames";

enum VoteValue {
  None = 0,
  Abstain,
  No,
  Yes,
}

describe("Vote", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let voteContract: Vote;
  let governanceWrapper: GovernanceWrapper;

  let depositor0: SignerWithAddress;
  let depositor1: SignerWithAddress;

  let groups: SignerWithAddress[];
  let groupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  async function proposeNewProposal() {
    const minDeposit = await governanceWrapper.minDeposit();
    const dequeueFrequency = await governanceWrapper.dequeueFrequency();

    const ownertx: ProposalTransaction = {
      value: "0",
      to: managerContract.address,
      input: managerContract.interface.encodeFunctionData("owner"),
    };

    const proposal: Proposal = [ownertx];

    const tx = await governanceWrapper.propose(proposal, "http://www.descriptionUrl.com");
    await tx.send({ from: depositor1.address, value: minDeposit.toString() });

    await timeTravel(dequeueFrequency.toNumber() + 1);
    const dequeueProposalIfReadyTx = await governanceWrapper.dequeueProposalsIfReady();
    await dequeueProposalIfReadyTx.send({ from: depositor1.address });
  }

  async function depositAndActivate(despositor: Signer, value: BigNumberish) {
    await managerContract.connect(despositor).deposit({ value });

    await hre.run(ACCOUNT_ACTIVATE_AND_VOTE);
    await mineToNextEpoch(hre.web3);
    await hre.run(ACCOUNT_ACTIVATE_AND_VOTE);
  }

  async function checkGovernanceTotalVotes(
    proposalId: number | string,
    yesVotes: BigNumberish,
    noVotes: BigNumberish,
    abstainVotes: BigNumberish
  ) {
    const governanceContract = governanceWrapper["contract"];

    const totalVotesProposal1 = await governanceContract.methods.getVoteTotals(proposalId).call();
    const yesVotesProposal1 = totalVotesProposal1[0];
    const noVotesProposal1 = totalVotesProposal1[1];
    const abstainVotesProposal1 = totalVotesProposal1[2];
    expect(BigNumber.from(yesVotesProposal1)).to.eq(yesVotes);
    expect(BigNumber.from(noVotesProposal1)).to.eq(noVotes);
    expect(BigNumber.from(abstainVotesProposal1)).to.eq(abstainVotes);
  }

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
    voteContract = await hre.ethers.getContract("Vote");
    stakedCeloContract = await hre.ethers.getContract("StakedCelo");

    const multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
    await activateValidators(managerContract, multisigOwner0.address, groupAddresses);
  });

  describe("#getVoteWeight()", () => {
    it("should return 0 when account doesn't have any stCelo", async () => {
      const voteWeight = await voteContract.getVoteWeight(depositor0.address);
      expect(voteWeight).to.eq(0);
    });

    it("should return deposited stCelo", async () => {
      const amountOfCeloToDeposit = hre.ethers.BigNumber.from("10000000000000000");
      await managerContract.connect(depositor0).deposit({ value: amountOfCeloToDeposit });
      const voteWeight = await voteContract.getVoteWeight(depositor0.address);
      expect(voteWeight).to.eq(amountOfCeloToDeposit);
    });
  });

  describe("#setReferendumDuration()", () => {
    it("should return same as governance referendum", async () => {
      const governanceStageDurations = await governanceWrapper.stageDurations();
      const referendumDuration = await voteContract.referendumDuration();
      expect(referendumDuration).to.eq(governanceStageDurations.Referendum);
    });

    it("should return deposited stCelo", async () => {
      const newReferendumDuration = 567;
      await (await voteContract.setReferendumDuration(newReferendumDuration)).wait();
      const referendumDuration = await voteContract.referendumDuration();
      expect(referendumDuration).to.eq(newReferendumDuration);
    });
  });

  describe("#voteProposal()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;

    beforeEach(async () => {
      await proposeNewProposal();
    });

    it("should revert when account has no stCelo", async () => {
      expect(
        voteContract.voteProposal(proposal1Id, proposal1Index, [VoteValue.Yes], [1])
      ).revertedWith("No staked celo");
    });

    describe("when stCelo deposited", () => {
      const amountOfCeloToDeposit = hre.web3.utils.toWei("10");

      beforeEach(async () => {
        await depositAndActivate(depositor0, amountOfCeloToDeposit);
      });

      it("should revert when voting with more celo than account has", async () => {
        const yesVotes = hre.web3.utils.toWei("8");
        const noVotes = hre.web3.utils.toWei("2");
        const abstainVotes = hre.web3.utils.toWei("1");

        await expect(
          voteContract
            .connect(depositor0)
            .voteProposal(
              proposal1Id,
              proposal1Index,
              [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
              [yesVotes, noVotes, abstainVotes]
            )
        ).revertedWith("Not enough celo to vote");
      });

      describe("when voted", async () => {
        const yesVotes = hre.web3.utils.toWei("7");
        const noVotes = hre.web3.utils.toWei("2");
        const abstainVotes = hre.web3.utils.toWei("1");

        beforeEach(async () => {
          await voteContract
            .connect(depositor0)
            .voteProposal(
              proposal1Id,
              proposal1Index,
              [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
              [yesVotes, noVotes, abstainVotes]
            );
        });

        it("should return correct votes from governance contract", async () => {
          await checkGovernanceTotalVotes(proposal1Id, yesVotes, noVotes, abstainVotes);
        });

        it("should return correct votes when revoted", async () => {
          const yesVotesRevote = hre.web3.utils.toWei("5");
          const noVotesRevote = hre.web3.utils.toWei("3");
          const abstainVotesRevote = hre.web3.utils.toWei("1");

          await voteContract
            .connect(depositor0)
            .voteProposal(
              proposal1Id,
              proposal1Index,
              [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
              [yesVotesRevote, noVotesRevote, abstainVotesRevote]
            );

          await checkGovernanceTotalVotes(
            proposal1Id,
            yesVotesRevote,
            noVotesRevote,
            abstainVotesRevote
          );
        });
      });
    });

    describe("When voting on two proposals", () => {
      const proposal2Id = 2;
      const proposal2Index = 1;
      const proposal3Id = 3;
      const proposal3Index = 2;
      const amountOfCeloToDeposit = hre.web3.utils.toWei("10");

      const yesVotes = [hre.web3.utils.toWei("7"), hre.web3.utils.toWei("2")];
      const noVotes = [hre.web3.utils.toWei("2"), hre.web3.utils.toWei("3")];
      const abstainVotes = [hre.web3.utils.toWei("1"), hre.web3.utils.toWei("5")];

      const yesVotesDepositor1 = [hre.web3.utils.toWei("1"), hre.web3.utils.toWei("4")];
      const noVotesDepositor1 = [hre.web3.utils.toWei("2"), hre.web3.utils.toWei("5")];
      const abstainVotesDepositor1 = [hre.web3.utils.toWei("3"), hre.web3.utils.toWei("1")];

      beforeEach(async () => {
        await depositAndActivate(depositor0, amountOfCeloToDeposit);
        await depositAndActivate(depositor1, amountOfCeloToDeposit);
        await proposeNewProposal();
        await proposeNewProposal();
      });

      it("should return correct votes from governance contract", async () => {
        console.log(
          "governanceWrapper.getDequeue()",
          JSON.stringify(await governanceWrapper.getDequeue())
        );
        console.log(
          "isQueuedProposalExpired",
          await governanceWrapper.isDequeuedProposalExpired(proposal1Id)
        );
        await voteContract
          .connect(depositor0)
          .voteProposal(
            proposal2Id,
            proposal2Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotes[0], noVotes[0], abstainVotes[0]]
          );

        await voteContract
          .connect(depositor0)
          .voteProposal(
            proposal3Id,
            proposal3Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotes[1], noVotes[1], abstainVotes[1]]
          );

        await voteContract
          .connect(depositor1)
          .voteProposal(
            proposal2Id,
            proposal2Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotesDepositor1[0], noVotesDepositor1[0], abstainVotesDepositor1[0]]
          );

        await voteContract
          .connect(depositor1)
          .voteProposal(
            proposal3Id,
            proposal3Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotesDepositor1[1], noVotesDepositor1[1], abstainVotesDepositor1[1]]
          );

        await checkGovernanceTotalVotes(
          proposal2Id,
          BigNumber.from(yesVotes[0]).add(BigNumber.from(yesVotesDepositor1[0])),
          BigNumber.from(noVotes[0]).add(BigNumber.from(noVotesDepositor1[0])),
          BigNumber.from(abstainVotes[0]).add(BigNumber.from(abstainVotesDepositor1[0]))
        );

        await checkGovernanceTotalVotes(
          proposal3Id,
          BigNumber.from(yesVotes[1]).add(BigNumber.from(yesVotesDepositor1[1])),
          BigNumber.from(noVotes[1]).add(BigNumber.from(noVotesDepositor1[1])),
          BigNumber.from(abstainVotes[1]).add(BigNumber.from(abstainVotesDepositor1[1]))
        );
      });
    });
  });

  describe("#getVoteRecord()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const amountOfCeloToDeposit = hre.web3.utils.toWei("10");

    beforeEach(async () => {
      await depositAndActivate(depositor0, amountOfCeloToDeposit);
      await proposeNewProposal();
    });

    it("should return empty vote record when not voted", async () => {
      const voteRecord = await voteContract.getVoteRecord(proposal1Id);
      const proposalIdRecord = voteRecord[0];
      const yesVotesRecord = voteRecord[1];
      const noVotesRecord = voteRecord[2];
      const abstainVotesRecord = voteRecord[3];

      expect(proposalIdRecord).to.eq(0);
      expect(yesVotesRecord.toString()).to.eq("0");
      expect(noVotesRecord.toString()).to.eq("0");
      expect(abstainVotesRecord.toString()).to.eq("0");
    });

    describe("when voted", async () => {
      const yesVotes = hre.web3.utils.toWei("7");
      const noVotes = hre.web3.utils.toWei("2");
      const abstainVotes = hre.web3.utils.toWei("1");

      beforeEach(async () => {
        await voteContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotes, noVotes, abstainVotes]
          );
      });

      it("should return voted record with correct values", async () => {
        const voteRecord = await voteContract.getVoteRecord(proposal1Id);
        const proposalIdRecord = voteRecord[0];
        const yesVotesRecord = voteRecord[1];
        const noVotesRecord = voteRecord[2];
        const abstainVotesRecord = voteRecord[3];

        expect(proposalIdRecord).to.eq(proposal1Id);
        expect(yesVotesRecord.toString()).to.eq(yesVotes);
        expect(noVotesRecord.toString()).to.eq(noVotes);
        expect(abstainVotesRecord.toString()).to.eq(abstainVotes);
      });

      it("should update vote record when revoted", async () => {
        const yesVotesRevote = hre.web3.utils.toWei("5");
        const noVotesRevote = hre.web3.utils.toWei("3");
        const abstainVotesRevote = hre.web3.utils.toWei("1");

        await voteContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotesRevote, noVotesRevote, abstainVotesRevote]
          );

        const voteRecord = await voteContract.getVoteRecord(proposal1Id);
        const proposalIdRecord = voteRecord[0];
        const yesVotesRecord = voteRecord[1];
        const noVotesRecord = voteRecord[2];
        const abstainVotesRecord = voteRecord[3];

        expect(proposalIdRecord).to.eq(proposal1Id);
        expect(yesVotesRecord.toString()).to.eq(yesVotesRevote);
        expect(noVotesRecord.toString()).to.eq(noVotesRevote);
        expect(abstainVotesRecord.toString()).to.eq(abstainVotesRevote);
      });
    });
  });

  describe("#getLockedStCeloInVotingView()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const amountOfCeloToDeposit = hre.web3.utils.toWei("10");

    beforeEach(async () => {
      await depositAndActivate(depositor0, amountOfCeloToDeposit);
      await proposeNewProposal();
    });

    it("should return 0 when not voted", async () => {
      const lockedCeloInVotingView = await voteContract.getLockedStCeloInVotingView(
        depositor0.address
      );
      expect(lockedCeloInVotingView).to.eq(0);
    });

    describe("when voted", async () => {
      const yesVotes = hre.web3.utils.toWei("7");
      const noVotes = hre.web3.utils.toWei("2");
      const abstainVotes = hre.web3.utils.toWei("1");
      const totalVotes = BigNumber.from(yesVotes)
        .add(BigNumber.from(noVotes))
        .add(BigNumber.from(abstainVotes));

      beforeEach(async () => {
        await voteContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotes, noVotes, abstainVotes]
          );
      });

      it("should return locked celo", async () => {
        const lockedCeloInVotingView = await voteContract.getLockedStCeloInVotingView(
          depositor0.address
        );
        expect(lockedCeloInVotingView).to.eq(totalVotes);
      });

      it("should update locked celo when revoted", async () => {
        const yesVotesRevote = hre.web3.utils.toWei("5");
        const noVotesRevote = hre.web3.utils.toWei("3");
        const abstainVotesRevote = hre.web3.utils.toWei("1");

        const totalRevotes = BigNumber.from(yesVotesRevote)
          .add(BigNumber.from(noVotesRevote))
          .add(BigNumber.from(abstainVotesRevote));

        await voteContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotesRevote, noVotesRevote, abstainVotesRevote]
          );

        const lockedCeloInVotingView = await voteContract.getLockedStCeloInVotingView(
          depositor0.address
        );
        expect(lockedCeloInVotingView).to.eq(totalRevotes);
      });
    });
  });

  describe("#getLockedStCeloInVoting()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const amountOfCeloToDeposit = hre.web3.utils.toWei("10");

    beforeEach(async () => {
      await depositAndActivate(depositor0, amountOfCeloToDeposit);
      await proposeNewProposal();
    });

    it("should return 0 when not voted", async () => {
      const lockedCeloInVoting = await voteContract.getLockedStCeloInVoting(depositor0.address);
      const lockedCeloInVotingReceipt = await lockedCeloInVoting.wait();
      const event = lockedCeloInVotingReceipt.events?.find(
        (event) => event.event === "LockedStCeloInVoting"
      );
      expect(event?.args?.lockedCelo).to.eq(0);
    });

    describe("when voted", async () => {
      const yesVotes = hre.web3.utils.toWei("7");
      const noVotes = hre.web3.utils.toWei("2");
      const abstainVotes = hre.web3.utils.toWei("1");
      const totalVotes = BigNumber.from(yesVotes)
        .add(BigNumber.from(noVotes))
        .add(BigNumber.from(abstainVotes));

      beforeEach(async () => {
        await voteContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotes, noVotes, abstainVotes]
          );
      });

      it("should return locked celo", async () => {
        const lockedCeloInVoting = await voteContract.getLockedStCeloInVoting(depositor0.address);
        const lockedCeloInVotingReceipt = await lockedCeloInVoting.wait();
        const event = lockedCeloInVotingReceipt.events?.find(
          (event) => event.event === "LockedStCeloInVoting"
        );
        expect(event?.args?.lockedCelo).to.eq(totalVotes);
      });

      it("should update locked celo when revoted", async () => {
        const yesVotesRevote = hre.web3.utils.toWei("5");
        const noVotesRevote = hre.web3.utils.toWei("3");
        const abstainVotesRevote = hre.web3.utils.toWei("1");

        const totalRevotes = BigNumber.from(yesVotesRevote)
          .add(BigNumber.from(noVotesRevote))
          .add(BigNumber.from(abstainVotesRevote));

        await voteContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
            [yesVotesRevote, noVotesRevote, abstainVotesRevote]
          );

        const lockedCeloInVoting = await voteContract.getLockedStCeloInVoting(depositor0.address);
        const lockedCeloInVotingReceipt = await lockedCeloInVoting.wait();
        const event = lockedCeloInVotingReceipt.events?.find(
          (event) => event.event === "LockedStCeloInVoting"
        );
        expect(event?.args?.lockedCelo).to.eq(totalRevotes);
      });
    });
  });

  describe("#revokeVotes()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const amountOfCeloToDeposit = hre.web3.utils.toWei("10");

    it("should revert when account has no stCelo", async () => {
      expect(voteContract.revokeVotes(proposal1Id, proposal1Index)).revertedWith("No staked celo");
    });

    describe("When deposited", async () => {
      beforeEach(async () => {
        await depositAndActivate(depositor0, amountOfCeloToDeposit);
        await proposeNewProposal();
      });

      describe("when voted", async () => {
        const yesVotes = hre.web3.utils.toWei("7");
        const noVotes = hre.web3.utils.toWei("2");
        const abstainVotes = hre.web3.utils.toWei("1");

        beforeEach(async () => {
          await voteContract
            .connect(depositor0)
            .voteProposal(
              proposal1Id,
              proposal1Index,
              [VoteValue.Yes, VoteValue.No, VoteValue.Abstain],
              [yesVotes, noVotes, abstainVotes]
            );
        });

        it("should return voted record with correct values", async () => {
          const voteRecord = await voteContract
            .connect(depositor0)
            .revokeVotes(proposal1Id, proposal1Index);
          await checkGovernanceTotalVotes(proposal1Id, 0, 0, 0);
        });
      });
    });
  });
});
