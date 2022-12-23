import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BigNumberJs from "bignumber.js";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { MockAccount__factory } from "../typechain-types/factories/MockAccount__factory";
import { MockLockedGold__factory } from "../typechain-types/factories/MockLockedGold__factory";
import { MockRegistry__factory } from "../typechain-types/factories/MockRegistry__factory";
import { MockStakedCelo__factory } from "../typechain-types/factories/MockStakedCelo__factory";
import { MockValidators__factory } from "../typechain-types/factories/MockValidators__factory";
import { MockVote__factory } from "../typechain-types/factories/MockVote__factory";
import { Manager } from "../typechain-types/Manager";
import { MockAccount } from "../typechain-types/MockAccount";
import { MockLockedGold } from "../typechain-types/MockLockedGold";
import { MockRegistry } from "../typechain-types/MockRegistry";
import { MockStakedCelo } from "../typechain-types/MockStakedCelo";
import { MockValidators } from "../typechain-types/MockValidators";
import { MockVote } from "../typechain-types/MockVote";
import {
  ADDRESS_ZERO,
  deregisterValidatorGroup,
  electGroup,
  electMinimumNumberOfValidators,
  getImpersonatedSigner,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorAndOnlyAffiliateToGroup,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
  removeMembersFromGroup,
  resetNetwork,
  updateGroupSlashingMultiplier,
} from "./utils";

const sum = (xs: BigNumber[]): BigNumber => xs.reduce((a, b) => a.add(b));

after(() => {
  hre.kit.stop();
});

