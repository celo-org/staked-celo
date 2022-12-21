import { AccountsWrapper } from "@celo/contractkit/lib/wrappers/Accounts";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { MockRegistry__factory } from "../typechain-types/factories/MockRegistry__factory";
import { MockGovernance } from "../typechain-types/MockGovernance";
import { MockRegistry } from "../typechain-types/MockRegistry";
import electionContractData from "./code/abi/electionAbi.json";
import {
  ADDRESS_ZERO,
  getImpersonatedSigner,
  LOCKED_GOLD_UNLOCKING_PERIOD,
  mineToNextEpoch,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
  resetNetwork,
  timeTravel,
} from "./utils";

after(() => {
  hre.kit.stop();
});

describe("Account", () => {
  let accountsInstance: AccountsWrapper;
  let lockedGold: LockedGoldWrapper;
  let election: ElectionWrapper;
  let governance: MockGovernance;
  let registryContract: MockRegistry;

  let account: Account;

  let manager: SignerWithAddress;
  let nonManager: SignerWithAddress;
  let beneficiary: SignerWithAddress;
  let otherBeneficiary: SignerWithAddress;
  let nonBeneficiary: SignerWithAddress;
  let groups: SignerWithAddress[];
  let groupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  before(async () => {
    await resetNetwork();

    [manager] = await randomSigner(parseUnits("100"));
    [nonManager] = await randomSigner(parseUnits("100"));
    [beneficiary] = await randomSigner(parseUnits("100"));
    [otherBeneficiary] = await randomSigner(parseUnits("100"));
    [nonBeneficiary] = await randomSigner(parseUnits("100"));

    const registryFactory: MockRegistry__factory = (
      await hre.ethers.getContractFactory("MockRegistry")
    ).connect(manager) as MockRegistry__factory;
    registryContract = registryFactory.attach(REGISTRY_ADDRESS);

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
      await registerValidatorAndAddToGroupMembers(groups[i], validators[i], validatorWallet);
    }

    accountsInstance = await hre.kit.contracts.getAccounts();
    lockedGold = await hre.kit.contracts.getLockedGold();
    election = await hre.kit.contracts.getElection();
  });

  beforeEach(async () => {
    await hre.deployments.fixture("TestAccount");
    const owner = await hre.ethers.getNamedSigner("owner");
    account = await hre.ethers.getContract("Account");
    await account.connect(owner).setManager(manager.address);
    governance = await hre.ethers.getContract("MockGovernance");
  });

  it("should create an account on the core Accounts contract", async () => {
    const isAccount = await accountsInstance.isAccount(account.address);
    expect(isAccount).to.be.true;
  });

  describe("#scheduleVotes()", () => {
    it("assigns votes to a given group", async () => {
      await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
      const scheduledVotes = await account.scheduledVotesForGroup(groupAddresses[0]);
      expect(scheduledVotes).to.eq(100);
    });

    it("emits a VotesScheduled event", async () => {
      await expect(
        account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" })
      )
        .to.emit(account, "VotesScheduled")
        .withArgs(groupAddresses[0], 100);
    });

    it("assigns votes to multiple groups", async () => {
      await account.connect(manager).scheduleVotes(groupAddresses, [100, 30, 70], { value: "200" });
      const scheduled0 = await account.scheduledVotesForGroup(groupAddresses[0]);
      const scheduled1 = await account.scheduledVotesForGroup(groupAddresses[1]);
      const scheduled2 = await account.scheduledVotesForGroup(groupAddresses[2]);
      expect(scheduled0).to.eq(100);
      expect(scheduled1).to.eq(30);
      expect(scheduled2).to.eq(70);
    });

    it("emits multiple VotesScheduled events", async () => {
      const response = account
        .connect(manager)
        .scheduleVotes(groupAddresses, [100, 30, 70], { value: "200" });
      await expect(response).to.emit(account, "VotesScheduled").withArgs(groupAddresses[0], 100);
      await expect(response).to.emit(account, "VotesScheduled").withArgs(groupAddresses[1], 30);
      await expect(response).to.emit(account, "VotesScheduled").withArgs(groupAddresses[2], 70);
    });

    it("aggregates pending votes across invocations", async () => {
      await account
        .connect(manager)
        .scheduleVotes([groupAddresses[0], groupAddresses[2]], [100, 30], { value: "130" });
      await account
        .connect(manager)
        .scheduleVotes([groupAddresses[2], groupAddresses[1]], [50, 70], { value: "120" });
      const scheduled0 = await account.scheduledVotesForGroup(groupAddresses[0]);
      const scheduled1 = await account.scheduledVotesForGroup(groupAddresses[1]);
      const scheduled2 = await account.scheduledVotesForGroup(groupAddresses[2]);
      expect(scheduled0).to.eq(100);
      expect(scheduled1).to.eq(70);
      expect(scheduled2).to.eq(80);
    });

    it("reverts when total votes are more than value sent", async () => {
      await expect(
        account.connect(manager).scheduleVotes(groupAddresses, [100, 31, 70], { value: "200" })
      ).revertedWith("TotalVotesMismatch(200, 201)");
    });

    it("reverts when total votes are less than value sent", async () => {
      await expect(
        account.connect(manager).scheduleVotes(groupAddresses, [100, 29, 70], { value: "200" })
      ).revertedWith("TotalVotesMismatch(200, 199)");
    });

    it("reverts when there are more votes than groups", async () => {
      await expect(
        account.connect(manager).scheduleVotes([groupAddresses[0]], [100, 30], { value: "100" })
      ).revertedWith("GroupsAndVotesArrayLengthsMismatch()");
    });

    it("reverts when there are more groups than votes", async () => {
      await expect(
        account
          .connect(manager)
          .scheduleVotes([groupAddresses[0], groupAddresses[1]], [100], { value: "100" })
      ).revertedWith("GroupsAndVotesArrayLengthsMismatch()");
    });

    it("cannot be called by a non-Manager address", async () => {
      await expect(
        account.connect(nonManager).scheduleVotes(groupAddresses, [100, 30, 70], { value: "200" })
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#activateAndVote()", () => {
    describe("when there are scheduled votes", async () => {
      beforeEach(async () => {
        await account
          .connect(manager)
          .scheduleVotes(groupAddresses, [100, 30, 70], { value: "200" });
        await account
          .connect(manager)
          .scheduleVotes(groupAddresses, [40, 50, 20], { value: "110" });
      });

      it("locks CELO", async () => {
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        const locked = await lockedGold.getAccountTotalLockedGold(account.address);
        expect(locked).to.eq(140);
      });

      it("resets pending votes for the group", async () => {
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        const scheduledVotes = await account.scheduledVotesForGroup(groupAddresses[0]);
        expect(scheduledVotes).to.eq(0);
      });

      it("casts votes for the group", async () => {
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        const votes = await election.getVotesForGroupByAccount(account.address, groupAddresses[0]);
        expect(votes.pending).to.eq(140);
      });
    });

    describe("when there are activatable votes", () => {
      beforeEach(async () => {
        await account
          .connect(manager)
          .scheduleVotes(groupAddresses, [100, 30, 70], { value: "200" });
        await account
          .connect(manager)
          .scheduleVotes(groupAddresses, [40, 50, 20], { value: "110" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await mineToNextEpoch(hre.web3);
      });

      it("activates votes", async () => {
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        const votes = await election.getVotesForGroupByAccount(account.address, groupAddresses[0]);
        expect(votes.active).to.eq(140);
      });
    });

    describe("when there are both scheduled and activatable votes", () => {
      beforeEach(async () => {
        await account
          .connect(manager)
          .scheduleVotes(groupAddresses, [100, 30, 70], { value: "200" });
        await account
          .connect(manager)
          .scheduleVotes(groupAddresses, [40, 50, 20], { value: "110" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await account.connect(manager).scheduleVotes(groupAddresses, [10, 20, 30], { value: "60" });
        await mineToNextEpoch(hre.web3);
        await account.connect(manager).scheduleVotes(groupAddresses, [30, 20, 10], { value: "60" });
      });

      it("locks additional CELO", async () => {
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        const locked = await lockedGold.getAccountTotalLockedGold(account.address);
        expect(locked).to.eq(180);
      });

      it("resets pending votes for the group", async () => {
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        const scheduledVotes = await account.scheduledVotesForGroup(groupAddresses[0]);
        expect(scheduledVotes).to.eq(0);
      });

      it("activates previously cast votes for the group", async () => {
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        const votes = await election.getVotesForGroupByAccount(account.address, groupAddresses[0]);
        expect(votes.active).to.eq(140);
      });

      it("casts new pending votes for the group", async () => {
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        const votes = await election.getVotesForGroupByAccount(account.address, groupAddresses[0]);
        expect(votes.pending).to.eq(40);
      });
    });
  });

  describe("#scheduleWithdrawals()", () => {
    describe("when called by a non-manager", () => {
      it("reverts with a CallerNotManager error", async () => {
        await expect(
          account
            .connect(nonManager)
            .scheduleWithdrawals(
              beneficiary.address,
              [groupAddresses[0], groupAddresses[1], groupAddresses[2]],
              [40, 40, 40]
            )
        ).revertedWith(`CallerNotManager("${nonManager.address}")`);
      });
    });

    const scheduleWithdrawalTests = () => {
      describe("when the withdrawal amount is too high", () => {
        it("reverts with a WithdrawalAmountTooHigh error", async () => {
          await expect(
            account
              .connect(manager)
              .scheduleWithdrawals(
                beneficiary.address,
                [groupAddresses[0], groupAddresses[1], groupAddresses[2]],
                [40, 40, 310]
              )
          ).revertedWith(`WithdrawalAmountTooHigh("${groupAddresses[2]}", 300, 310)`);
        });
      });

      describe("when the withdrawal amount is in range", () => {
        const firstWithdrawal = async () => {
          return account
            .connect(manager)
            .scheduleWithdrawals(
              beneficiary.address,
              [groupAddresses[0], groupAddresses[1], groupAddresses[2]],
              [40, 40, 40]
            );
        };

        it("emits an event for each group", async () => {
          const result = await firstWithdrawal();
          for (let i = 0; i < 3; i++) {
            await expect(result)
              .to.emit(account, "CeloWithdrawalScheduled")
              .withArgs(beneficiary.address, groupAddresses[i], 40);
          }
        });

        it("increments totalScheduledWithdrawals", async () => {
          await firstWithdrawal();
          expect(await account.totalScheduledWithdrawals()).to.eq(120);
        });

        it("increments scheduledVotes[group].toWithdraw", async () => {
          await firstWithdrawal();
          for (let i = 0; i < 3; i++) {
            expect(await account.scheduledWithdrawalsForGroup(groupAddresses[i])).to.eq(40);
          }
        });

        it("increments scheduledVotes[group].toWithdrawFor[beneficiary]", async () => {
          await firstWithdrawal();
          for (let i = 0; i < 3; i++) {
            expect(
              await account.scheduledWithdrawalsForGroupAndBeneficiary(
                groupAddresses[i],
                beneficiary.address
              )
            ).to.eq(40);
          }
        });

        context("and a second withdrawal happens", () => {
          const secondWithdrawal = async () => {
            return account
              .connect(manager)
              .scheduleWithdrawals(
                otherBeneficiary.address,
                [groupAddresses[0], groupAddresses[1], groupAddresses[2]],
                [30, 30, 30]
              );
          };

          it("increments totalScheduledWithdrawals", async () => {
            await firstWithdrawal();
            await secondWithdrawal();
            expect(await account.totalScheduledWithdrawals()).to.eq(210);
          });

          it("increments scheduledVotes[group].toWithdraw", async () => {
            await firstWithdrawal();
            await secondWithdrawal();
            for (let i = 0; i < 3; i++) {
              expect(await account.scheduledWithdrawalsForGroup(groupAddresses[i])).to.eq(70);
            }
          });

          it("increments scheduledVotes[group].toWithdrawFor[beneficiary]", async () => {
            await firstWithdrawal();
            await secondWithdrawal();
            for (let i = 0; i < 3; i++) {
              expect(
                await account.scheduledWithdrawalsForGroupAndBeneficiary(
                  groupAddresses[i],
                  beneficiary.address
                )
              ).to.eq(40);
              expect(
                await account.scheduledWithdrawalsForGroupAndBeneficiary(
                  groupAddresses[i],
                  otherBeneficiary.address
                )
              ).to.eq(30);
            }
          });
        });
      });
    };

    describe("when votes are scheduled", () => {
      beforeEach(async () => {
        await account
          .connect(manager)
          .scheduleVotes(
            [groupAddresses[0], groupAddresses[1], groupAddresses[2]],
            [100, 200, 300],
            { value: 600 }
          );
      });

      scheduleWithdrawalTests();
    });

    describe("when votes are locked and pending", () => {
      beforeEach(async () => {
        await account
          .connect(manager)
          .scheduleVotes(
            [groupAddresses[0], groupAddresses[1], groupAddresses[2]],
            [100, 200, 300],
            { value: 600 }
          );
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await account.activateAndVote(groupAddresses[1], groupAddresses[2], ADDRESS_ZERO);
        await account.activateAndVote(groupAddresses[2], groupAddresses[0], ADDRESS_ZERO);
      });

      scheduleWithdrawalTests();
    });

    describe("when votes are active", () => {
      beforeEach(async () => {
        await account
          .connect(manager)
          .scheduleVotes(
            [groupAddresses[0], groupAddresses[1], groupAddresses[2]],
            [100, 200, 300],
            { value: 600 }
          );
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await account.activateAndVote(groupAddresses[1], groupAddresses[2], ADDRESS_ZERO);
        await account.activateAndVote(groupAddresses[2], groupAddresses[0], ADDRESS_ZERO);
        await mineToNextEpoch(hre.web3);
        await account.activateAndVote(groupAddresses[0], ADDRESS_ZERO, groupAddresses[1]);
        await account.activateAndVote(groupAddresses[1], groupAddresses[0], groupAddresses[2]);
        await account.activateAndVote(groupAddresses[2], groupAddresses[1], ADDRESS_ZERO);
      });

      scheduleWithdrawalTests();
    });
  });

  describe("#withdraw()", () => {
    describe("when there are scheduled votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: 100 });
        await account
          .connect(manager)
          .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
      });

      it("emits CeloWithdrawalStarted", async () => {
        await expect(
          account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              ADDRESS_ZERO,
              ADDRESS_ZERO,
              ADDRESS_ZERO,
              ADDRESS_ZERO,
              0
            )
        )
          .to.emit(account, "CeloWithdrawalStarted")
          .withArgs(beneficiary.address, groupAddresses[0], 60);
      });

      it("immediately transfers out scheduled CELO", async () => {
        const balanceBefore = await hre.ethers.provider.getBalance(beneficiary.address);
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            0
          );
        const balanceAfter = await hre.ethers.provider.getBalance(beneficiary.address);
        expect(balanceAfter.sub(balanceBefore)).to.eq(60);
      });

      it("decrements scheduled votes", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            0
          );
        const afterScheduledVotes = await account.scheduledVotesForGroup(groupAddresses[0]);
        expect(afterScheduledVotes).to.eq(40);
      });
    });

    describe("when there are pending votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: 100 });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await account
          .connect(manager)
          .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
      });

      it("revokes pending votes", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            0
          );

        const votes = await election.getVotesForGroupByAccount(account.address, groupAddresses[0]);
        expect(votes.pending).to.eq(40);
      });

      it("unlocks CELO", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            0
          );

        const pendingWithdrawals = await lockedGold.getPendingWithdrawals(account.address);
        expect(pendingWithdrawals.length).to.eq(1);
        expect(pendingWithdrawals[0].value).to.eq(60);
      });

      it("internally assigns the withdrawal to beneficiary", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            ADDRESS_ZERO,
            0
          );

        const [value] = await account.getPendingWithdrawal(beneficiary.address, 0);
        expect(value).to.eq(60);
      });
    });

    describe("when there are active votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: 100 });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await mineToNextEpoch(hre.web3);
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await account
          .connect(manager)
          .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
      });

      it("revokes active votes", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            groupAddresses[1],
            ADDRESS_ZERO,
            0
          );

        const votes = await election.getVotesForGroupByAccount(account.address, groupAddresses[0]);
        expect(votes.active).to.eq(40);
      });

      it("unlocks CELO", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            groupAddresses[1],
            ADDRESS_ZERO,
            0
          );

        const pendingWithdrawals = await lockedGold.getPendingWithdrawals(account.address);
        expect(pendingWithdrawals.length).to.eq(1);
        expect(pendingWithdrawals[0].value).to.eq(60);
      });

      it("internally assigns the withdrawal to beneficiary", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            groupAddresses[1],
            ADDRESS_ZERO,
            0
          );

        const [value] = await account.getPendingWithdrawal(beneficiary.address, 0);
        expect(value).to.eq(60);
      });
    });

    describe("when there are scheduled, pending, and active votes", () => {
      beforeEach(async () => {
        // These votes will be activated.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await mineToNextEpoch(hre.web3);
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        // These votes will be cast but remain pending in Elections.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        // These votes will remain scheduled in Account.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account
          .connect(manager)
          .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [250]);
      });

      it("immediately transfers out scheduled CELO", async () => {
        const balanceBefore = await hre.ethers.provider.getBalance(beneficiary.address);

        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            groupAddresses[1],
            ADDRESS_ZERO,
            0
          );

        const balanceAfter = await hre.ethers.provider.getBalance(beneficiary.address);
        expect(balanceAfter.sub(balanceBefore)).to.eq(100);
      });

      it("revokes pending votes", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            groupAddresses[1],
            ADDRESS_ZERO,
            0
          );
        const votes = await election.getVotesForGroupByAccount(account.address, groupAddresses[0]);
        expect(votes.pending).to.eq(0);
      });

      it("revokes active votes", async () => {
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            groupAddresses[1],
            ADDRESS_ZERO,
            0
          );
        const votes = await election.getVotesForGroupByAccount(account.address, groupAddresses[0]);
        expect(votes.active).to.eq(50);
      });
    });
  });

  describe("#finishPendingWithdrawal()", () => {
    describe("when there is a pending withdrawal ready", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await account
          .connect(manager)
          .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
        await account
          .connect(manager)
          .withdraw(
            beneficiary.address,
            groupAddresses[0],
            groupAddresses[1],
            ADDRESS_ZERO,
            groupAddresses[1],
            ADDRESS_ZERO,
            0
          );
        await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);
      });

      it("transfers out CELO", async () => {
        const balanceBefore = await hre.ethers.provider.getBalance(beneficiary.address);
        await account.finishPendingWithdrawal(beneficiary.address, 0, 0);
        const balanceAfter = await hre.ethers.provider.getBalance(beneficiary.address);
        expect(balanceAfter.sub(balanceBefore)).to.eq(60);
      });

      it("has to be called with the correct beneficiary", async () => {
        await expect(account.finishPendingWithdrawal(nonBeneficiary.address, 0, 0)).revertedWith(
          "PendingWithdrawalIndexTooHigh(0, 0)"
        );
      });

      it("removes the pending withdrawal", async () => {
        await account.finishPendingWithdrawal(beneficiary.address, 0, 0);
        const numberWithdrawals = await account.getNumberPendingWithdrawals(beneficiary.address);
        expect(numberWithdrawals).to.eq(0);
      });
    });
  });

  describe("#getCeloForGroup()", () => {
    it("returns 0 when there were no votes", async () => {
      const votes = await account.getCeloForGroup(groupAddresses[0]);
      expect(votes).to.eq(0);
    });

    describe("when there are scheduled votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
      });

      it("reports them", async () => {
        const votes = await account.getCeloForGroup(groupAddresses[0]);
        expect(votes).to.eq(100);
      });

      describe("when some of them have been withdrawn", () => {
        beforeEach(async () => {
          await account
            .connect(manager)
            .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
          await account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              groupAddresses[1],
              ADDRESS_ZERO,
              groupAddresses[1],
              ADDRESS_ZERO,
              0
            );
        });

        it("reports only the remaining votes", async () => {
          const votes = await account.getCeloForGroup(groupAddresses[0]);
          expect(votes).to.eq(40);
        });
      });
    });

    describe("when there are pending votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
      });

      it("reports them", async () => {
        const votes = await account.getCeloForGroup(groupAddresses[0]);
        expect(votes).to.eq(100);
      });

      describe("when some of them have been withdrawn", () => {
        beforeEach(async () => {
          await account
            .connect(manager)
            .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
          await account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              groupAddresses[1],
              ADDRESS_ZERO,
              groupAddresses[1],
              ADDRESS_ZERO,
              0
            );
        });

        it("reports only the remaining votes", async () => {
          const votes = await account.getCeloForGroup(groupAddresses[0]);
          expect(votes).to.eq(40);
        });
      });
    });

    describe("when there are active votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await mineToNextEpoch(hre.web3);
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
      });

      it("reports them", async () => {
        const votes = await account.getCeloForGroup(groupAddresses[0]);
        expect(votes).to.eq(100);
      });

      describe("when some of them have been withdrawn", () => {
        beforeEach(async () => {
          await account
            .connect(manager)
            .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
          await account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              groupAddresses[1],
              ADDRESS_ZERO,
              groupAddresses[1],
              ADDRESS_ZERO,
              0
            );
        });

        it("reports only the remaining votes", async () => {
          const votes = await account.getCeloForGroup(groupAddresses[0]);
          expect(votes).to.eq(40);
        });
      });
    });

    describe("when there are scheduled, pending, and active votes", () => {
      beforeEach(async () => {
        // These votes will be activated.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await mineToNextEpoch(hre.web3);
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        // These votes will be cast but remain pending in Elections.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        // These votes will remain scheduled in Account.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
      });

      it("reports all of them", async () => {
        const votes = await account.getCeloForGroup(groupAddresses[0]);
        expect(votes).to.eq(300);
      });

      describe("when some of them have been withdrawn", () => {
        beforeEach(async () => {
          await account
            .connect(manager)
            .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [260]);
          await account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              groupAddresses[1],
              ADDRESS_ZERO,
              groupAddresses[1],
              ADDRESS_ZERO,
              0
            );
        });

        it("reports only the remaining votes", async () => {
          const votes = await account.getCeloForGroup(groupAddresses[0]);
          expect(votes).to.eq(40);
        });
      });
    });
  });

  describe("#getTotalCelo()", () => {
    it("returns 0 when there were no votes", async () => {
      const votes = await account.getTotalCelo();
      expect(votes).to.eq(0);
    });

    describe("when there are scheduled votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
      });

      it("reports them", async () => {
        const votes = await account.getTotalCelo();
        expect(votes).to.eq(100);
      });

      describe("when some of them have been withdrawn", () => {
        beforeEach(async () => {
          await account
            .connect(manager)
            .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
          await account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              groupAddresses[1],
              ADDRESS_ZERO,
              groupAddresses[1],
              ADDRESS_ZERO,
              0
            );
        });

        it("reports only the remaining votes", async () => {
          const votes = await account.getTotalCelo();
          expect(votes).to.eq(40);
        });
      });
    });

    describe("when there are pending votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
      });

      it("reports them", async () => {
        const votes = await account.getTotalCelo();
        expect(votes).to.eq(100);
      });

      describe("when some of them have been withdrawn", () => {
        beforeEach(async () => {
          await account
            .connect(manager)
            .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
          await account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              groupAddresses[1],
              ADDRESS_ZERO,
              groupAddresses[1],
              ADDRESS_ZERO,
              0
            );
        });

        it("reports only the remaining votes", async () => {
          const votes = await account.getTotalCelo();
          expect(votes).to.eq(40);
        });
      });
    });

    describe("when there are active votes", () => {
      beforeEach(async () => {
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await mineToNextEpoch(hre.web3);
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
      });

      it("reports them", async () => {
        const votes = await account.getTotalCelo();
        expect(votes).to.eq(100);
      });

      describe("when some of them have been withdrawn", () => {
        beforeEach(async () => {
          await account
            .connect(manager)
            .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [60]);
          await account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              groupAddresses[1],
              ADDRESS_ZERO,
              groupAddresses[1],
              ADDRESS_ZERO,
              0
            );
        });

        it("reports only the remaining votes", async () => {
          const votes = await account.getTotalCelo();
          expect(votes).to.eq(40);
        });
      });
    });

    describe("when there are scheduled, pending, and active votes", () => {
      beforeEach(async () => {
        // These votes will be activated.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        await mineToNextEpoch(hre.web3);
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        // These votes will be cast but remain pending in Elections.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
        await account.activateAndVote(groupAddresses[0], groupAddresses[1], ADDRESS_ZERO);
        // These votes will remain scheduled in Account.
        await account.connect(manager).scheduleVotes([groupAddresses[0]], [100], { value: "100" });
      });

      it("reports all of them", async () => {
        const votes = await account.getTotalCelo();
        expect(votes).to.eq(300);
      });

      describe("when some of them have been withdrawn", () => {
        beforeEach(async () => {
          await account
            .connect(manager)
            .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [260]);
          await account
            .connect(manager)
            .withdraw(
              beneficiary.address,
              groupAddresses[0],
              groupAddresses[1],
              ADDRESS_ZERO,
              groupAddresses[1],
              ADDRESS_ZERO,
              0
            );
        });

        it("reports only the remaining votes", async () => {
          const votes = await account.getTotalCelo();
          expect(votes).to.eq(40);
        });
      });
    });
  });

  describe("#setAllowedToVoteOverMaxNumberOfGroups()", () => {
    let owner: SignerWithAddress;

    beforeEach(async () => {
      const ownerAddress = await account.owner();
      owner = await getImpersonatedSigner(ownerAddress);
    });
    it("reverts when not called by owner", async () => {
      expect(account.setAllowedToVoteOverMaxNumberOfGroups(true)).revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("sets allowedToVoteOverMaxNumberOfGroups correctly", async () => {
      // TODO: once contractkit updated - use just election contract from contractkit
      const electionContract = new hre.kit.web3.eth.Contract(
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        electionContractData.abi as any,
        election.address
      );
      const setAllowedToVoteOverMaxNumberOfGroupsTxObject =
        electionContract.methods.allowedToVoteOverMaxNumberOfGroups(account.address);

      const isAllowedToVoteOverMaxNumberOfGroupsFalse =
        await setAllowedToVoteOverMaxNumberOfGroupsTxObject.call();
      expect(
        isAllowedToVoteOverMaxNumberOfGroupsFalse,
        "allowedToVoteOverMaxNumberOfGroups not set correctly"
      ).to.be.false;

      const setAllowedToVoteOverMaxNumberOfGroupsTx = await account
        .connect(owner)
        .setAllowedToVoteOverMaxNumberOfGroups(true);
      await setAllowedToVoteOverMaxNumberOfGroupsTx.wait();

      const isAllowedToVoteOverMaxNumberOfGroupsTrue =
        await setAllowedToVoteOverMaxNumberOfGroupsTxObject.call();
      expect(
        isAllowedToVoteOverMaxNumberOfGroupsTrue,
        "allowedToVoteOverMaxNumberOfGroups not set correctly"
      ).to.be.true;
    });
  });

  describe("#voteProposal", () => {
    it("should should revert when not called by manager", async () => {
      const proposalId = 3;
      const index = 4;
      const yes = 5;
      const no = 6;
      const abstain = 7;

      await expect(
        account.connect(nonManager).votePartially(proposalId, index, yes, no, abstain)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });

    it("should pass correct values to governance contract", async () => {
      const registryOwner = await registryContract.owner();
      const registryOwnerSigner = await getImpersonatedSigner(registryOwner);

      const setAddressTx = await registryContract
        .connect(registryOwnerSigner)
        .setAddressFor("Governance", governance.address);
      await setAddressTx.wait();

      const proposalId = 1;
      const index = 0;
      const yes = 5;
      const no = 6;
      const abstain = 7;

      await account.connect(manager).votePartially(proposalId, index, yes, no, abstain);

      expect(await governance.proposalId()).to.eq(proposalId);
      expect(await governance.index()).to.eq(index);
      expect(await governance.yesVotes()).to.eq(yes);
      expect(await governance.noVotes()).to.eq(no);
      expect(await governance.abstainVotes()).to.eq(abstain);
    });
  });
});
