import hre from "hardhat";
import { BigNumber } from "ethers";
import BigNumberJs from "bignumber.js";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { Manager } from "../typechain-types/Manager";
import { MockAccount } from "../typechain-types/MockAccount";
import { MockAccount__factory } from "../typechain-types/factories/MockAccount__factory";
import { MockStakedCelo } from "../typechain-types/MockStakedCelo";
import { MockStakedCelo__factory } from "../typechain-types/factories/MockStakedCelo__factory";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  randomSigner,
  registerValidator,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
  resetNetwork,
} from "./utils";

const sum = (xs: BigNumber[]): BigNumber => xs.reduce((a, b) => a.add(b));

after(() => {
  hre.kit.stop();
});

describe("Manager", () => {
  let account: MockAccount;
  let stakedCelo: MockStakedCelo;
  let manager: Manager;

  let election: ElectionWrapper;
  let lockedGold: LockedGoldWrapper;

  let owner: SignerWithAddress;
  let nonOwner: SignerWithAddress;
  let someone: SignerWithAddress;
  let depositor: SignerWithAddress;
  let voter: SignerWithAddress;
  let groups: SignerWithAddress[];
  let groupAddresses: string[];

  let snapshotId: any;

  before(async function () {
    this.timeout(100000);
    await resetNetwork();
    election = await hre.kit.contracts.getElection();

    await hre.deployments.fixture("TestManager");
    manager = await hre.ethers.getContract("Manager");

    [owner] = await randomSigner(parseUnits("100"));
    [nonOwner] = await randomSigner(parseUnits("100"));
    [someone] = await randomSigner(parseUnits("100"));
    [depositor] = await randomSigner(parseUnits("300"));
    [voter] = await randomSigner(parseUnits("10000000000"));

    const accountFactory: MockAccount__factory = (
      await hre.ethers.getContractFactory("MockAccount")
    ).connect(owner) as MockAccount__factory;
    account = await accountFactory.deploy();

    const stakedCeloFactory: MockStakedCelo__factory = (
      await hre.ethers.getContractFactory("MockStakedCelo")
    ).connect(owner) as MockStakedCelo__factory;
    stakedCelo = await stakedCeloFactory.deploy();

    manager.setDependencies(stakedCelo.address, account.address);

    groups = [];
    groupAddresses = [];
    for (let i = 0; i < 11; i++) {
      const [group] = await randomSigner(parseUnits("21000"));
      groups.push(group);
      groupAddresses.push(group.address);
    }

    lockedGold = await hre.kit.contracts.getLockedGold();
    for (let i = 0; i < 11; i++) {
      if (i == 1) {
        // For groups[1] we register an extra validator so it has a higher voting limit.
        await registerValidatorGroup(groups[i], 2);
        const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
        await registerValidator(groups[i], validator, validatorWallet);
      } else {
        await registerValidatorGroup(groups[i], 1);
      }
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      await registerValidator(groups[i], validator, validatorWallet);
    }
  });

  beforeEach(async () => {
    snapshotId = await hre.ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await hre.ethers.provider.send("evm_revert", [snapshotId]);
  });

  describe("#activateGroup()", () => {
    it("adds a group", async () => {
      await manager.activateGroup(groupAddresses[0]);
      const activeGroups = await manager.getGroups();
      expect(activeGroups).to.deep.eq([groupAddresses[0]]);
    });

    it("emits a GroupActivated event", async () => {
      await expect(manager.activateGroup(groupAddresses[0]))
        .to.emit(manager, "GroupActivated")
        .withArgs(groupAddresses[0]);
    });

    it("cannot be called by a non owner", async () => {
      await expect(manager.connect(nonOwner).activateGroup(groupAddresses[0])).revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    describe("when some groups are already added", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
        }
      });

      it("adds another group", async () => {
        await manager.activateGroup(groupAddresses[3]);
        const activeGroups = await manager.getGroups();
        expect(activeGroups).to.deep.eq(groupAddresses.slice(0, 4));
      });

      it("emits a GroupActivated event", async () => {
        await expect(manager.activateGroup(groupAddresses[3]))
          .to.emit(manager, "GroupActivated")
          .withArgs(groupAddresses[3]);
      });

      it("reverts when trying to add an existing group", async () => {
        await expect(manager.activateGroup(groupAddresses[1])).revertedWith(
          `GroupAlreadyAdded("${groupAddresses[1]}")`
        );
      });
    });

    describe("when maxNumGroupsVotedFor have been voted for", async () => {
      let additionalGroup: SignerWithAddress;

      beforeEach(async () => {
        [additionalGroup] = await randomSigner(parseUnits("100"));

        for (let i = 0; i < 10; i++) {
          await manager.activateGroup(groups[i].address);
        }
      });

      it("cannot add another group", async () => {
        await expect(manager.activateGroup(additionalGroup.address)).revertedWith(
          "MaxGroupsVotedForReached()"
        );
      });

      describe("when some of the groups are currently deprecated", () => {
        beforeEach(async () => {
          await account.setCeloForGroup(groupAddresses[2], 100);
          await account.setCeloForGroup(groupAddresses[7], 100);
          await manager.deprecateGroup(groupAddresses[2]);
          await manager.deprecateGroup(groupAddresses[7]);
        });

        it("cannot add another group", async () => {
          await expect(manager.activateGroup(additionalGroup.address)).revertedWith(
            "MaxGroupsVotedForReached()"
          );
        });

        it("reactivates a deprecated group", async () => {
          await manager.activateGroup(groupAddresses[2]);
          const activeGroups = await manager.getGroups();
          expect(activeGroups[8]).to.equal(groupAddresses[2]);
        });

        it("emits a GroupActivated event", async () => {
          await expect(manager.activateGroup(groupAddresses[2]))
            .to.emit(manager, "GroupActivated")
            .withArgs(groupAddresses[2]);
        });

        it("removes the group from deprecated", async () => {
          await manager.activateGroup(groupAddresses[2]);
          const deprecatedGroups = await manager.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.equal([groupAddresses[7]]);
        });
      });
    });
  });

  describe("#deprecateGroup()", () => {
    let deprecatedGroup: SignerWithAddress;

    beforeEach(async () => {
      deprecatedGroup = groups[1];
      for (let i = 0; i < 3; i++) {
        await manager.activateGroup(groups[i].address);
      }
    });

    describe("when the group is voted for", () => {
      beforeEach(async () => {
        await account.setCeloForGroup(deprecatedGroup.address, 100);
      });

      it("removes the group from the groups array", async () => {
        await manager.deprecateGroup(deprecatedGroup.address);
        const activeGroups = await manager.getGroups();
        expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[2]]);
      });

      it("adds the group to the deprecatedd array", async () => {
        await manager.deprecateGroup(deprecatedGroup.address);
        const deprecatedGroups = await manager.getDeprecatedGroups();
        expect(deprecatedGroups).to.deep.eq([groupAddresses[1]]);
      });

      it("emits a GroupDeprecated event", async () => {
        await expect(manager.deprecateGroup(deprecatedGroup.address))
          .to.emit(manager, "GroupDeprecated")
          .withArgs(deprecatedGroup.address);
      });

      it("reverts when deprecating a non active group", async () => {
        await expect(manager.deprecateGroup(groupAddresses[3])).revertedWith(
          `GroupNotActive("${groupAddresses[3]}")`
        );
      });

      it("cannot be called by a non owner", async () => {
        await expect(
          manager.connect(nonOwner).deprecateGroup(deprecatedGroup.address)
        ).revertedWith("Ownable: caller is not the owner");
      });
    });

    describe("when the group is not voted for", () => {
      it("removes the group from the groups array", async () => {
        await manager.deprecateGroup(deprecatedGroup.address);
        const activeGroups = await manager.getGroups();
        expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[2]]);
      });

      it("does not add the group to the deprecatedd array", async () => {
        await manager.deprecateGroup(deprecatedGroup.address);
        const deprecatedGroups = await manager.getDeprecatedGroups();
        expect(deprecatedGroups).to.deep.eq([]);
      });

      it("emits a GroupDeprecated event", async () => {
        await expect(manager.deprecateGroup(deprecatedGroup.address))
          .to.emit(manager, "GroupDeprecated")
          .withArgs(deprecatedGroup.address);
      });

      it("emits a GroupRemoved event", async () => {
        await expect(manager.deprecateGroup(deprecatedGroup.address))
          .to.emit(manager, "GroupRemoved")
          .withArgs(deprecatedGroup.address);
      });

      it("reverts when deprecating a non active group", async () => {
        await expect(manager.deprecateGroup(groupAddresses[3])).revertedWith(
          `GroupNotActive("${groupAddresses[3]}")`
        );
      });

      it("cannot be called by a non owner", async () => {
        await expect(
          manager.connect(nonOwner).deprecateGroup(deprecatedGroup.address)
        ).revertedWith("Ownable: caller is not the owner");
      });
    });
  });

  describe("#deposit()", async () => {
    it("reverts when there are no active groups", async () => {
      await expect(manager.connect(depositor).deposit({ value: 100 })).revertedWith(
        "NoActiveGroups()"
      );
    });

    describe("when all groups have equal votes", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }
      });

      it("distributes votes evenly", async () => {
        await manager.connect(depositor).deposit({ value: 99 });
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal(groupAddresses.slice(0, 3));
        expect(votes).to.deep.equal([
          BigNumber.from("33"),
          BigNumber.from("33"),
          BigNumber.from("33"),
        ]);
      });

      it("distributes a slight overflow correctly", async () => {
        await manager.connect(depositor).deposit({ value: 100 });
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal(groupAddresses.slice(0, 3));
        expect(votes).to.deep.equal([
          BigNumber.from("34"),
          BigNumber.from("33"),
          BigNumber.from("33"),
        ]);
      });

      it("distributes a different slight overflow correctly", async () => {
        await manager.connect(depositor).deposit({ value: 101 });
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal(groupAddresses.slice(0, 3));
        expect(votes).to.deep.equal([
          BigNumber.from("34"),
          BigNumber.from("34"),
          BigNumber.from("33"),
        ]);
      });

      describe("when one of the groups is deprecated", () => {
        beforeEach(async () => {
          await manager.deprecateGroup(groupAddresses[1]);
        });

        it("distributes votes evenly between the two active groups", async () => {
          await manager.connect(depositor).deposit({ value: 100 });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[0], groupAddresses[2]]);
          expect(votes).to.deep.equal([BigNumber.from("50"), BigNumber.from("50")]);
        });

        it("distributes a slight overflow correctly", async () => {
          await manager.connect(depositor).deposit({ value: 101 });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[0], groupAddresses[2]]);
          expect(votes).to.deep.equal([BigNumber.from("51"), BigNumber.from("50")]);
        });
      });
    });

    describe("when groups have unequal votes", () => {
      const votes = [40, 100, 30];
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], votes[i]);
        }
      });

      it("distributes a small deposit to the least voted validator only", async () => {
        await manager.connect(depositor).deposit({ value: 10 });
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([groupAddresses[2]]);
        expect(votes).to.deep.equal([BigNumber.from("10")]);
      });

      it("distributes a medium deposit to two validators only", async () => {
        await manager.connect(depositor).deposit({ value: 130 });
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([groupAddresses[2], groupAddresses[0]]);
        expect(votes).to.deep.equal([BigNumber.from("70"), BigNumber.from("60")]);
      });

      it("distributes a medium deposit with overflow correctly", async () => {
        await manager.connect(depositor).deposit({ value: 131 });
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([groupAddresses[2], groupAddresses[0]]);
        expect(votes).to.deep.equal([BigNumber.from("71"), BigNumber.from("60")]);
      });

      it("distributes a large deposit to all validators", async () => {
        await manager.connect(depositor).deposit({ value: 160 });
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([
          groupAddresses[2],
          groupAddresses[0],
          groupAddresses[1],
        ]);
        expect(votes).to.deep.equal([
          BigNumber.from("80"),
          BigNumber.from("70"),
          BigNumber.from("10"),
        ]);
      });

      it("distributes a large deposit with overflow correctly", async () => {
        await manager.connect(depositor).deposit({ value: 162 });
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([
          groupAddresses[2],
          groupAddresses[0],
          groupAddresses[1],
        ]);
        expect(votes).to.deep.equal([
          BigNumber.from("81"),
          BigNumber.from("71"),
          BigNumber.from("10"),
        ]);
      });

      describe("when one of the groups is deprecated", () => {
        beforeEach(async () => {
          await manager.deprecateGroup(groupAddresses[0]);
        });

        it("distributes a small deposit to the least voted validator only", async () => {
          await manager.connect(depositor).deposit({ value: 10 });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[2]]);
          expect(votes).to.deep.equal([BigNumber.from("10")]);
        });

        it("distributes another small deposit to the least voted validator only", async () => {
          await manager.connect(depositor).deposit({ value: 70 });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[2]]);
          expect(votes).to.deep.equal([BigNumber.from("70")]);
        });

        it("distributes a larger deposit to both active groups", async () => {
          await manager.connect(depositor).deposit({ value: 80 });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[2], groupAddresses[1]]);
          expect(votes).to.deep.equal([BigNumber.from("75"), BigNumber.from("5")]);
        });

        it("distributes a larger deposit with overflow correctly", async () => {
          await manager.connect(depositor).deposit({ value: 81 });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[2], groupAddresses[1]]);
          expect(votes).to.deep.equal([BigNumber.from("76"), BigNumber.from("5")]);
        });
      });
    });

    describe("stCELO minting", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
        }
      });

      describe("when there are no tokens in the system", () => {
        beforeEach(async () => {
          await account.setTotalCelo(0);
        });

        it("mints CELO 1:1 with stCELO", async () => {
          await manager.connect(depositor).deposit({ value: 100 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(100);
        });

        it("calculates CELO 1:1 with stCELO for a different amount", async () => {
          await manager.connect(depositor).deposit({ value: 10 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(10);
        });
      });

      describe("when there are equal amount of CELO and stCELO in the system", () => {
        beforeEach(async () => {
          await account.setTotalCelo(100);
          await stakedCelo.mint(someone.address, 100);
        });

        it("calculates CELO 1:1 with stCELO", async () => {
          await manager.connect(depositor).deposit({ value: 100 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(100);
        });

        it("calculates CELO 1:1 with stCELO for a different amount", async () => {
          await manager.connect(depositor).deposit({ value: 10 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(10);
        });
      });

      describe("when there is more CELO than stCELO in the system", () => {
        beforeEach(async () => {
          await account.setTotalCelo(200);
          await stakedCelo.mint(someone.address, 100);
        });

        it("calculates less stCELO than the input CELO", async () => {
          await manager.connect(depositor).deposit({ value: 100 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(50);
        });

        it("calculates less stCELO than the input CELO for a different amount", async () => {
          await manager.connect(depositor).deposit({ value: 10 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(5);
        });
      });

      describe("when there is less CELO than stCELO in the system", () => {
        beforeEach(async () => {
          await account.setTotalCelo(100);
          await stakedCelo.mint(someone.address, 200);
        });

        it("calculates more stCELO than the input CELO", async () => {
          await manager.connect(depositor).deposit({ value: 100 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(200);
        });

        it("calculates more stCELO than the input CELO for a different amount", async () => {
          await manager.connect(depositor).deposit({ value: 10 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(20);
        });
      });
    });

    describe("when groups are close to their voting limit", () => {
      beforeEach(async () => {
        // These numbers are derived from a system of linear equations such that
        // given 12 validators registered, as above, we have the following
        // limits for the first three groups:
        // group[0] and group[2]: 95864 Locked CELO
        // group[1]: 143796 Locked CELO
        // and the remaining receivable votes are [40, 100, 200] (in CELO) for
        // the three groups, respectively.
        const votes = [parseUnits("95824"), parseUnits("143696"), parseUnits("95664")];

        const accounts = await hre.kit.contracts.getAccounts();
        await accounts.createAccount().sendAndWaitForReceipt({
          from: voter.address,
        });

        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);

          await lockedGold.lock().sendAndWaitForReceipt({
            from: voter.address,
            value: votes[i].toString(),
          });
        }

        // We have to do this in a separate loop because the voting limits
        // depend on total locked CELO. The votes we want to cast are very close
        // to the final limit we'll arrive at, so we first lock all CELO, then
        // cast it as votes.
        for (let i = 0; i < 3; i++) {
          const voteTx = await election.vote(
            groupAddresses[i],
            new BigNumberJs(votes[i].toString())
          );
          await voteTx.sendAndWaitForReceipt({ from: voter.address });
        }
      });

      it("skips the first group when the deposit total would push it over its capacity", async () => {
        await manager.connect(depositor).deposit({ value: parseUnits("50") });

        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([groupAddresses[1], groupAddresses[2]]);

        expect(votes).to.deep.equal([parseUnits("25"), parseUnits("25")]);
      });

      it("skips the first two groups when the deposit total would push them over their capacity", async () => {
        await manager.connect(depositor).deposit({ value: parseUnits("110") });

        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([groupAddresses[2]]);

        expect(votes).to.deep.equal([parseUnits("110")]);
      });

      it("reverts when the deposit total would push all groups over their capacity", async () => {
        await expect(manager.connect(depositor).deposit({ value: parseUnits("210") })).revertedWith(
          "NoVotableGroups()"
        );
      });

      describe("when there are scheduled votes for the groups", () => {
        beforeEach(async () => {
          await account.setScheduledVotes(groupAddresses[0], parseUnits("50"));
          await account.setScheduledVotes(groupAddresses[1], parseUnits("50"));
          // Schedule more votes for group[2] so it gets skipped before
          // group[1].
          await account.setScheduledVotes(groupAddresses[2], parseUnits("170"));
        });

        it("skips the first group at a smaller deposit", async () => {
          await manager.connect(depositor).deposit({ value: parseUnits("2") });

          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[1], groupAddresses[2]]);

          expect(votes).to.deep.equal([parseUnits("1"), parseUnits("1")]);
        });

        it("skips the first and last group at a small deposit", async () => {
          await manager.connect(depositor).deposit({ value: parseUnits("31") });

          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[1]]);

          expect(votes).to.deep.equal([parseUnits("31")]);
        });

        it("reverts when the deposit total would push all groups over their capacity", async () => {
          await expect(
            manager.connect(depositor).deposit({ value: parseUnits("51") })
          ).revertedWith("NoVotableGroups()");
        });
      });
    });
  });

  describe("#withdraw()", async () => {
    it("reverts when there are no active or deprecated groups", async () => {
      await expect(manager.connect(depositor).withdraw(100)).revertedWith("NoGroups()");
    });

    describe("when all groups have equal votes", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }

        await stakedCelo.mint(depositor.address, 300);
        await account.setTotalCelo(300);
      });

      it("distributes withdrawals evenly", async () => {
        await manager.connect(depositor).withdraw(99);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal(groupAddresses.slice(0, 3));
        expect(withdrawals).to.deep.equal([
          BigNumber.from("33"),
          BigNumber.from("33"),
          BigNumber.from("33"),
        ]);
      });

      it("distributes a slight overflow correctly", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal(groupAddresses.slice(0, 3));
        expect(withdrawals).to.deep.equal([
          BigNumber.from("33"),
          BigNumber.from("33"),
          BigNumber.from("34"),
        ]);
      });

      it("distributes a different slight overflow correctly", async () => {
        await manager.connect(depositor).withdraw(101);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal(groupAddresses.slice(0, 3));
        expect(withdrawals).to.deep.equal([
          BigNumber.from("33"),
          BigNumber.from("34"),
          BigNumber.from("34"),
        ]);
      });

      describe("when one of the groups is deprecated", () => {
        beforeEach(async () => {
          await manager.deprecateGroup(groupAddresses[1]);
        });

        it("withdraws a small withdrawal from the deprecated group only", async () => {
          await manager.connect(depositor).withdraw(30);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([groupAddresses[1]]);
          expect(withdrawals).to.deep.equal([BigNumber.from("30")]);
        });

        it("withdraws a larger withdrawal from the deprecated group first, then the remaining groups", async () => {
          await manager.connect(depositor).withdraw(120);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([
            groupAddresses[1],
            groupAddresses[0],
            groupAddresses[2],
          ]);
          expect(withdrawals).to.deep.equal([
            BigNumber.from("100"),
            BigNumber.from("10"),
            BigNumber.from("10"),
          ]);
        });

        it("removes the deprecated group if it is no longer voted for", async () => {
          await manager.connect(depositor).withdraw(120);
          const deprecatedGroups = await manager.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([]);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(manager.connect(depositor).withdraw(120))
            .to.emit(manager, "GroupRemoved")
            .withArgs(groupAddresses[1]);
        });
      });
    });

    describe("when groups have unequal votes", () => {
      const withdrawals = [40, 100, 30];
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        await stakedCelo.mint(depositor.address, 170);
        await account.setTotalCelo(170);
      });

      it("takes a small withdrawal from the most voted validator only", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[1]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
      });

      it("takes a medium withdrawal from two validators only", async () => {
        await manager.connect(depositor).withdraw(70);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[0], groupAddresses[1]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("5"), BigNumber.from("65")]);
      });

      it("takes a medium withdrawal with overflow correctly", async () => {
        await manager.connect(depositor).withdraw(71);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[0], groupAddresses[1]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("5"), BigNumber.from("66")]);
      });

      it("distributes a large withdrawal across all validators", async () => {
        await manager.connect(depositor).withdraw(89);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([
          groupAddresses[2],
          groupAddresses[0],
          groupAddresses[1],
        ]);
        expect(withdrawals).to.deep.equal([
          BigNumber.from("3"),
          BigNumber.from("13"),
          BigNumber.from("73"),
        ]);
      });

      it("distributes a large deposit with overflow correctly", async () => {
        await manager.connect(depositor).withdraw(90);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([
          groupAddresses[2],
          groupAddresses[0],
          groupAddresses[1],
        ]);
        expect(withdrawals).to.deep.equal([
          BigNumber.from("3"),
          BigNumber.from("13"),
          BigNumber.from("74"),
        ]);
      });

      describe("when one of the groups is deprecated", () => {
        beforeEach(async () => {
          await manager.deprecateGroup(groupAddresses[0]);
        });

        it("takes a small withdrawal from the deprecated group only", async () => {
          await manager.connect(depositor).withdraw(30);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([groupAddresses[0]]);
          expect(withdrawals).to.deep.equal([BigNumber.from("30")]);
        });

        it("takes another small withdrawal from the deprecated group only", async () => {
          await manager.connect(depositor).withdraw(40);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([groupAddresses[0]]);
          expect(withdrawals).to.deep.equal([BigNumber.from("40")]);
        });

        it("removes the deprecated group if it is no longer voted for", async () => {
          await manager.connect(depositor).withdraw(40);
          const deprecatedGroups = await manager.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([]);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(manager.connect(depositor).withdraw(40))
            .to.emit(manager, "GroupRemoved")
            .withArgs(groupAddresses[0]);
        });

        it("takes a medium withdrawal first from deprecated group, then from most voted active group", async () => {
          await manager.connect(depositor).withdraw(110);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([groupAddresses[0], groupAddresses[1]]);
          expect(withdrawals).to.deep.equal([BigNumber.from("40"), BigNumber.from("70")]);
        });

        it("takes a large withdrawal from from deprecated group, then distributes correctly over active groups", async () => {
          await manager.connect(depositor).withdraw(120);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([
            groupAddresses[0],
            groupAddresses[2],
            groupAddresses[1],
          ]);
          expect(withdrawals).to.deep.equal([
            BigNumber.from("40"),
            BigNumber.from("5"),
            BigNumber.from("75"),
          ]);
        });

        it("distributes a large withdrawal with overflow correctly", async () => {
          await manager.connect(depositor).withdraw(121);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([
            groupAddresses[0],
            groupAddresses[2],
            groupAddresses[1],
          ]);
          expect(withdrawals).to.deep.equal([
            BigNumber.from("40"),
            BigNumber.from("5"),
            BigNumber.from("76"),
          ]);
        });
      });
    });

    describe("stCELO burning", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }

        await stakedCelo.mint(depositor.address, 100);
      });

      describe("when there are equal amount of CELO and stCELO in the system", () => {
        beforeEach(async () => {
          await account.setTotalCelo(200);
          await stakedCelo.mint(someone.address, 100);
        });

        it("calculates CELO 1:1 with stCELO", async () => {
          await manager.connect(depositor).withdraw(100);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          const celo = sum(withdrawals);
          expect(celo).to.eq(100);
        });

        it("burns the stCELO", async () => {
          await manager.connect(depositor).withdraw(100);
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(0);
        });

        it("calculates CELO 1:1 with stCELO for a different amount", async () => {
          await manager.connect(depositor).withdraw(10);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          const celo = sum(withdrawals);
          expect(celo).to.eq(10);
        });

        it("burns the stCELO", async () => {
          await manager.connect(depositor).withdraw(10);
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(90);
        });
      });

      describe("when there is more CELO than stCELO in the system", () => {
        beforeEach(async () => {
          await account.setTotalCelo(200);
        });

        it("calculates more stCELO than the input CELO", async () => {
          await manager.connect(depositor).withdraw(100);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          const celo = sum(withdrawals);
          expect(celo).to.eq(200);
        });

        it("burns the stCELO", async () => {
          await manager.connect(depositor).withdraw(100);
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(0);
        });

        it("calculates more stCELO than the input CELO for a different amount", async () => {
          await manager.connect(depositor).withdraw(10);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          const celo = sum(withdrawals);
          expect(celo).to.eq(20);
        });

        it("burns the stCELO", async () => {
          await manager.connect(depositor).withdraw(10);
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(90);
        });
      });

      describe("when there is less CELO than stCELO in the system", () => {
        beforeEach(async () => {
          await account.setTotalCelo(100);
          await stakedCelo.mint(someone.address, 100);
        });

        it("calculates less stCELO than the input CELO", async () => {
          await manager.connect(depositor).withdraw(100);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          const celo = sum(withdrawals);
          expect(celo).to.eq(50);
        });

        it("burns the stCELO", async () => {
          await manager.connect(depositor).withdraw(100);
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(0);
        });

        it("calculates less stCELO than the input CELO for a different amount", async () => {
          await manager.connect(depositor).withdraw(10);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          const celo = sum(withdrawals);
          expect(celo).to.eq(5);
        });

        it("burns the stCELO", async () => {
          await manager.connect(depositor).withdraw(10);
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(90);
        });
      });
    });
  });
});