describe("Manager", () => {
  let account: MockAccount;
  let stakedCelo: MockStakedCelo;
  let voteContract: MockVote;
  let lockedGoldContract: MockLockedGold;
  let validatorsContract: MockValidators;
  let registryContract: MockRegistry;

  let manager: Manager;
  let nonVote: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;

  let election: ElectionWrapper;
  let lockedGold: LockedGoldWrapper;
  let validators: ValidatorsWrapper;

  let owner: SignerWithAddress;
  let nonOwner: SignerWithAddress;
  let someone: SignerWithAddress;
  let mockSlasher: SignerWithAddress;
  let depositor: SignerWithAddress;
  let depositor2: SignerWithAddress;
  let voter: SignerWithAddress;
  let groups: SignerWithAddress[];
  let groupAddresses: string[];

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  before(async function () {
    this.timeout(100000);
    await resetNetwork();
    lockedGold = await hre.kit.contracts.getLockedGold();
    election = await hre.kit.contracts.getElection();
    validators = await hre.kit.contracts.getValidators();

    await hre.deployments.fixture("TestManager");
    manager = await hre.ethers.getContract("Manager");

    [owner] = await randomSigner(parseUnits("100"));
    [nonOwner] = await randomSigner(parseUnits("100"));
    [someone] = await randomSigner(parseUnits("100"));
    [mockSlasher] = await randomSigner(parseUnits("100"));
    [depositor] = await randomSigner(parseUnits("300"));
    [depositor2] = await randomSigner(parseUnits("300"));
    [voter] = await randomSigner(parseUnits("10000000000"));
    [nonVote] = await randomSigner(parseUnits("100000"));
    [nonStakedCelo] = await randomSigner(parseUnits("100"));
    [nonAccount] = await randomSigner(parseUnits("100"));

    const accountFactory: MockAccount__factory = (
      await hre.ethers.getContractFactory("MockAccount")
    ).connect(owner) as MockAccount__factory;
    account = await accountFactory.deploy();

    const lockedGoldFactory: MockLockedGold__factory = (
      await hre.ethers.getContractFactory("MockLockedGold")
    ).connect(owner) as MockLockedGold__factory;
    lockedGoldContract = lockedGoldFactory.attach(lockedGold.address);

    const validatorsFactory: MockValidators__factory = (
      await hre.ethers.getContractFactory("MockValidators")
    ).connect(owner) as MockValidators__factory;
    validatorsContract = validatorsFactory.attach(validators.address);

    const registryFactory: MockRegistry__factory = (
      await hre.ethers.getContractFactory("MockRegistry")
    ).connect(owner) as MockRegistry__factory;
    registryContract = registryFactory.attach(REGISTRY_ADDRESS);

    const stakedCeloFactory: MockStakedCelo__factory = (
      await hre.ethers.getContractFactory("MockStakedCelo")
    ).connect(owner) as MockStakedCelo__factory;
    stakedCelo = await stakedCeloFactory.deploy();

    const mockVoteFactory: MockVote__factory = (
      await hre.ethers.getContractFactory("MockVote")
    ).connect(owner) as MockVote__factory;
    voteContract = await mockVoteFactory.deploy();

    await manager.setDependencies(stakedCelo.address, account.address, voteContract.address);

    const accounts = await hre.kit.contracts.getAccounts();
    await accounts.createAccount().sendAndWaitForReceipt({
      from: voter.address,
    });
    await accounts.createAccount().sendAndWaitForReceipt({
      from: someone.address,
    });

    groups = [];
    groupAddresses = [];
    for (let i = 0; i < 11; i++) {
      const [group] = await randomSigner(parseUnits("21000"));
      groups.push(group);
      groupAddresses.push(group.address);
    }
    for (let i = 0; i < 11; i++) {
      if (i == 1) {
        // For groups[1] we register an extra validator so it has a higher voting limit.
        await registerValidatorGroup(groups[i], 2);
        const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
        await registerValidatorAndAddToGroupMembers(groups[i], validator, validatorWallet);
      } else {
        await registerValidatorGroup(groups[i], 1);
      }
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      await registerValidatorAndAddToGroupMembers(groups[i], validator, validatorWallet);
    }

    await electMinimumNumberOfValidators(groups, voter); // first 10 groups
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

    describe("when group is not registered", () => {
      it("reverts when trying to add an unregistered group", async () => {
        const [unregisteredGroup] = await randomSigner(parseUnits("100"));

        await expect(manager.activateGroup(unregisteredGroup.address)).revertedWith(
          `GroupNotEligible("${unregisteredGroup.address}")`
        );
      });
    });

    describe("when group has no members", () => {
      let noMemberedGroup: SignerWithAddress;
      beforeEach(async () => {
        [noMemberedGroup] = await randomSigner(parseUnits("21000"));
        await registerValidatorGroup(noMemberedGroup);
        const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
        await registerValidatorAndOnlyAffiliateToGroup(noMemberedGroup, validator, validatorWallet);
      });

      it("reverts when trying to add a group with no members", async () => {
        await expect(manager.activateGroup(noMemberedGroup.address)).revertedWith(
          `GroupNotEligible("${noMemberedGroup.address}")`
        );
      });
    });

    describe("when group is not elected", () => {
      it("reverts when trying to add non elected group", async () => {
        const nonElectedGroup = groups[10];
        await expect(manager.activateGroup(nonElectedGroup.address)).revertedWith(
          `GroupNotEligible("${nonElectedGroup.address}")`
        );
      });
    });

    describe("when group has 3 validators, but only 1 is elected.", () => {
      let gloup: SignerWithAddress;
      beforeEach(async () => {
        [gloup] = await randomSigner(parseUnits("31000"));
        await registerValidatorGroup(gloup);

        for (let i = 0; i < 3; i++) {
          const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));

          if (i === 2) {
            await registerValidatorAndAddToGroupMembers(gloup, validator, validatorWallet);
            await electGroup(gloup.address, someone);
          } else {
            await registerValidatorAndOnlyAffiliateToGroup(gloup, validator, validatorWallet);
          }
        }
      });

      it("emits a GroupActivated event", async () => {
        await expect(manager.activateGroup(gloup.address))
          .to.emit(manager, "GroupActivated")
          .withArgs(gloup.address);
      });
    });

    describe("when group has low slash multiplier", () => {
      let slashedGroup: SignerWithAddress;
      beforeEach(async () => {
        [slashedGroup] = await randomSigner(parseUnits("21000"));
        await registerValidatorGroup(slashedGroup);
        const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
        await registerValidatorAndAddToGroupMembers(slashedGroup, validator, validatorWallet);
        await electGroup(slashedGroup.address, someone);

        await updateGroupSlashingMultiplier(
          registryContract,
          lockedGoldContract,
          validatorsContract,
          slashedGroup,
          mockSlasher
        );
      });

      it("reverts when trying to add slashed group", async () => {
        await expect(manager.activateGroup(slashedGroup.address)).revertedWith(
          `GroupNotEligible("${slashedGroup.address}")`
        );
      });
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
        additionalGroup = groups[10];
        await electGroup(additionalGroup.address, someone);

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

    describe("When 3 active groups", () => {
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

        it("adds the group to the deprecated array", async () => {
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

        it("does not add the group to the deprecated array", async () => {
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
  });

  describe("#disallowStrategy()", () => {
    it("reverts when no active groups", async () => {
      await manager.allowStrategy(groupAddresses[3]);
      await expect(manager.disallowStrategy(groupAddresses[3])).revertedWith(`NoActiveGroups()`);
    });

    describe("When 2 active groups", () => {
      let allowedStrategy: SignerWithAddress;
      beforeEach(async () => {
        allowedStrategy = groups[2];
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groups[i].address);
        }
      });

      describe("when the group is allowed", () => {
        let allowedStrategyDeposit: BigNumber;

        beforeEach(async () => {
          await account.setCeloForGroup(allowedStrategy.address, 100);
          allowedStrategyDeposit = parseUnits("1");
          await manager.allowStrategy(allowedStrategy.address);
          await manager.connect(depositor).changeStrategy(allowedStrategy.address);
          await manager.connect(depositor).deposit({ value: allowedStrategyDeposit });
        });

        it("added group to allowed strategies", async () => {
          const activeGroups = await manager.connect(depositor).getGroups();
          const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
          const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(deprecatedGroups).to.deep.eq([]);
          expect(allowedStrategies).to.deep.eq([allowedStrategy.address]);
        });

        it("removes the group from the groups array", async () => {
          await manager.disallowStrategy(allowedStrategy.address);
          const activeGroups = await manager.connect(depositor).getGroups();
          const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
          const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(deprecatedGroups).to.deep.eq([]);
          expect(allowedStrategies).to.deep.eq([]);
        });

        it("emits a StrategyDisallowed event", async () => {
          await expect(manager.disallowStrategy(allowedStrategy.address))
            .to.emit(manager, "StrategyDisallowed")
            .withArgs(allowedStrategy.address);
        });

        it("reverts when disallowing a not allowed strategy", async () => {
          await expect(manager.disallowStrategy(groupAddresses[3])).revertedWith(
            `StrategyNotAllowed("${groupAddresses[3]}")`
          );
        });

        it("cannot be called by a non owner", async () => {
          await expect(
            manager.connect(nonOwner).disallowStrategy(allowedStrategy.address)
          ).revertedWith("Ownable: caller is not the owner");
        });

        it("should schedule transfers to default strategy", async () => {
          await manager.disallowStrategy(allowedStrategy.address);
          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          expect(lastTransferFromGroups).to.deep.eq([allowedStrategy.address]);
          expect(lastTransferFromVotes).to.deep.eq([allowedStrategyDeposit]);

          expect(lastTransferToGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(lastTransferToVotes.length).to.eq(2);
          expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).to.deep.eq(
            allowedStrategyDeposit
          );
        });
      });
    });
  });

  describe("#deprecateUnhealthyGroup()", () => {
    let deprecatedGroup: SignerWithAddress;

    beforeEach(async () => {
      deprecatedGroup = groups[1];
      for (let i = 0; i < 3; i++) {
        await manager.activateGroup(groups[i].address);
      }
    });

    it("should revert when group is healthy", async () => {
      await expect(manager.deprecateUnhealthyGroup(groupAddresses[1])).revertedWith(
        `HealthyGroup("${groupAddresses[1]}")`
      );
    });

    describe("when the group is not elected", () => {
      beforeEach(async () => {
        const groupVotes = await election.getVotesForGroupByAccount(
          voter.address,
          deprecatedGroup.address
        );

        const revokeTx = await election.revoke(
          voter.address,
          deprecatedGroup.address,
          groupVotes.active
        );
        for (let i = 0; i < revokeTx.length; i++) {
          await revokeTx[i].sendAndWaitForReceipt({ from: voter.address });
        }
        await electGroup(groups[10].address, someone);
      });

      it("should deprecate group", async () => {
        await expect(await manager.deprecateUnhealthyGroup(groupAddresses[1]))
          .to.emit(manager, "GroupDeprecated")
          .withArgs(groupAddresses[1]);
      });
    });

    describe("when the group is not registered", () => {
      beforeEach(async () => {
        await deregisterValidatorGroup(deprecatedGroup);
      });

      it("should deprecate group", async () => {
        await expect(await manager.deprecateUnhealthyGroup(deprecatedGroup.address))
          .to.emit(manager, "GroupDeprecated")
          .withArgs(deprecatedGroup.address);
      });
    });

    describe("when the group has no members", () => {
      // if voting for a group that has no members, i get no rewards.
      beforeEach(async () => {
        await removeMembersFromGroup(deprecatedGroup);
      });

      it("should deprecate group", async () => {
        await expect(await manager.deprecateUnhealthyGroup(deprecatedGroup.address))
          .to.emit(manager, "GroupDeprecated")
          .withArgs(deprecatedGroup.address);
      });
    });

    describe("when group has 3 validators, but only 1 is elected.", () => {
      let gloups: SignerWithAddress;
      beforeEach(async () => {
        [gloups] = await randomSigner(parseUnits("21000"));
        await registerValidatorGroup(gloups);

        for (let i = 0; i < 3; i++) {
          const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));

          if (i === 2) {
            await registerValidatorAndAddToGroupMembers(gloups, validator, validatorWallet);
            await electGroup(gloups.address, someone);
          } else {
            await registerValidatorAndOnlyAffiliateToGroup(gloups, validator, validatorWallet);
          }
        }
        await manager.activateGroup(gloups.address);
      });

      it("should revert with Healthy group message", async () => {
        await expect(manager.deprecateUnhealthyGroup(gloups.address)).revertedWith(
          `HealthyGroup("${gloups.address}")`
        );
      });
    });

    describe("when the group is slashed", () => {
      beforeEach(async () => {
        await updateGroupSlashingMultiplier(
          registryContract,
          lockedGoldContract,
          validatorsContract,
          deprecatedGroup,
          mockSlasher
        );
      });

      it("should deprecate group", async () => {
        await expect(await manager.deprecateUnhealthyGroup(deprecatedGroup.address))
          .to.emit(manager, "GroupDeprecated")
          .withArgs(groupAddresses[1]);
      });
    });
  });

  describe("#deposit()", () => {
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
        // given 12 validators registered and elected, as above, we have the following
        // limits for the first three groups:
        // group[0] and group[2]: 95864 Locked CELO
        // group[1]: 143797 Locked CELO
        // and the remaining receivable votes are [40, 100, 200] (in CELO) for
        // the three groups, respectively.
        const votes = [parseUnits("95824"), parseUnits("143697"), parseUnits("95664")];

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

    describe("When voted for allowed validator group", () => {
      beforeEach(async () => {
        await manager.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor).deposit({ value: 100 });
      });

      it("should add group to allowed strategies", async () => {
        const activeGroups = await manager.connect(depositor).getGroups();
        const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect(activeGroups.length).to.eq(0);
        expect(deprecatedGroups.length).to.eq(0);
        expect(allowedStrategies.length).to.eq(1);
        expect(allowedStrategies[0]).to.eq(groupAddresses[0]);
      });

      it("should schedule votes for allowed group", async () => {
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal(groupAddresses.slice(0, 1));
        expect(votes).to.deep.equal([BigNumber.from("100")]);
      });

      it("should mint 1:1 stCelo", async () => {
        const stCelo = await stakedCelo.balanceOf(depositor.address);
        expect(stCelo).to.eq(100);
      });
    });

    describe("When voted for originally valid validator group that is no longer valid", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }

        await manager.allowStrategy(groupAddresses[4]);
        await manager.connect(depositor).changeStrategy(groupAddresses[4]);
        await account.setCeloForGroup(groupAddresses[4], 100);
        await updateGroupSlashingMultiplier(
          registryContract,
          lockedGoldContract,
          validatorsContract,
          groups[4],
          mockSlasher
        );
        await manager.connect(depositor).deposit({ value: 100 });
      });

      it("should not add group to allowed strategies", async () => {
        const activeGroups = await manager.connect(depositor).getGroups();
        const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect(activeGroups).to.deep.eq(groupAddresses.slice(0, 3));
        expect(deprecatedGroups).to.deep.eq([]);
        expect(allowedStrategies).to.deep.eq([groupAddresses[4]]);
      });

      it("should schedule votes for default groups", async () => {
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal(groupAddresses.slice(0, 3));
        expect(votes).to.deep.equal([
          BigNumber.from("34"),
          BigNumber.from("33"),
          BigNumber.from("33"),
        ]);
      });

      it("should not schedule transfers to default strategy when no balance for allowed strategy", async () => {
        await manager.disallowStrategy(groupAddresses[4]);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([]);
        expect(lastTransferFromVotes).to.deep.eq([]);

        expect(lastTransferToGroups).to.deep.eq([]);
        expect(lastTransferToVotes).to.deep.eq([]);
      });

      it("should mint 1:1 stCelo", async () => {
        const stCelo = await stakedCelo.balanceOf(depositor.address);
        expect(stCelo).to.eq(100);
      });
    });

    describe("When voted for deprecated group", () => {
      const depositedValue = 1000;
      let allowedStrategyAddress: string;

      describe("Disallow strategy - group other than active", () => {
        beforeEach(async () => {
          for (let i = 0; i < 2; i++) {
            await manager.activateGroup(groupAddresses[i]);
            await account.setCeloForGroup(groupAddresses[i], 100);
          }
          allowedStrategyAddress = groupAddresses[2];

          await manager.allowStrategy(allowedStrategyAddress);
          await manager.changeStrategy(allowedStrategyAddress);
          await manager.deposit({ value: depositedValue });
          await account.setCeloForGroup(allowedStrategyAddress, depositedValue);
          await manager.disallowStrategy(allowedStrategyAddress);
        });

        it("should schedule votes for default strategy", async () => {
          const secondDepositedValue = 1000;
          await manager.deposit({ value: secondDepositedValue });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect([groupAddresses[0], groupAddresses[1]]).to.deep.eq(votedGroups);
          expect(2).to.eq(votes.length);
          expect(secondDepositedValue).to.eq(votes[0].add(votes[1]));
        });
      });

      describe("Disallow strategy - group one of active", () => {
        beforeEach(async () => {
          for (let i = 0; i < 3; i++) {
            await manager.activateGroup(groupAddresses[i]);
            await account.setCeloForGroup(groupAddresses[i], 100);
          }
          allowedStrategyAddress = groupAddresses[0];

          await manager.allowStrategy(allowedStrategyAddress);
          await manager.changeStrategy(allowedStrategyAddress);
          await manager.deposit({ value: depositedValue });
          await account.setCeloForGroup(allowedStrategyAddress, depositedValue);
          await manager.disallowStrategy(allowedStrategyAddress);
        });

        it("should schedule votes for default strategy", async () => {
          const secondDepositedValue = 1000;
          await manager.deposit({ value: secondDepositedValue });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect([groupAddresses[1], groupAddresses[2]]).to.deep.eq(votedGroups);
          expect(2).to.eq(votes.length);
          expect(secondDepositedValue).to.eq(votes[0].add(votes[1]));
        });
      });
    });

    describe("When we have 2 active validator groups", () => {
      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }
      });

      describe("When voted for allowed validator group which is not in active groups", () => {
        beforeEach(async () => {
          await manager.allowStrategy(groupAddresses[2]);
          await manager.connect(depositor).changeStrategy(groupAddresses[2]);
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should add group to allowed strategies", async () => {
          const activeGroups = await manager.connect(depositor).getGroups();
          const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
          const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(deprecatedGroups).to.deep.eq([]);
          expect(allowedStrategies).to.deep.eq([groupAddresses[2]]);
        });

        it("should schedule votes for allowed group", async () => {
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[2]]);
          expect(votes).to.deep.equal([BigNumber.from("100")]);
        });

        it("should mint 1:1 stCelo", async () => {
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(100);
        });
      });

      describe("When voted for allowed validator group which is in active groups", () => {
        let allowedStrategyAddress: string;
        beforeEach(async () => {
          allowedStrategyAddress = groupAddresses[0];
          await manager.allowStrategy(allowedStrategyAddress);
          await manager.connect(depositor).changeStrategy(allowedStrategyAddress);
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should add group to allowed strategies", async () => {
          const activeGroups = await manager.connect(depositor).getGroups();
          const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
          const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(deprecatedGroups).to.deep.eq([]);
          expect(allowedStrategies).to.deep.eq([allowedStrategyAddress]);
        });

        it("should schedule votes for allowed group", async () => {
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[0]]);
          expect(votes).to.deep.equal([BigNumber.from("100")]);
        });

        it("should mint 1:1 stCelo", async () => {
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(100);
        });
      });
    });
  });

  describe("#withdraw()", () => {
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

    describe("when all groups have equal votes and one of the groups was voted for as for allowed group", () => {
      let allowedStrategy: SignerWithAddress;
      beforeEach(async () => {
        allowedStrategy = groups[0];
        const allowedStrategyWithdrawal = 100;
        for (let i = 0; i < 3; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }

        await account.setCeloForGroup(allowedStrategy.address, 100 + allowedStrategyWithdrawal);

        await manager.allowStrategy(allowedStrategy.address);
        await manager.connect(depositor2).changeStrategy(allowedStrategy.address);
        await manager.connect(depositor2).deposit({ value: allowedStrategyWithdrawal });

        await stakedCelo.mint(depositor.address, 300);
        await account.setTotalCelo(300 + allowedStrategyWithdrawal);
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

      describe("when one of the non allowed strategies is deprecated", () => {
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

      describe("when allowed group is deprecated", () => {
        beforeEach(async () => {
          await manager.deprecateGroup(allowedStrategy.address);
        });

        it("withdraws a small withdrawal from the deprecated group only", async () => {
          await manager.connect(depositor).withdraw(30);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([allowedStrategy.address]);
          expect(withdrawals).to.deep.equal([BigNumber.from("30")]);
        });

        it("withdraws a larger withdrawal from the deprecated group first, then the remaining groups", async () => {
          await manager.connect(depositor).withdraw(220);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([
            allowedStrategy.address,
            groupAddresses[2],
            groupAddresses[1],
          ]);
          expect(withdrawals).to.deep.equal([
            BigNumber.from("200"),
            BigNumber.from("10"),
            BigNumber.from("10"),
          ]);
        });

        it("removes the deprecated group if it is no longer voted for", async () => {
          await manager.connect(depositor).withdraw(220);
          const deprecatedGroups = await manager.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([]);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(manager.connect(depositor).withdraw(220))
            .to.emit(manager, "GroupRemoved")
            .withArgs(allowedStrategy.address);
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
          const [, withdrawals] = await account.getLastScheduledWithdrawals();
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
          const [, withdrawals] = await account.getLastScheduledWithdrawals();
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
          const [, withdrawals] = await account.getLastScheduledWithdrawals();
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
          const [, withdrawals] = await account.getLastScheduledWithdrawals();
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
          const [, withdrawals] = await account.getLastScheduledWithdrawals();
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
          const [, withdrawals] = await account.getLastScheduledWithdrawals();
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

    describe("When voted for allowed validator group - no active groups", () => {
      beforeEach(async () => {
        await manager.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor).deposit({ value: 100 });
        await account.setCeloForGroup(groupAddresses[0], 100);
      });

      it("should withdraw less than originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[0]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
      });

      it("should withdraw same amount as originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[0]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("100")]);
      });

      it("should revert when withdraw more amount than originally deposited from allowed group", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `GroupNotBalancedOrNotEnoughStCelo("${groupAddresses[0]}")`
        );
      });
    });

    describe("When there are other active groups besides allowed validator group - allowed is different from active", () => {
      const withdrawals = [40, 50];
      const allowedStrategyWithdrawal = 100;
      let allowedStrategy: SignerWithAddress;

      beforeEach(async () => {
        allowedStrategy = groups[2];
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        await account.setCeloForGroup(allowedStrategy.address, allowedStrategyWithdrawal);

        await manager.allowStrategy(allowedStrategy.address);
        await manager.connect(depositor).changeStrategy(allowedStrategy.address);
        await manager.connect(depositor).deposit({ value: allowedStrategyWithdrawal });
      });

      it("added group to allowed strategies", async () => {
        const activeGroups = await manager.connect(depositor).getGroups();
        const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(deprecatedGroups).to.deep.eq([]);
        expect(allowedStrategies).to.deep.eq([allowedStrategy.address]);
      });

      it("should withdraw less than originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([allowedStrategy.address]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect(allowedStrategies).to.deep.eq([allowedStrategy.address]);
      });

      it("should withdraw same amount as originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect([allowedStrategy.address]).to.deep.equal(withdrawnGroups);
        expect([BigNumber.from("100")]).to.deep.equal(withdrawals);
        const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect([]).to.deep.eq(allowedStrategies);
        expect([]).to.deep.eq(deprecatedGroups);
      });

      it("should withdraw same amount as originally deposited from active groups after strategy is disallowed", async () => {
        await manager.disallowStrategy(allowedStrategy.address);
        const [, , lastTransferToGroups, lastTransferToVotes] =
          await account.getLastTransferValues();

        for (let i = 0; i < lastTransferToGroups.length; i++) {
          await account.setCeloForGroup(
            groupAddresses[i],
            BigNumber.from(withdrawals[i]).add(lastTransferToVotes[i])
          );
        }
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, groupWithdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal(groupAddresses.slice(0, 2));
        expect(groupWithdrawals).to.deep.equal([BigNumber.from("50"), BigNumber.from("50")]);
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect(allowedStrategies).to.deep.eq([]);
      });

      it("should revert when withdraw more amount than originally deposited from allowed group", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `GroupNotBalancedOrNotEnoughStCelo("${allowedStrategy.address}")`
        );
      });
    });

    describe("When there are other active groups besides allowed validator group - allowed is same from active", () => {
      const withdrawals = [40, 50];
      const allowedStrategyWithdrawal = 100;
      let allowedStrategy: SignerWithAddress;

      beforeEach(async () => {
        allowedStrategy = groups[1];
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        await account.setCeloForGroup(allowedStrategy.address, allowedStrategyWithdrawal);

        await manager.allowStrategy(allowedStrategy.address);
        await manager.connect(depositor).changeStrategy(allowedStrategy.address);
        await manager.connect(depositor).deposit({ value: allowedStrategyWithdrawal });
      });

      it("added group to allowed strategies", async () => {
        const activeGroups = await manager.connect(depositor).getGroups();
        const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(deprecatedGroups).to.deep.eq([]);
        expect(allowedStrategies).to.deep.eq([allowedStrategy.address]);
      });

      it("should withdraw less than originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([allowedStrategy.address]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
        const activeGroups = await manager.connect(depositor).getGroups();
        const deprecatedGroups = await manager.connect(depositor).getDeprecatedGroups();
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(allowedStrategies).to.deep.eq([allowedStrategy.address]);
        expect(deprecatedGroups).to.deep.eq([]);
      });

      it("should withdraw same amount as originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([allowedStrategy.address]);
        expect(withdrawals).to.deep.equal([BigNumber.from("100")]);
        const activeGroups = await manager.connect(depositor).getGroups();
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(allowedStrategies).to.deep.eq([]);
      });

      it("should revert when withdraw more amount than originally deposited from allowed group", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `GroupNotBalancedOrNotEnoughStCelo("${allowedStrategy.address}")`
        );
      });
    });

    describe("When there are other active groups besides allowed validator group - allowed is one of the active groups", () => {
      const withdrawals = [40, 50];
      const allowedStrategyWithdrawal = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        await account.setCeloForGroup(
          groupAddresses[1],
          withdrawals[1] + allowedStrategyWithdrawal
        );

        await manager.allowStrategy(groupAddresses[1]);
        await manager.connect(depositor).changeStrategy(groupAddresses[1]);
        await manager.connect(depositor).deposit({ value: allowedStrategyWithdrawal });
      });

      it("should withdraw less than originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[1]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
      });

      it("should withdraw same amount as originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[1]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("100")]);
      });

      it("should revert when withdraw more amount than originally deposited from allowed group", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `CantWithdrawAccordingToStrategy("${groupAddresses[1]}")`
        );
      });
    });
  });

  describe("#setDependencies()", () => {
    let ownerSigner: SignerWithAddress;

    before(async () => {
      const managerOwner = await manager.owner();
      ownerSigner = await getImpersonatedSigner(managerOwner);
    });

    it("reverts with zero stCelo address", async () => {
      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(ADDRESS_ZERO, nonAccount.address, nonVote.address)
      ).revertedWith("stakedCelo null address");
    });

    it("reverts with zero account address", async () => {
      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(nonStakedCelo.address, ADDRESS_ZERO, nonVote.address)
      ).revertedWith("account null address");
    });

    it("reverts with zero vote address", async () => {
      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(nonStakedCelo.address, nonAccount.address, ADDRESS_ZERO)
      ).revertedWith("vote null address");
    });

    it("sets the vote contract", async () => {
      await manager
        .connect(ownerSigner)
        .setDependencies(nonStakedCelo.address, nonAccount.address, nonVote.address);
      const newVoteContract = await manager.voteContract();
      expect(newVoteContract).to.eq(nonVote.address);
    });

    it("emits a VoteContractSet event", async () => {
      const managerOwner = await manager.owner();
      const ownerSigner = await getImpersonatedSigner(managerOwner);

      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(nonStakedCelo.address, nonAccount.address, nonVote.address)
      )
        .to.emit(manager, "VoteContractSet")
        .withArgs(nonVote.address);
    });

    it("cannot be called by a non-Owner account", async () => {
      await expect(
        manager
          .connect(nonOwner)
          .setDependencies(nonStakedCelo.address, nonAccount.address, nonVote.address)
      ).revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("#voteProposal()", () => {
    const proposalId = 1;
    const index = 0;
    const yes = 10;
    const no = 20;
    const abstain = 30;

    it("should call all subsequent contracts correctly", async () => {
      await manager.voteProposal(proposalId, index, yes, no, abstain);

      const stCeloLockedBalance = await stakedCelo.lockedBalance();
      expect(stCeloLockedBalance).to.eq(BigNumber.from(yes + no + abstain));

      const voteProposalIdVoted = await voteContract.proposalId();
      const voteYesVotesVoted = await voteContract.totalYesVotes();
      const voteNoVotesVoted = await voteContract.totalNoVotes();
      const voteAbstainVoteVoted = await voteContract.totalAbstainVotes();

      const accountProposalIdVoted = await account.proposalIdVoted();
      const accountIndexVoted = await account.indexVoted();
      const accountYesVotesVoted = await account.yesVotesVoted();
      const accountNoVotesVoted = await account.noVotesVoted();
      const accountAbstainVoteVoted = await account.abstainVoteVoted();

      expect(voteProposalIdVoted).to.eq(BigNumber.from(proposalId));
      expect(voteYesVotesVoted).to.eq(BigNumber.from(yes));
      expect(voteNoVotesVoted).to.eq(BigNumber.from(no));
      expect(voteAbstainVoteVoted).to.eq(BigNumber.from(abstain));

      expect(accountProposalIdVoted).to.eq(BigNumber.from(proposalId));
      expect(accountIndexVoted).to.eq(BigNumber.from(index));
      expect(accountYesVotesVoted).to.eq(BigNumber.from(yes));
      expect(accountNoVotesVoted).to.eq(BigNumber.from(no));
      expect(accountAbstainVoteVoted).to.eq(BigNumber.from(abstain));
    });
  });

  describe("#revokeVotes()", () => {
    const proposalId = 1;
    const index = 0;
    const yes = 10;
    const no = 20;
    const abstain = 30;

    it("should call all subsequent contracts correctly", async () => {
      await voteContract.setVotes(yes, no, abstain);
      await manager.revokeVotes(proposalId, index);

      const voteProposalIdVoted = await voteContract.revokeProposalId();

      const accountProposalIdVoted = await account.proposalIdVoted();
      const accountIndexVoted = await account.indexVoted();
      const accountYesVotesVoted = await account.yesVotesVoted();
      const accountNoVotesVoted = await account.noVotesVoted();
      const accountAbstainVoteVoted = await account.abstainVoteVoted();

      expect(voteProposalIdVoted).to.eq(BigNumber.from(proposalId));

      expect(accountProposalIdVoted).to.eq(BigNumber.from(proposalId));
      expect(accountIndexVoted).to.eq(BigNumber.from(index));
      expect(accountYesVotesVoted).to.eq(BigNumber.from(yes));
      expect(accountNoVotesVoted).to.eq(BigNumber.from(no));
      expect(accountAbstainVoteVoted).to.eq(BigNumber.from(abstain));
    });
  });

  describe("#unlockBalance()", () => {
    it("should call all subsequent contracts correctly", async () => {
      await manager.unlockBalance(nonVote.address);

      const stCeloUnlockedFor = await stakedCelo.unlockedBalanceFor();
      expect(stCeloUnlockedFor).to.eq(nonVote.address);
    });
  });

  describe("#updateHistoryAndReturnLockedStCeloInVoting()", () => {
    it("should call all subsequent contracts correctly", async () => {
      await manager.updateHistoryAndReturnLockedStCeloInVoting(nonVote.address);

      const updatedHistoryFor = await voteContract.updatedHistoryFor();
      expect(updatedHistoryFor).to.eq(nonVote.address);
    });
  });

  describe("#transfer()", () => {
    let stakedCeloSigner: SignerWithAddress;

    beforeEach(async () => {
      stakedCeloSigner = await getImpersonatedSigner(stakedCelo.address);
      await nonVote.sendTransaction({ value: parseUnits("1"), to: stakedCeloSigner.address });
    });

    describe("When depositor voted for default strategy", () => {
      const withdrawals = [40, 50];
      let defaultGroupDeposit: BigNumber;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        defaultGroupDeposit = parseUnits("1");
        await manager.connect(depositor).deposit({ value: defaultGroupDeposit });
      });

      it("should not schedule any transfers if both account use default strategy", async () => {
        await manager.connect(stakedCeloSigner).transfer(depositor.address, depositor2.address, 10);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups.length).to.eq(0);
        expect(lastTransferFromVotes.length).to.eq(0);
        expect(lastTransferToGroups.length).to.eq(0);
        expect(lastTransferToVotes.length).to.eq(0);
      });

      it("should not schedule any transfers if both account use default strategy (depositor2 also deposited)", async () => {
        const defaultGroupDeposit = 150;
        await manager.connect(depositor2).deposit({ value: defaultGroupDeposit });

        await manager.connect(stakedCeloSigner).transfer(depositor.address, depositor2.address, 10);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups.length).to.eq(0);
        expect(lastTransferFromVotes.length).to.eq(0);
        expect(lastTransferToGroups.length).to.eq(0);
        expect(lastTransferToVotes.length).to.eq(0);
      });

      it("should schedule transfers if default strategy => allowed strategy", async () => {
        const allowedStrategyDeposit = 10;
        const allowedStrategyAddress = groupAddresses[2];

        await manager.allowStrategy(allowedStrategyAddress);
        await manager.connect(depositor2).changeStrategy(allowedStrategyAddress);
        await manager.connect(depositor2).deposit({ value: allowedStrategyDeposit });

        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor.address, depositor2.address, defaultGroupDeposit);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(lastTransferFromVotes.length).to.eq(2);
        expect(lastTransferFromVotes[0].add(lastTransferFromVotes[1])).to.eq(defaultGroupDeposit);

        expect(lastTransferToGroups).to.deep.eq([allowedStrategyAddress]);
        expect(lastTransferToVotes).to.deep.eq([defaultGroupDeposit]);
      });
    });

    describe("When depositor voted for allowed strategy", () => {
      const withdrawals = [40, 50];
      let allowedStrategyAddress: string;
      let allowedStrategyDeposit: BigNumber;

      beforeEach(async () => {
        allowedStrategyAddress = groupAddresses[2];
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        allowedStrategyDeposit = BigNumber.from(100);
        await manager.allowStrategy(allowedStrategyAddress);
        await manager.connect(depositor).changeStrategy(allowedStrategyAddress);
        await manager.connect(depositor).deposit({ value: allowedStrategyDeposit });
      });

      it("should not schedule any transfers if second account also voted for same allowed group", async () => {
        const differentallowedStrategyDeposit = parseUnits("1");
        await manager.connect(depositor2).changeStrategy(allowedStrategyAddress);
        await manager.connect(depositor2).deposit({ value: differentallowedStrategyDeposit });

        await manager.connect(stakedCeloSigner).transfer(depositor.address, depositor2.address, 10);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups.length).to.eq(0);
        expect(lastTransferFromVotes.length).to.eq(0);
        expect(lastTransferToGroups.length).to.eq(0);
        expect(lastTransferToVotes.length).to.eq(0);
      });

      it("should schedule transfers if allowed strategy => default strategy", async () => {
        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor.address, depositor2.address, allowedStrategyDeposit);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([allowedStrategyAddress]);
        expect(lastTransferFromVotes).to.deep.eq([allowedStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(lastTransferToVotes.length).to.eq(2);
        expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).to.eq(allowedStrategyDeposit);
      });

      it("should schedule transfers if allowed strategy => different allowed strategy", async () => {
        const differentallowedStrategyDeposit = parseUnits("1");
        await manager.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor2).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor2).deposit({ value: differentallowedStrategyDeposit });

        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor2.address, depositor.address, differentallowedStrategyDeposit);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0]]);
        expect(lastTransferFromVotes).to.deep.eq([differentallowedStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([allowedStrategyAddress]);
        expect(lastTransferToVotes).to.deep.eq([differentallowedStrategyDeposit]);
      });

      it("should schedule transfers to default if different allowed strategy was disallowed", async () => {
        const differentallowedStrategyDeposit = BigNumber.from(100);
        const differentallowedStrategyAddress = groupAddresses[0];
        await manager.disallowStrategy(allowedStrategyAddress);
        await manager.allowStrategy(differentallowedStrategyAddress);
        await manager.connect(depositor2).changeStrategy(differentallowedStrategyAddress);
        await manager.connect(depositor2).deposit({ value: differentallowedStrategyDeposit });
        await account.setCeloForGroup(
          differentallowedStrategyAddress,
          differentallowedStrategyDeposit
        );

        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor2.address, depositor.address, differentallowedStrategyDeposit);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([differentallowedStrategyAddress]);
        expect(lastTransferFromVotes).to.deep.eq([differentallowedStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(lastTransferToVotes.length).to.eq(2);
        expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).to.eq(allowedStrategyDeposit);
      });

      it("should schedule transfers from default if allowed strategy was disallowed", async () => {
        const differentallowedStrategyDeposit = BigNumber.from(1000);
        const differentallowedStrategyAddress = groupAddresses[0];
        await manager.allowStrategy(differentallowedStrategyAddress);
        await manager.connect(depositor2).changeStrategy(differentallowedStrategyAddress);
        await manager.connect(depositor2).deposit({ value: differentallowedStrategyDeposit });
        await manager.disallowStrategy(differentallowedStrategyAddress);
        await account.setCeloForGroup(
          differentallowedStrategyAddress,
          differentallowedStrategyDeposit
        );

        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor2.address, depositor.address, differentallowedStrategyDeposit);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([groupAddresses[1], groupAddresses[0]]);
        expect(lastTransferFromVotes.length).to.eq(2);
        expect(lastTransferFromVotes[0].add(lastTransferFromVotes[1])).to.deep.eq(
          differentallowedStrategyDeposit
        );

        expect(lastTransferToGroups).to.deep.eq([allowedStrategyAddress]);
        expect(lastTransferToVotes).to.deep.eq([differentallowedStrategyDeposit]);
      });
    });
  });

  describe("#changeStrategy()", () => {
    const withdrawals = [40, 50];
    let allowedStrategyAddress: string;

    beforeEach(async () => {
      allowedStrategyAddress = groupAddresses[2];
      for (let i = 0; i < 2; i++) {
        await manager.activateGroup(groupAddresses[i]);
        await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
      }
    });

    it("should revert when not valid group", async () => {
      const slashedGroup = groups[0];
      await manager.allowStrategy(slashedGroup.address);
      await updateGroupSlashingMultiplier(
        registryContract,
        lockedGoldContract,
        validatorsContract,
        slashedGroup,
        mockSlasher
      );
      await expect(manager.changeStrategy(slashedGroup.address)).revertedWith(
        `GroupNotEligible("${slashedGroup.address}")`
      );
    });

    it("should revert when not allowed group", async () => {
      await expect(manager.changeStrategy(groupAddresses[0])).revertedWith(
        `GroupNotEligible("${groupAddresses[0]}")`
      );
    });

    describe("When changing with no previous stCelo", () => {
      beforeEach(async () => {
        await manager.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
      });

      it("should add group to allowed strategies", async () => {
        const allowedStrategies = await manager.connect(depositor).getAllowedStrategies();
        expect([groupAddresses[0]]).to.deep.eq(allowedStrategies);
      });

      it("should change account strategy ", async () => {
        const strategy = await manager.connect(depositor).getAccountStrategy(depositor.address);
        expect(groupAddresses[0]).to.eq(strategy);
      });
    });

    describe("When depositor voted for allowed strategy", () => {
      let allowedStrategyDeposit: BigNumber;

      beforeEach(async () => {
        allowedStrategyDeposit = parseUnits("2");
        await manager.allowStrategy(allowedStrategyAddress);
        await manager.changeStrategy(allowedStrategyAddress);
        await manager.deposit({ value: allowedStrategyDeposit });
      });

      it("should schedule nothing when trying to change to same allowed strategy", async () => {
        await manager.changeStrategy(allowedStrategyAddress);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([]);
        expect(lastTransferFromVotes).to.deep.eq([]);
        expect(lastTransferToGroups).to.deep.eq([]);
        expect(lastTransferToVotes).to.deep.eq([]);
      });

      it("should schedule transfers when changing to different allowed strategy", async () => {
        const differentallowedStrategy = groupAddresses[0];

        await manager.allowStrategy(differentallowedStrategy);
        await manager.changeStrategy(differentallowedStrategy);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect([allowedStrategyAddress]).to.deep.eq(lastTransferFromGroups);
        expect([allowedStrategyDeposit]).to.deep.eq(lastTransferFromVotes);
        expect([differentallowedStrategy]).to.deep.eq(lastTransferToGroups);
        expect([allowedStrategyDeposit]).to.deep.eq(lastTransferToVotes);
      });

      it("should schedule transfers when changing to default strategy", async () => {
        await manager.changeStrategy(ADDRESS_ZERO);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([allowedStrategyAddress]);
        expect(lastTransferFromVotes).to.deep.eq([allowedStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(lastTransferToVotes.length).to.eq(2);
        expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).eq(allowedStrategyDeposit);
      });
    });

    describe("When depositor voted for default strategy", () => {
      let defaultGroupDeposit: BigNumber;

      beforeEach(async () => {
        defaultGroupDeposit = parseUnits("2");
        await manager.deposit({ value: defaultGroupDeposit });
      });

      it("should schedule nothing when changing to default strategy", async () => {
        await manager.changeStrategy(ADDRESS_ZERO);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([]);
        expect(lastTransferFromVotes).to.deep.eq([]);
        expect(lastTransferToGroups).to.deep.eq([]);
        expect(lastTransferToVotes).to.deep.eq([]);
      });

      it("should schedule transfers when changing to allowed strategy", async () => {
        await manager.allowStrategy(allowedStrategyAddress);
        await manager.changeStrategy(allowedStrategyAddress);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(lastTransferFromVotes.length).to.eq(2);
        expect(lastTransferFromVotes[0].add(lastTransferFromVotes[1])).eq(defaultGroupDeposit);

        expect(lastTransferToGroups).to.deep.eq([allowedStrategyAddress]);
        expect(lastTransferToVotes).to.deep.eq([defaultGroupDeposit]);
      });
    });
  });

  describe("#getExpectedAndRealCeloForGroup()", () => {
    describe("When strategy is disallowed", () => {
      const withdrawals = [50, 50];
      const depositedValue = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        await manager.allowStrategy(groupAddresses[2]);
        await manager.changeStrategy(groupAddresses[2]);
        await manager.deposit({ value: depositedValue });
        await account.setCeloForGroup(groupAddresses[2], depositedValue);
        await manager.disallowStrategy(groupAddresses[2]);
      });

      it("should return correct amount for real and expected", async () => {
        const [expected, real] = await manager.getExpectedAndRealCeloForGroup(groupAddresses[2]);
        expect(expected).to.eq(0);
        expect(real).to.eq(depositedValue);
      });
    });

    describe("When group is deprecated", () => {
      const withdrawals = [50, 50];
      const depositedValue = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        await manager.deposit({ value: depositedValue });
        await manager.deprecateGroup(groupAddresses[0]);
      });

      it("should return correct amount for real and expected", async () => {
        const [expected, real] = await manager.getExpectedAndRealCeloForGroup(groupAddresses[0]);
        expect(expected).to.eq(0);
        expect(real).to.eq(depositedValue / 2);
      });
    });

    describe("When group is only in allowed", () => {
      const depositedValue = 100;
      beforeEach(async () => {
        await manager.allowStrategy(groupAddresses[0]);
        await manager.changeStrategy(groupAddresses[0]);
        await manager.deposit({ value: depositedValue });
      });

      it("should return same amount for real and expected", async () => {
        await account.setCeloForGroup(groupAddresses[0], depositedValue);

        const [expected, real] = await manager.getExpectedAndRealCeloForGroup(groupAddresses[0]);
        expect(expected).to.eq(real);
      });

      it("should return different amount for real and expected", async () => {
        const celoForGroup = 50;
        await account.setCeloForGroup(groupAddresses[0], celoForGroup);

        const [expected, real] = await manager.getExpectedAndRealCeloForGroup(groupAddresses[0]);
        expect(expected).to.eq(depositedValue);
        expect(real).to.eq(celoForGroup);
      });
    });

    describe("When there are active groups", () => {
      const withdrawals = [50, 50];

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await manager.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
      });

      describe("When group is only in active", () => {
        const depositedValue = 100;
        beforeEach(async () => {
          await manager.deposit({ value: depositedValue });
        });

        it("should return same amount for real and expected", async () => {
          const [expected, real] = await manager.getExpectedAndRealCeloForGroup(groupAddresses[0]);
          expect(expected).to.eq(real);
        });

        it("should return different amount for real and expected", async () => {
          const celoForGroup = 60;
          await account.setCeloForGroup(groupAddresses[0], celoForGroup);

          const [expected, real] = await manager.getExpectedAndRealCeloForGroup(groupAddresses[0]);
          expect(expected).to.eq(depositedValue / 2);
          expect(real).to.eq(celoForGroup);
        });
      });

      describe("When group is in both active and allowed", () => {
        const defaultDepositedValue = 100;
        const specificDepositedValue = 100;

        beforeEach(async () => {
          await manager.allowStrategy(groupAddresses[0]);
          await manager.connect(depositor).deposit({ value: defaultDepositedValue });
          await manager.connect(depositor2).changeStrategy(groupAddresses[0]);
          await manager.connect(depositor2).deposit({ value: specificDepositedValue });
        });

        it("should return same amount for real and expected", async () => {
          await account.setCeloForGroup(
            groupAddresses[0],
            defaultDepositedValue / 2 + specificDepositedValue
          );
          const [expected, real] = await manager.getExpectedAndRealCeloForGroup(groupAddresses[0]);
          expect(expected).to.eq(real);
        });

        it("should return different amount for real and expected", async () => {
          const celoForGroup = 60;
          await account.setCeloForGroup(groupAddresses[0], celoForGroup);

          const [expected, real] = await manager.getExpectedAndRealCeloForGroup(groupAddresses[0]);
          expect(expected).to.eq(defaultDepositedValue / 2 + specificDepositedValue);
          expect(real).to.eq(celoForGroup);
        });
      });
    });
  });

  describe("#rebalance()", () => {
    const fromGroupDepositedValue = 100;
    const toGroupDepositedValue = 77;

    it("should revert when trying to balance 0x0 and some group", async () => {
      await manager.allowStrategy(groupAddresses[0]);
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });
      await expect(manager.rebalance(ADDRESS_ZERO, groupAddresses[0])).revertedWith(
        `InvalidFromGroup("${ADDRESS_ZERO}")`
      );
    });

    it("should revert when trying to balance some and 0x0 group", async () => {
      await manager.allowStrategy(groupAddresses[0]);
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });

      await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue + 1);

      await expect(manager.rebalance(groupAddresses[0], ADDRESS_ZERO)).revertedWith(
        `InvalidToGroup("${ADDRESS_ZERO}")`
      );
    });

    it("should revert when trying to balance 0x0 and 0x0 group", async () => {
      await expect(manager.rebalance(ADDRESS_ZERO, ADDRESS_ZERO)).revertedWith(
        `InvalidToGroup("${ADDRESS_ZERO}")`
      );
    });

    it("should revert when fromGroup has less Celo than it should", async () => {
      await manager.allowStrategy(groupAddresses[0]);
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });

      await manager.allowStrategy(groupAddresses[1]);
      await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
      await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });

      await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue - 1);
      await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
        `RebalanceNoExtraCelo("${groupAddresses[0]}")`
      );
    });

    it("should revert when fromGroup has same Celo as it should", async () => {
      await manager.allowStrategy(groupAddresses[0]);
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });

      await manager.allowStrategy(groupAddresses[1]);
      await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
      await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });

      await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue);
      await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
        `RebalanceNoExtraCelo("${groupAddresses[0]}")`
      );
    });

    describe("When fromGroup has valid properties", () => {
      const toGroupDepositedValue = 77;

      beforeEach(async () => {
        await manager.allowStrategy(groupAddresses[0]);
        await manager.changeStrategy(groupAddresses[0]);
        await manager.deposit({ value: fromGroupDepositedValue });
        await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue + 1);
      });

      it("should revert when toGroup has more Celo than it should", async () => {
        await manager.allowStrategy(groupAddresses[1]);
        await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
        await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });
        await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue + 1);

        await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
          `RebalanceEnoughCelo("${groupAddresses[1]}")`
        );
      });

      it("should revert when toGroup has same Celo as it should", async () => {
        await manager.allowStrategy(groupAddresses[1]);
        await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
        await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });
        await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue);

        await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
          `RebalanceEnoughCelo("${groupAddresses[1]}")`
        );
      });

      describe("When toGroup has valid properties", () => {
        beforeEach(async () => {
          await manager.allowStrategy(groupAddresses[1]);
          await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
          await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });
          await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue - 1);
        });

        it("should schedule transfer", async () => {
          await manager.rebalance(groupAddresses[0], groupAddresses[1]);

          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0]]);
          expect(lastTransferFromVotes).to.deep.eq([BigNumber.from(1)]);
          expect(lastTransferToGroups).to.deep.eq([groupAddresses[1]]);
          expect(lastTransferToVotes).to.deep.eq([BigNumber.from(1)]);
        });

        describe("When having same active groups and strategies get disallowed", () => {
          beforeEach(async () => {
            for (let i = 0; i < 2; i++) {
              await manager.activateGroup(groupAddresses[i]);
            }
            await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue);

            await manager.disallowStrategy(groupAddresses[0]);
            await manager.disallowStrategy(groupAddresses[1]);
          });

          it("should schedule transfer from deprecated group", async () => {
            await manager.deprecateGroup(groupAddresses[0]);
            await manager.rebalance(groupAddresses[0], groupAddresses[1]);

            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0]]);
            expect(lastTransferFromVotes).to.deep.eq([BigNumber.from(fromGroupDepositedValue)]);
            expect(lastTransferToGroups).to.deep.eq([groupAddresses[1]]);
            expect(lastTransferToVotes).to.deep.eq([BigNumber.from(fromGroupDepositedValue)]);
          });

          it("should revert when rebalance to deprecated group", async () => {
            await manager.deprecateGroup(groupAddresses[1]);
            await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
              `InvalidToGroup("${groupAddresses[1]}")`
            );
          });
        });

        describe("When having different active groups", () => {
          beforeEach(async () => {
            for (let i = 2; i < 4; i++) {
              await manager.activateGroup(groupAddresses[i]);
            }
          });

          it("should schedule transfer from disallowed strategy", async () => {
            await manager.disallowStrategy(groupAddresses[0]);
            await manager.rebalance(groupAddresses[0], groupAddresses[1]);

            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0]]);
            expect(lastTransferFromVotes).to.deep.eq([BigNumber.from(1)]);
            expect(lastTransferToGroups).to.deep.eq([groupAddresses[1]]);
            expect(lastTransferToVotes).to.deep.eq([BigNumber.from(1)]);
          });

          it("should revert when rebalance to disallowed strategy", async () => {
            await manager.disallowStrategy(groupAddresses[1]);
            await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
              `InvalidToGroup("${groupAddresses[1]}")`
            );
          });
        });
      });
    });
  });
});
