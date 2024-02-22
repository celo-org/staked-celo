import {
  GovernanceWrapper,
  Proposal,
  ProposalTransaction,
} from "@celo/contractkit/lib/wrappers/Governance";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { Manager } from "../typechain-types/Manager";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { Vote } from "../typechain-types/Vote";
import {
  ADDRESS_ZERO,
  electMockValidatorGroupsAndUpdate,
  getImpersonatedSigner,
  mineToNextEpoch,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  resetNetwork,
  setGovernanceConcurrentProposals,
  timeTravel,
} from "./utils";

// eslint-disable-next-line no-unused-vars, @typescript-eslint/no-explicit-any
describe("Vote", async function (this: any) {
  this.timeout(0); // Disable test timeout
  let managerContract: Manager;
  let groupHealthContract: MockGroupHealth;
  let voteContract: Vote;
  let governanceWrapper: GovernanceWrapper;
  let defaultStrategyContract: DefaultStrategy;
  let account: Account;

  let owner: SignerWithAddress;
  let depositor0: SignerWithAddress;
  let depositor1: SignerWithAddress;
  let voter: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;
  let nonOwner: SignerWithAddress;
  let pauser: SignerWithAddress;

  let groups: SignerWithAddress[];
  let activatedGroupAddresses: string[];
  let groupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  async function proposeNewProposal(dequeue = true) {
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

    if (dequeue) {
      await timeTravel(dequeueFrequency.toNumber() + 1);
      const dequeueProposalIfReadyTx = await governanceWrapper.dequeueProposalsIfReady();
      await dequeueProposalIfReadyTx.send({ from: depositor1.address });
    }
  }

  async function depositAndActivate(depositor: Signer, value: BigNumberish) {
    await managerContract.connect(depositor).deposit({ value });

    const electionWrapper = await hre.kit.contracts.getElection();
    for (let i = 0; i < activatedGroupAddresses.length; i++) {
      const group = activatedGroupAddresses[i];
      const scheduledVotes = await account.scheduledVotesForGroup(group);
      const { lesser, greater } = await electionWrapper.findLesserAndGreaterAfterVote(
        group,
        // @ts-ignore: BigNumber types library conflict.
        scheduledVotes.toString()
      );
      await account.connect(depositor).activateAndVote(activatedGroupAddresses[i], lesser, greater);
    }

    await mineToNextEpoch(hre.web3);

    for (let i = 0; i < activatedGroupAddresses.length; i++) {
      await account
        .connect(depositor)
        .activateAndVote(activatedGroupAddresses[i], ADDRESS_ZERO, ADDRESS_ZERO);
    }
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
    try {
      await resetNetwork();

      process.env = {
        ...process.env,
        TIME_LOCK_MIN_DELAY: "1",
        TIME_LOCK_DELAY: "1",
        MULTISIG_REQUIRED_CONFIRMATIONS: "1",
        VALIDATOR_GROUPS: "",
      };

      owner = await hre.ethers.getNamedSigner("owner");
      [depositor0] = await randomSigner(parseUnits("300"));
      [depositor1] = await randomSigner(parseUnits("300"));
      [nonStakedCelo] = await randomSigner(parseUnits("100"));
      [nonOwner] = await randomSigner(parseUnits("100"));
      [nonAccount] = await randomSigner(parseUnits("100"));
      [voter] = await randomSigner(parseUnits("300"));
      pauser = owner;

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
    } catch (error) {
      console.error(error);
    }
  });

  beforeEach(async () => {
    await hre.deployments.fixture("TestVote");
    governanceWrapper = await hre.kit.contracts.getGovernance();
    managerContract = await hre.ethers.getContract("Manager");
    groupHealthContract = await hre.ethers.getContract("MockGroupHealth");
    voteContract = await hre.ethers.getContract("Vote");
    defaultStrategyContract = await hre.ethers.getContract("MockDefaultStrategy");
    account = await hre.ethers.getContract("Account");

    await voteContract.connect(owner).setPauser();

    const specificGroupStrategy = await hre.ethers.getContract("SpecificGroupStrategy");
    const stakedCelo = await hre.ethers.getContract("StakedCelo");

    await defaultStrategyContract
      .connect(owner)
      .setDependencies(account.address, groupHealthContract.address, specificGroupStrategy.address);
    await managerContract
      .connect(owner)
      .setDependencies(
        stakedCelo.address,
        account.address,
        voteContract.address,
        groupHealthContract.address,
        specificGroupStrategy.address,
        defaultStrategyContract.address
      );
    await voteContract.connect(owner).setDependencies(stakedCelo.address, account.address);

    const validatorWrapper = await hre.kit.contracts.getValidators();

    await electMockValidatorGroupsAndUpdate(
      validatorWrapper,
      groupHealthContract,
      activatedGroupAddresses
    );

    let previousKey = ADDRESS_ZERO;
    for (let i = 0; i < activatedGroupAddresses.length; i++) {
      await defaultStrategyContract
        .connect(owner)
        .activateGroup(activatedGroupAddresses[i], ADDRESS_ZERO, previousKey);
      previousKey = activatedGroupAddresses[i];
    }
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

  describe("#getReferendumDuration()", () => {
    it("should return same as governance referendum", async () => {
      const governanceStageDurations = await governanceWrapper.stageDurations();
      const referendumDuration = await voteContract.getReferendumDuration();
      expect(referendumDuration.toString()).to.eq(governanceStageDurations.Referendum.toString());
    });
  });

  describe("#voteProposal()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;

    beforeEach(async () => {
      await proposeNewProposal();
    });

    it("should revert when account has no stCelo", async () => {
      await expect(
        managerContract.connect(depositor0).voteProposal(proposal1Id, proposal1Index, 1, 0, 0)
      ).revertedWith(`NoStakedCelo("${depositor0.address}")`);
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
          managerContract
            .connect(depositor0)
            .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes)
        ).revertedWith(`NotEnoughStakedCelo("${depositor0.address}")`);
      });

      it("should revert when voting for non existing proposal", async () => {
        const yesVotes = hre.web3.utils.toWei("7");
        const noVotes = hre.web3.utils.toWei("2");
        const abstainVotes = hre.web3.utils.toWei("1");

        await expect(
          managerContract
            .connect(depositor0)
            .voteProposal(100, proposal1Index, yesVotes, noVotes, abstainVotes)
        ).revertedWith("Proposal not dequeued");
      });

      describe("when voted", async () => {
        const yesVotes = hre.web3.utils.toWei("7");
        const noVotes = hre.web3.utils.toWei("2");
        const abstainVotes = hre.web3.utils.toWei("1");

        beforeEach(async () => {
          await managerContract
            .connect(depositor0)
            .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes);
        });

        it("should return correct votes from governance contract", async () => {
          await checkGovernanceTotalVotes(proposal1Id, yesVotes, noVotes, abstainVotes);
        });

        it("should return correct votes when revoted", async () => {
          const yesVotesRevote = hre.web3.utils.toWei("5");
          const noVotesRevote = hre.web3.utils.toWei("3");
          const abstainVotesRevote = hre.web3.utils.toWei("1");

          await managerContract
            .connect(depositor0)
            .voteProposal(
              proposal1Id,
              proposal1Index,
              yesVotesRevote,
              noVotesRevote,
              abstainVotesRevote
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

      const yesVotes = [hre.web3.utils.toWei("6"), hre.web3.utils.toWei("2")];
      const noVotes = [hre.web3.utils.toWei("2"), hre.web3.utils.toWei("3")];
      const abstainVotes = [hre.web3.utils.toWei("1"), hre.web3.utils.toWei("4")];

      const yesVotesDepositor1 = [hre.web3.utils.toWei("1"), hre.web3.utils.toWei("4")];
      const noVotesDepositor1 = [hre.web3.utils.toWei("2"), hre.web3.utils.toWei("3")];
      const abstainVotesDepositor1 = [hre.web3.utils.toWei("3"), hre.web3.utils.toWei("1")];

      beforeEach(async () => {
        await depositAndActivate(depositor0, amountOfCeloToDeposit);
        await depositAndActivate(depositor1, amountOfCeloToDeposit);
        await proposeNewProposal();
        await proposeNewProposal();
      });

      it("should return correct votes from governance contract", async () => {
        await managerContract
          .connect(depositor0)
          .voteProposal(proposal2Id, proposal2Index, yesVotes[0], noVotes[0], abstainVotes[0]);

        await managerContract
          .connect(depositor0)
          .voteProposal(proposal3Id, proposal3Index, yesVotes[1], noVotes[1], abstainVotes[1]);

        await managerContract
          .connect(depositor1)
          .voteProposal(
            proposal2Id,
            proposal2Index,
            yesVotesDepositor1[0],
            noVotesDepositor1[0],
            abstainVotesDepositor1[0]
          );

        await managerContract
          .connect(depositor1)
          .voteProposal(
            proposal3Id,
            proposal3Index,
            yesVotesDepositor1[1],
            noVotesDepositor1[1],
            abstainVotesDepositor1[1]
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
        await managerContract
          .connect(depositor0)
          .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes);
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

        await managerContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            yesVotesRevote,
            noVotesRevote,
            abstainVotesRevote
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

  describe("#getLockedStCeloInVoting()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const amountOfCeloToDeposit = hre.web3.utils.toWei("10");

    beforeEach(async () => {
      await depositAndActivate(depositor0, amountOfCeloToDeposit);
      await proposeNewProposal();
    });

    it("should return 0 when not voted", async () => {
      const lockedCeloInVotingView = await voteContract.getLockedStCeloInVoting(depositor0.address);
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
        await managerContract
          .connect(depositor0)
          .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes);
      });

      it("should return locked celo", async () => {
        const lockedCeloInVotingView = await voteContract.getLockedStCeloInVoting(
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

        await managerContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            yesVotesRevote,
            noVotesRevote,
            abstainVotesRevote
          );

        const lockedCeloInVotingView = await voteContract.getLockedStCeloInVoting(
          depositor0.address
        );
        expect(lockedCeloInVotingView).to.eq(totalRevotes);
      });
    });
  });

  describe("#updateHistoryAndReturnLockedStCeloInVoting()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const amountOfCeloToDeposit = hre.web3.utils.toWei("10");
    let managerSigner: SignerWithAddress;
    beforeEach(async () => {
      await depositAndActivate(depositor0, amountOfCeloToDeposit);
      await proposeNewProposal();
      managerSigner = await getImpersonatedSigner(managerContract.address, parseUnits("100"));
    });

    it("should return 0 when not voted", async () => {
      await expect(
        voteContract
          .connect(managerSigner)
          .updateHistoryAndReturnLockedStCeloInVoting(depositor0.address)
      )
        .to.emit(voteContract, "LockedStCeloInVoting")
        .withArgs(depositor0.address, hre.ethers.BigNumber.from(0));
    });

    describe("when voted", async () => {
      const yesVotes = hre.web3.utils.toWei("7");
      const noVotes = hre.web3.utils.toWei("2");
      const abstainVotes = hre.web3.utils.toWei("1");
      const totalVotes = BigNumber.from(yesVotes)
        .add(BigNumber.from(noVotes))
        .add(BigNumber.from(abstainVotes));

      beforeEach(async () => {
        await managerContract
          .connect(depositor0)
          .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes);
      });

      it("should return locked celo", async () => {
        await expect(
          voteContract
            .connect(managerSigner)
            .updateHistoryAndReturnLockedStCeloInVoting(depositor0.address)
        )
          .to.emit(voteContract, "LockedStCeloInVoting")
          .withArgs(depositor0.address, totalVotes);
      });

      it("should return locked celo when voting on maximum number of proposals", async () => {
        const currentMainnetConcurrentProposals = 3 * 7; // 3 proposals per day * week
        setGovernanceConcurrentProposals(currentMainnetConcurrentProposals);
        for (let i = 0; i < currentMainnetConcurrentProposals; i++) {
          await proposeNewProposal(i === currentMainnetConcurrentProposals - 1); // dequeue only after the last proposal
        }

        for (let i = 0; i < currentMainnetConcurrentProposals; i++) {
          await managerContract
            .connect(depositor0)
            .voteProposal(i + 1, i, yesVotes, noVotes, abstainVotes);
        }

        await expect(
          voteContract
            .connect(managerSigner)
            .updateHistoryAndReturnLockedStCeloInVoting(depositor0.address)
        )
          .to.emit(voteContract, "LockedStCeloInVoting")
          .withArgs(depositor0.address, totalVotes);
      });

      it("should update locked celo when revoted", async () => {
        const yesVotesRevote = hre.web3.utils.toWei("5");
        const noVotesRevote = hre.web3.utils.toWei("3");
        const abstainVotesRevote = hre.web3.utils.toWei("1");

        const totalRevotes = BigNumber.from(yesVotesRevote)
          .add(BigNumber.from(noVotesRevote))
          .add(BigNumber.from(abstainVotesRevote));

        await managerContract
          .connect(depositor0)
          .voteProposal(
            proposal1Id,
            proposal1Index,
            yesVotesRevote,
            noVotesRevote,
            abstainVotesRevote
          );

        await expect(
          voteContract
            .connect(managerSigner)
            .updateHistoryAndReturnLockedStCeloInVoting(depositor0.address)
        )
          .to.emit(voteContract, "LockedStCeloInVoting")
          .withArgs(depositor0.address, totalRevotes);
      });
    });

    describe("When voted on 3 proposals", () => {
      let referendumDuration: BigNumber;

      const proposal2Id = 2;
      const proposal2Index = 1;

      const proposal3Id = 3;
      const proposal3Index = 2;

      const yesVotes = hre.web3.utils.toWei("7");
      const noVotes = hre.web3.utils.toWei("2");
      const abstainVotes = hre.web3.utils.toWei("1");

      const yesVotesProposal2 = hre.web3.utils.toWei("1");
      const noVotesProposal2 = hre.web3.utils.toWei("2");
      const abstainVotesProposal2 = hre.web3.utils.toWei("3");

      const yesVotesProposal3 = hre.web3.utils.toWei("2");
      const noVotesProposal3 = hre.web3.utils.toWei("3");
      const abstainVotesProposal3 = hre.web3.utils.toWei("4");

      beforeEach(async () => {
        referendumDuration = await voteContract.getReferendumDuration();
        await proposeNewProposal(false);
        await proposeNewProposal();
        await managerContract
          .connect(depositor0)
          .voteProposal(
            proposal2Id,
            proposal2Index,
            yesVotesProposal2,
            noVotesProposal2,
            abstainVotesProposal2
          );

        await managerContract
          .connect(depositor0)
          .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes);
        await managerContract
          .connect(depositor0)
          .voteProposal(
            proposal3Id,
            proposal3Index,
            yesVotesProposal3,
            noVotesProposal3,
            abstainVotesProposal3
          );
      });

      it("should return correct order of voted proposals", async () => {
        const votedProposals = await voteContract.getVotedStillRelevantProposals(
          await depositor0.getAddress()
        );
        const proposal1Timestamp = await voteContract.proposalTimestamps(proposal1Id);
        const proposal2Timestamp = await voteContract.proposalTimestamps(proposal2Id);
        const proposal3Timestamp = await voteContract.proposalTimestamps(proposal3Id);

        expect(votedProposals.length).to.equal(3);
        expect(votedProposals[0]).to.equal(proposal2Id);
        expect(votedProposals[1]).to.equal(proposal1Id);
        expect(votedProposals[2]).to.equal(proposal3Id);

        expect(proposal1Timestamp.toNumber()).to.greaterThan(0);
        expect(proposal2Timestamp.toNumber()).to.greaterThan(0);
        expect(proposal3Timestamp.toNumber()).to.greaterThan(0);
      });

      it("should remove expired proposal", async () => {
        const dequeueFrequency = (await governanceWrapper.dequeueFrequency()).toNumber();
        await timeTravel(referendumDuration.toNumber() - dequeueFrequency + 1);
        await (
          await voteContract
            .connect(managerSigner)
            .updateHistoryAndReturnLockedStCeloInVoting(await depositor0.getAddress())
        ).wait();
        const proposal1Timestamp = await voteContract.proposalTimestamps(proposal1Id);
        const proposal2Timestamp = await voteContract.proposalTimestamps(proposal2Id);
        const proposal3Timestamp = await voteContract.proposalTimestamps(proposal3Id);

        const votedProposals = await voteContract.getVotedStillRelevantProposals(
          await depositor0.getAddress()
        );
        expect(votedProposals.length).to.equal(2);
        expect(votedProposals[0]).to.equal(proposal2Id);
        expect(votedProposals[1]).to.equal(proposal3Id);

        expect(proposal1Timestamp.toNumber()).to.eq(0);
        expect(proposal2Timestamp.toNumber()).to.greaterThan(0);
        expect(proposal3Timestamp.toNumber()).to.greaterThan(0);
      });
    });
  });

  describe("#revokeVotes()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const amountOfCeloToDeposit = hre.web3.utils.toWei("10");

    it("should revert when account has no stCelo", async () => {
      await expect(
        managerContract.connect(depositor0).revokeVotes(proposal1Id, proposal1Index)
      ).revertedWith(`NoStakedCelo("${depositor0.address}")`);
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
          await managerContract
            .connect(depositor0)
            .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes);
        });

        it("should return voted record with correct values", async () => {
          await managerContract.connect(depositor0).revokeVotes(proposal1Id, proposal1Index);
          await checkGovernanceTotalVotes(proposal1Id, 0, 0, 0);
        });
      });
    });
  });

  describe("#setDependencies()", () => {
    let ownerSigner: SignerWithAddress;

    beforeEach(async () => {
      const voteOwner = await voteContract.owner();
      ownerSigner = await getImpersonatedSigner(voteOwner, parseUnits("1"));
    });

    it("reverts with zero stCelo address", async () => {
      await expect(
        voteContract.connect(ownerSigner).setDependencies(ADDRESS_ZERO, nonAccount.address)
      ).revertedWith("AddressZeroNotAllowed()");
    });

    it("reverts with zero account address", async () => {
      await expect(
        voteContract.connect(ownerSigner).setDependencies(nonStakedCelo.address, ADDRESS_ZERO)
      ).revertedWith("AddressZeroNotAllowed()");
    });

    it("cannot be called by a non-Owner account", async () => {
      await expect(
        voteContract.connect(nonOwner).setDependencies(nonStakedCelo.address, nonAccount.address)
      ).revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("#deleteExpiredProposalTimestamp()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const amountOfCeloToDeposit = parseUnits("10");

    const yesVotes = hre.web3.utils.toWei("7");
    const noVotes = hre.web3.utils.toWei("2");
    const abstainVotes = hre.web3.utils.toWei("1");

    beforeEach(async () => {
      await proposeNewProposal();
      await depositAndActivate(depositor0, amountOfCeloToDeposit);
      await managerContract
        .connect(depositor0)
        .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes);
    });

    it("voter should have proposal as voted", async () => {
      const proposalIds = await voteContract.getVotedStillRelevantProposals(depositor0.address);
      expect(proposalIds).to.have.deep.members([BigNumber.from(proposal1Id)]);
    });

    it("should have proposal timestamp in storage", async () => {
      const timestamp = await voteContract.proposalTimestamps(proposal1Id);
      expect(timestamp.toNumber()).to.be.greaterThan(0);
    });

    it("should revert when proposal is not expired", async () => {
      await expect(voteContract.deleteExpiredProposalTimestamp(proposal1Id)).revertedWith(
        "ProposalNotExpired()"
      );
    });

    describe("When proposal expires", () => {
      let referendumDuration: BigNumber;

      beforeEach(async () => {
        referendumDuration = await voteContract.getReferendumDuration();
        const dequeueFrequency = await governanceWrapper.dequeueFrequency();
        await timeTravel(referendumDuration.toNumber() - dequeueFrequency.toNumber() + 1);
      });

      it("should delete timestamp from storage since proposal expired", async () => {
        await voteContract.deleteExpiredProposalTimestamp(proposal1Id);
        const timestamp = await voteContract.proposalTimestamps(proposal1Id);
        expect(timestamp.toNumber()).to.be.eq(0);
      });
    });
  });

  describe("#deleteExpiredVoterProposalId()", () => {
    const proposal1Id = 1;
    const proposal1Index = 0;
    const proposal2Id = 2;
    const proposal2Index = 1;
    const amountOfCeloToDeposit = parseUnits("10");

    const yesVotes = hre.web3.utils.toWei("7");
    const noVotes = hre.web3.utils.toWei("2");
    const abstainVotes = hre.web3.utils.toWei("1");

    beforeEach(async () => {
      await depositAndActivate(depositor0, amountOfCeloToDeposit);
      await proposeNewProposal();
      await proposeNewProposal();
      await managerContract
        .connect(depositor0)
        .voteProposal(proposal1Id, proposal1Index, yesVotes, noVotes, abstainVotes);
      await managerContract
        .connect(depositor0)
        .voteProposal(proposal2Id, proposal2Index, yesVotes, noVotes, abstainVotes);
    });

    it("voter should have proposal as voted", async () => {
      const proposalIds = await voteContract.getVotedStillRelevantProposals(depositor0.address);
      expect(proposalIds).to.have.deep.members([
        BigNumber.from(proposal1Id),
        BigNumber.from(proposal2Id),
      ]);
    });

    it("should revert when incorrect index", async () => {
      await expect(
        voteContract.deleteExpiredVoterProposalId(depositor0.address, proposal1Id, proposal2Index)
      ).revertedWith("IncorrectIndex()");
    });

    it("should revert when proposal not expired", async () => {
      await expect(
        voteContract.deleteExpiredVoterProposalId(depositor0.address, proposal1Id, proposal1Index)
      ).revertedWith("ProposalNotExpired()");
    });

    describe("When proposal expires", () => {
      let referendumDuration: BigNumber;

      beforeEach(async () => {
        referendumDuration = await voteContract.getReferendumDuration();
        const dequeueFrequency = await governanceWrapper.dequeueFrequency();
        await timeTravel(referendumDuration.toNumber() - dequeueFrequency.toNumber() + 1);
      });

      it("should delete delete proposalId from voter history since proposal expired", async () => {
        await voteContract.deleteExpiredVoterProposalId(
          depositor0.address,
          proposal1Id,
          proposal1Index
        );

        const proposalIds = await voteContract.getVotedStillRelevantProposals(depositor0.address);
        expect(proposalIds).to.have.deep.members([BigNumber.from(proposal2Id)]);
      });
    });
  });

  describe("#setPauser", () => {
    it("sets the pauser address to the owner of the contract", async () => {
      await voteContract.connect(owner).setPauser();
      const newPauser = await voteContract.pauser();
      expect(newPauser).to.eq(owner.address);
    });

    it("emits a PauserSet event", async () => {
      await expect(voteContract.connect(owner).setPauser())
        .to.emit(voteContract, "PauserSet")
        .withArgs(owner.address);
    });

    it("cannot be called by a non-owner", async () => {
      await expect(voteContract.connect(nonOwner).setPauser()).revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    describe("when the owner is changed", async () => {
      beforeEach(async () => {
        await voteContract.connect(owner).transferOwnership(nonOwner.address);
      });

      it("sets the pauser to the new owner", async () => {
        await voteContract.connect(nonOwner).setPauser();
        const newPauser = await voteContract.pauser();
        expect(newPauser).to.eq(nonOwner.address);
      });
    });
  });

  describe("#pause", () => {
    it("can be called by the pauser", async () => {
      await voteContract.connect(pauser).pause();
      const isPaused = await voteContract.isPaused();
      expect(isPaused).to.be.true;
    });

    it("emits a ContractPaused event", async () => {
      await expect(voteContract.connect(pauser).pause()).to.emit(voteContract, "ContractPaused");
    });

    it("cannot be called by a random account", async () => {
      await expect(voteContract.connect(nonOwner).pause()).revertedWith("OnlyPauser()");
      const isPaused = await voteContract.isPaused();
      expect(isPaused).to.be.false;
    });
  });

  describe("#unpause", () => {
    beforeEach(async () => {
      await voteContract.connect(pauser).pause();
    });

    it("can be called by the pauser", async () => {
      await voteContract.connect(pauser).unpause();
      const isPaused = await voteContract.isPaused();
      expect(isPaused).to.be.false;
    });

    it("emits a ContractUnpaused event", async () => {
      await expect(voteContract.connect(pauser).unpause()).to.emit(
        voteContract,
        "ContractUnpaused"
      );
    });

    it("cannot be called by a random account", async () => {
      await expect(voteContract.connect(nonOwner).unpause()).revertedWith("OnlyPauser()");
      const isPaused = await voteContract.isPaused();
      expect(isPaused).to.be.true;
    });
  });

  describe("when paused", () => {
    beforeEach(async () => {
      await voteContract.connect(pauser).pause();
    });

    it("can't call deleteExpiredVoterProposalId", async () => {
      await expect(
        voteContract.connect(depositor0).deleteExpiredVoterProposalId(depositor0.address, 0, 0)
      ).revertedWith("Paused()");
    });

    it("can't call updateHistoryAndReturnLockedStCeloInVoting", async () => {
      await expect(
        voteContract
          .connect(depositor0)
          .updateHistoryAndReturnLockedStCeloInVoting(depositor0.address)
      ).revertedWith("Paused()");
    });

    it("can't call deleteExpiredProposalTimestamp", async () => {
      await expect(voteContract.connect(depositor0).deleteExpiredProposalTimestamp(0)).revertedWith(
        "Paused()"
      );
    });
  });
});
