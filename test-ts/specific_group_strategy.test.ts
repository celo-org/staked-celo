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
import { MockDefaultStrategy } from "../typechain-types/MockDefaultStrategy";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { MockLockedGold } from "../typechain-types/MockLockedGold";
import { MockRegistry } from "../typechain-types/MockRegistry";
import { MockStakedCelo } from "../typechain-types/MockStakedCelo";
import { MockValidators } from "../typechain-types/MockValidators";
import { MockVote } from "../typechain-types/MockVote";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import {
  ADDRESS_ZERO,
  deregisterValidatorGroup,
  electMockValidatorGroupsAndUpdate,
  getBlockedSpecificGroupStrategies,
  getDefaultGroupsSafe,
  getImpersonatedSigner,
  getSpecificGroupsSafe,
  mineToNextEpoch,
  prepareOverflow,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
  removeMembersFromGroup,
  resetNetwork,
  revokeElectionOnMockValidatorGroupsAndUpdate,
  updateGroupSlashingMultiplier,
} from "./utils";

after(() => {
  hre.kit.stop();
});

describe("SpecificGroupStrategy", () => {
  let account: MockAccount;
  let manager: Manager;
  let nonVote: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;
  let depositor: SignerWithAddress;
  let nonManager: SignerWithAddress;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let voter: SignerWithAddress;
  let someone: SignerWithAddress;
  let validators: ValidatorsWrapper;
  let owner: SignerWithAddress;
  let registryContract: MockRegistry;
  let lockedGoldContract: MockLockedGold;
  let validatorsContract: MockValidators;
  let lockedGold: LockedGoldWrapper;
  let mockSlasher: SignerWithAddress;
  let stakedCelo: MockStakedCelo;
  let voteContract: MockVote;
  let groupHealthContract: MockGroupHealth;
  let defaultStrategyContract: MockDefaultStrategy;
  let election: ElectionWrapper;

  let nonOwner: SignerWithAddress;

  let groupAddresses: string[];
  let groups: SignerWithAddress[];

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  before(async function () {
    try {
      this.timeout(100000);
      await resetNetwork();

      await hre.deployments.fixture("FullTestManager");
      manager = await hre.ethers.getContract("Manager");
      specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");
      groupHealthContract = await hre.ethers.getContract("MockGroupHealth");
      defaultStrategyContract = await hre.ethers.getContract("MockDefaultStrategy");
      validators = await hre.kit.contracts.getValidators();
      lockedGold = await hre.kit.contracts.getLockedGold();
      election = await hre.kit.contracts.getElection();

      [owner] = await randomSigner(parseUnits("100"));
      [nonOwner] = await randomSigner(parseUnits("100"));
      [nonVote] = await randomSigner(parseUnits("100000"));
      [nonStakedCelo] = await randomSigner(parseUnits("100"));
      [nonAccount] = await randomSigner(parseUnits("100"));
      [nonManager] = await randomSigner(parseUnits("100"));
      [voter] = await randomSigner(parseUnits("10000000000"));
      [someone] = await randomSigner(parseUnits("100"));
      [mockSlasher] = await randomSigner(parseUnits("100"));
      [depositor] = await randomSigner(parseUnits("500"));

      const registryFactory: MockRegistry__factory = (
        await hre.ethers.getContractFactory("MockRegistry")
      ).connect(owner) as MockRegistry__factory;
      registryContract = registryFactory.attach(REGISTRY_ADDRESS);

      const lockedGoldFactory: MockLockedGold__factory = (
        await hre.ethers.getContractFactory("MockLockedGold")
      ).connect(owner) as MockLockedGold__factory;
      lockedGoldContract = lockedGoldFactory.attach(lockedGold.address);

      const validatorsFactory: MockValidators__factory = (
        await hre.ethers.getContractFactory("MockValidators")
      ).connect(owner) as MockValidators__factory;
      validatorsContract = validatorsFactory.attach(validators.address);

      const stakedCeloFactory: MockStakedCelo__factory = (
        await hre.ethers.getContractFactory("MockStakedCelo")
      ).connect(owner) as MockStakedCelo__factory;
      stakedCelo = await stakedCeloFactory.deploy();

      const mockVoteFactory: MockVote__factory = (
        await hre.ethers.getContractFactory("MockVote")
      ).connect(owner) as MockVote__factory;
      voteContract = await mockVoteFactory.deploy();

      const accountFactory: MockAccount__factory = (
        await hre.ethers.getContractFactory("MockAccount")
      ).connect(owner) as MockAccount__factory;
      account = await accountFactory.deploy();

      await manager.setDependencies(
        stakedCelo.address,
        account.address,
        voteContract.address,
        groupHealthContract.address,
        specificGroupStrategyContract.address,
        defaultStrategyContract.address
      );

      await specificGroupStrategyContract.setDependencies(
        account.address,
        groupHealthContract.address,
        defaultStrategyContract.address
      );

      await defaultStrategyContract.setDependencies(
        account.address,
        groupHealthContract.address,
        specificGroupStrategyContract.address
      );

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

      await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, groupAddresses);
    } catch (error) {
      console.error(error);
    }
  });

  beforeEach(async () => {
    snapshotId = await hre.ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await hre.ethers.provider.send("evm_revert", [snapshotId]);
  });

  describe("#setDependencies()", () => {
    let ownerSigner: SignerWithAddress;

    before(async () => {
      const managerOwner = await manager.owner();
      ownerSigner = await getImpersonatedSigner(managerOwner);
    });

    it("reverts with zero account address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(ownerSigner)
          .setDependencies(ADDRESS_ZERO, nonVote.address, nonVote.address)
      ).revertedWith("Account null");
    });

    it("reverts with zero groupHealth address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, ADDRESS_ZERO, nonVote.address)
      ).revertedWith("GroupHealth null");
    });

    it("reverts with zero defaultStrategy address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, nonVote.address, ADDRESS_ZERO)
      ).revertedWith("DefaultStrategy null");
    });

    it("sets the vote contract", async () => {
      await specificGroupStrategyContract
        .connect(ownerSigner)
        .setDependencies(nonAccount.address, nonStakedCelo.address, nonOwner.address);
      const account = await specificGroupStrategyContract.account();
      expect(account).to.eq(nonAccount.address);

      const groupHealth = await specificGroupStrategyContract.groupHealth();
      expect(groupHealth).to.eq(nonStakedCelo.address);

      const defaultStrategy = await specificGroupStrategyContract.defaultStrategy();
      expect(defaultStrategy).to.eq(nonOwner.address);
    });

    it("cannot be called by a non-Owner account", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(nonOwner)
          .setDependencies(nonStakedCelo.address, nonAccount.address, nonAccount.address)
      ).revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("#calculateAndUpdateForWithdrawal", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(nonManager)
          .calculateAndUpdateForWithdrawal(nonVote.address, 10, 10)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#blockStrategy()", () => {
    it("reverts when no active groups", async () => {
      await expect(specificGroupStrategyContract.blockStrategy(groupAddresses[3])).revertedWith(
        `NoActiveGroups()`
      );
    });

    describe("When 2 active groups", () => {
      let specificGroupStrategy: SignerWithAddress;
      beforeEach(async () => {
        specificGroupStrategy = groups[2];
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groups[i].address, ADDRESS_ZERO, head);
        }
      });

      describe("when the group is allowed", () => {
        let specificGroupStrategyDeposit: BigNumber;

        beforeEach(async () => {
          specificGroupStrategyDeposit = parseUnits("1");
          await account.setCeloForGroup(
            specificGroupStrategy.address,
            specificGroupStrategyDeposit
          );
          await manager.connect(depositor).changeStrategy(specificGroupStrategy.address);
          await manager.connect(depositor).deposit({ value: specificGroupStrategyDeposit });
        });

        it("added group to allowed strategies", async () => {
          const activeGroups = await getDefaultGroupsSafe(defaultStrategyContract);
          const specificStrategies = await getSpecificGroupsSafe(specificGroupStrategyContract);
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(specificStrategies).to.deep.eq([specificGroupStrategy.address]);
        });

        it("removes the group from the groups array", async () => {
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
          const activeGroups = await getDefaultGroupsSafe(defaultStrategyContract);
          const specificStrategies = await getSpecificGroupsSafe(specificGroupStrategyContract);
          expect(activeGroups).to.have.deep.members([groupAddresses[0], groupAddresses[1]]);
          expect(specificStrategies).to.deep.eq([]);
        });

        it("emits a StrategyBlocked event", async () => {
          await expect(specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address))
            .to.emit(specificGroupStrategyContract, "StrategyBlocked")
            .withArgs(specificGroupStrategy.address);
        });

        it("should add blocked strategy to blocked strategies", async () => {
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
          const blockedStrategies = await getBlockedSpecificGroupStrategies(
            specificGroupStrategyContract
          );
          expect(blockedStrategies).to.have.deep.members([specificGroupStrategy.address]);
        });

        it("reverts when blocking already blocked strategy", async () => {
          await specificGroupStrategyContract.blockStrategy(groupAddresses[3]);
          await expect(specificGroupStrategyContract.blockStrategy(groupAddresses[3])).revertedWith(
            `StrategyAlreadyBlocked("${groupAddresses[3]}")`
          );
        });

        it("cannot be called by a non owner", async () => {
          await expect(
            specificGroupStrategyContract
              .connect(nonOwner)
              .blockStrategy(specificGroupStrategy.address)
          ).revertedWith("Ownable: caller is not the owner");
        });

        it("should schedule transfers to default strategy", async () => {
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          expect(lastTransferFromGroups).to.deep.eq([specificGroupStrategy.address]);
          expect(lastTransferFromVotes).to.deep.eq([specificGroupStrategyDeposit]);

          expect(lastTransferToGroups).to.deep.eq([tail]);
          expect(lastTransferToVotes).to.have.deep.members([specificGroupStrategyDeposit]);
        });
      });
    });
  });

  describe("#unblockStrategy", () => {
    it("should revert when unhealthy group", async () => {
      await deregisterValidatorGroup(groups[0]);
      await groupHealthContract.updateGroupHealth(groupAddresses[0]);
      await expect(specificGroupStrategyContract.unblockStrategy(groupAddresses[0])).revertedWith(
        `StrategyNotEligible("${groupAddresses[0]}")`
      );
    });

    it("should revert when not blocked strategy", async () => {
      await expect(specificGroupStrategyContract.unblockStrategy(groupAddresses[0])).revertedWith(
        `FailedToUnBlockStrategy("${groupAddresses[0]}")`
      );
    });

    describe("when the group is blocked", () => {
      let specificGroupStrategy: SignerWithAddress;
      let specificGroupStrategyDeposit: BigNumber;
      beforeEach(async () => {
        specificGroupStrategy = groups[2];
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groups[i].address, ADDRESS_ZERO, head);
        }

        specificGroupStrategyDeposit = parseUnits("1");
        await account.setCeloForGroup(specificGroupStrategy.address, specificGroupStrategyDeposit);
        await manager.connect(depositor).changeStrategy(specificGroupStrategy.address);
        await manager.connect(depositor).deposit({ value: specificGroupStrategyDeposit });
        await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
      });

      it("should have blocked strategy", async () => {
        const blockedGroups = await getBlockedSpecificGroupStrategies(
          specificGroupStrategyContract
        );
        expect(blockedGroups).to.have.deep.members([specificGroupStrategy.address]);
      });

      it("should allow to unblock strategy", async () => {
        await specificGroupStrategyContract.unblockStrategy(specificGroupStrategy.address);
        const blockedGroups = await getBlockedSpecificGroupStrategies(
          specificGroupStrategyContract
        );
        expect(blockedGroups).to.have.deep.members([]);
      });
    });
  });

  describe("#blockUnhealthyStrategy()", () => {
    let deactivatedGroup: SignerWithAddress;

    beforeEach(async () => {
      deactivatedGroup = groups[1];
      for (let i = 0; i < 3; i++) {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract.activateGroup(groups[i].address, ADDRESS_ZERO, head);
      }

      await manager.connect(depositor).changeStrategy(groupAddresses[1]);
      await manager.connect(depositor).deposit({ value: 100 });
    });

    it("should revert when group is healthy", async () => {
      await expect(
        specificGroupStrategyContract.blockUnhealthyStrategy(groupAddresses[1])
      ).revertedWith(`HealthyGroup("${groupAddresses[1]}")`);
    });

    describe("when the group is not elected", () => {
      beforeEach(async () => {
        await mineToNextEpoch(hre.web3);
        await revokeElectionOnMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          groupAddresses[1],
        ]);
      });

      it("should deactivate group", async () => {
        await expect(await specificGroupStrategyContract.blockUnhealthyStrategy(groupAddresses[1]))
          .to.emit(specificGroupStrategyContract, "StrategyBlocked")
          .withArgs(groupAddresses[1]);
      });
    });

    describe("when the group is not registered", () => {
      beforeEach(async () => {
        await deregisterValidatorGroup(deactivatedGroup);
        await mineToNextEpoch(hre.web3);
        await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          deactivatedGroup.address,
        ]);
      });

      it("should deactivate group", async () => {
        await expect(
          await specificGroupStrategyContract.blockUnhealthyStrategy(deactivatedGroup.address)
        )
          .to.emit(specificGroupStrategyContract, "StrategyBlocked")
          .withArgs(deactivatedGroup.address);
      });
    });

    describe("when the group has no members", () => {
      // if voting for a group that has no members, I get no rewards.
      beforeEach(async () => {
        await removeMembersFromGroup(deactivatedGroup);
        await mineToNextEpoch(hre.web3);
        await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          deactivatedGroup.address,
        ]);
      });

      it("should deactivate group", async () => {
        await expect(
          await specificGroupStrategyContract.blockUnhealthyStrategy(deactivatedGroup.address)
        )
          .to.emit(specificGroupStrategyContract, "StrategyBlocked")
          .withArgs(deactivatedGroup.address);
      });
    });

    describe("when group has 3 validators, but only 1 is elected.", () => {
      let validatorGroupWithThreeValidators: SignerWithAddress;
      beforeEach(async () => {
        [validatorGroupWithThreeValidators] = await randomSigner(parseUnits("40000"));
        const memberCount = 3;
        await registerValidatorGroup(validatorGroupWithThreeValidators, memberCount);

        const electedValidatorIndex = 0;

        for (let i = 0; i < memberCount; i++) {
          const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
          await registerValidatorAndAddToGroupMembers(
            validatorGroupWithThreeValidators,
            validator,
            validatorWallet
          );

          if (i === memberCount - 1) {
            await groupHealthContract.setElectedValidator(electedValidatorIndex, validator.address);
          }
        }
        await groupHealthContract.updateGroupHealth(validatorGroupWithThreeValidators.address);
        const [head] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract.activateGroup(
          validatorGroupWithThreeValidators.address,
          ADDRESS_ZERO,
          head
        );
      });

      it("should revert with Healthy group message", async () => {
        await expect(
          specificGroupStrategyContract.blockUnhealthyStrategy(
            validatorGroupWithThreeValidators.address
          )
        ).revertedWith(`HealthyGroup("${validatorGroupWithThreeValidators.address}")`);
      });
    });

    describe("when the group is slashed", () => {
      beforeEach(async () => {
        await updateGroupSlashingMultiplier(
          registryContract,
          lockedGoldContract,
          validatorsContract,
          deactivatedGroup,
          mockSlasher
        );
        await mineToNextEpoch(hre.web3);
        await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          deactivatedGroup.address,
        ]);
      });

      it("should deactivate group", async () => {
        await expect(
          await specificGroupStrategyContract.blockUnhealthyStrategy(deactivatedGroup.address)
        )
          .to.emit(specificGroupStrategyContract, "StrategyBlocked")
          .withArgs(groupAddresses[1]);
      });
    });
  });

  describe("#rebalanceOverflownGroup()", () => {
    const thirdGroupCapacity = parseUnits("200.166666666666666666");

    beforeEach(async () => {
      await prepareOverflow(defaultStrategyContract, election, lockedGold, voter, groupAddresses);
    });

    it("should revert when from group is not overflowing", async () => {
      await expect(
        specificGroupStrategyContract.rebalanceOverflownGroup(groupAddresses[0])
      ).revertedWith(`GroupNotOverflowing("${groupAddresses[0]}")`);
    });

    describe("When third group overflowing", () => {
      const deposit = parseUnits("250");
      beforeEach(async () => {
        await manager.connect(depositor).changeStrategy(groupAddresses[2]);
        await manager.connect(depositor).deposit({ value: deposit });
        const [scheduledGroups, scheduledVotes] = await account.getLastScheduledVotes();
        for (let i = 0; i < scheduledGroups.length; i++) {
          await account.setCeloForGroup(scheduledGroups[i], scheduledVotes[i]);
        }
      });

      it("should revert when group is overflowing and no capacity was freed", async () => {
        await expect(
          specificGroupStrategyContract.rebalanceOverflownGroup(groupAddresses[2])
        ).revertedWith(`GroupStillOverflowing("${groupAddresses[2]}")`);
      });

      describe("When some capacity was freed and rebalanced", () => {
        let originalOverflow: BigNumber;
        beforeEach(async () => {
          const revokeTx = await election.revokePending(
            voter.address,
            groupAddresses[2],
            new BigNumberJs(thirdGroupCapacity.toString())
          );
          await revokeTx.sendAndWaitForReceipt({ from: voter.address });
          [, originalOverflow] = await specificGroupStrategyContract.getStCeloInStrategy(
            groupAddresses[2]
          );
          await specificGroupStrategyContract.rebalanceOverflownGroup(groupAddresses[2]);
        });

        it("should return 0 overflow", async () => {
          const [total, overflow] = await specificGroupStrategyContract.getStCeloInStrategy(
            groupAddresses[2]
          );
          expect(overflow).to.deep.eq(BigNumber.from("0"));
          expect(total).to.deep.eq(deposit);
        });

        it("should remove stCelo from default strategy", async () => {
          const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
          expect(stCeloInDefault).to.deep.eq(BigNumber.from(0));
        });

        it("should schedule transfers from active groups", async () => {
          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          expect(lastTransferFromGroups).to.have.deep.members([
            groupAddresses[0],
            groupAddresses[1],
          ]);
          expect(lastTransferFromVotes[0].add(lastTransferFromVotes[1])).to.deep.eq(
            originalOverflow
          );

          expect(lastTransferToGroups).to.have.deep.members([groupAddresses[2]]);
          expect(lastTransferToVotes).to.have.deep.members([originalOverflow]);
        });
      });
    });
  });
});
