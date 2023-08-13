import { AccountsWrapper } from "@celo/contractkit/lib/wrappers/Accounts";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
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
  electGroup,
  electMockValidatorGroupsAndUpdate,
  getDefaultGroups,
  getImpersonatedSigner,
  getOrderedActiveGroups,
  getUnsortedGroups,
  mineToNextEpoch,
  prepareOverflow,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorAndOnlyAffiliateToGroup,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
  removeMembersFromGroup,
  resetNetwork,
  revokeElectionOnMockValidatorGroupsAndUpdate,
  updateGroupCeloBasedOnProtocolStCelo,
  updateGroupSlashingMultiplier,
  updateMaxNumberOfGroups,
} from "./utils";
import { OrderedGroup } from "./utils-interfaces";

after(() => {
  hre.kit.stop();
});

describe("DefaultStrategy", () => {
  let account: MockAccount;

  let manager: Manager;
  let groupHealthContract: MockGroupHealth;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategyContract: MockDefaultStrategy;
  let nonVote: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;
  let nonManager: SignerWithAddress;
  let voter: SignerWithAddress;
  let someone: SignerWithAddress;
  let validators: ValidatorsWrapper;
  let accountsWrapper: AccountsWrapper;
  let election: ElectionWrapper;
  let registryContract: MockRegistry;
  let lockedGoldContract: MockLockedGold;
  let validatorsContract: MockValidators;
  let lockedGold: LockedGoldWrapper;
  let mockSlasher: SignerWithAddress;
  let stakedCelo: MockStakedCelo;
  let voteContract: MockVote;

  let owner: SignerWithAddress;
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
      groupHealthContract = await hre.ethers.getContract("MockGroupHealth");
      specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");
      defaultStrategyContract = await hre.ethers.getContract("MockDefaultStrategy");
      validators = await hre.kit.contracts.getValidators();
      accountsWrapper = await hre.kit.contracts.getAccounts();
      election = await hre.kit.contracts.getElection();
      lockedGold = await hre.kit.contracts.getLockedGold();

      [owner] = await randomSigner(parseUnits("100"));
      [nonOwner] = await randomSigner(parseUnits("100"));
      [nonVote] = await randomSigner(parseUnits("100000"));
      [nonStakedCelo] = await randomSigner(parseUnits("100"));
      [nonAccount] = await randomSigner(parseUnits("100"));
      [nonManager] = await randomSigner(parseUnits("100"));
      [voter] = await randomSigner(parseUnits("10000000000"));
      [someone] = await randomSigner(parseUnits("100"));
      [mockSlasher] = await randomSigner(parseUnits("100"));

      const accountFactory: MockAccount__factory = (
        await hre.ethers.getContractFactory("MockAccount")
      ).connect(owner) as MockAccount__factory;
      account = await accountFactory.deploy();

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

      await manager.setDependencies(
        stakedCelo.address,
        account.address,
        voteContract.address,
        groupHealthContract.address,
        specificGroupStrategyContract.address,
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
        defaultStrategyContract
          .connect(ownerSigner)
          .setDependencies(ADDRESS_ZERO, nonVote.address, nonVote.address)
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero groupHealth address", async () => {
      await expect(
        defaultStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, ADDRESS_ZERO, nonVote.address)
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero specific group strategy address", async () => {
      await expect(
        defaultStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, nonVote.address, ADDRESS_ZERO)
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("sets the vote contract", async () => {
      await defaultStrategyContract
        .connect(ownerSigner)
        .setDependencies(nonAccount.address, nonStakedCelo.address, nonVote.address);
      const account = await defaultStrategyContract.account();
      expect(account).to.eq(nonAccount.address);

      const groupHealth = await defaultStrategyContract.groupHealth();
      expect(groupHealth).to.eq(nonStakedCelo.address);

      const specificGroupStrategy = await defaultStrategyContract.specificGroupStrategy();
      expect(specificGroupStrategy).to.eq(nonVote.address);
    });

    it("cannot be called by a non-Owner account", async () => {
      await expect(
        defaultStrategyContract
          .connect(nonOwner)
          .setDependencies(nonStakedCelo.address, nonAccount.address, nonVote.address)
      ).revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("#activateGroup()", () => {
    it("adds a group", async () => {
      await defaultStrategyContract.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);
      const activeGroups = await getDefaultGroups(defaultStrategyContract);
      const activeGroupsLength = await defaultStrategyContract.getNumberOfGroups();
      const [firstActiveGroup] = await defaultStrategyContract.getGroupsHead();
      expect(activeGroups).to.deep.eq([groupAddresses[0]]);
      expect(activeGroupsLength).to.eq(1);
      expect(firstActiveGroup).to.eq(groupAddresses[0]);
    });

    it("emits a GroupActivated event", async () => {
      await expect(
        defaultStrategyContract.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO)
      )
        .to.emit(defaultStrategyContract, "GroupActivated")
        .withArgs(groupAddresses[0]);
    });

    it("cannot be called by a non owner", async () => {
      await expect(
        defaultStrategyContract
          .connect(nonOwner)
          .activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO)
      ).revertedWith("Ownable: caller is not the owner");
    });

    describe("when group is not registered", () => {
      it("reverts when trying to add an unregistered group", async () => {
        const [unregisteredGroup] = await randomSigner(parseUnits("100"));
        await expect(
          defaultStrategyContract.activateGroup(
            unregisteredGroup.address,
            ADDRESS_ZERO,
            ADDRESS_ZERO
          )
        ).revertedWith(`GroupNotEligible("${unregisteredGroup.address}")`);
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
        await expect(
          defaultStrategyContract.activateGroup(noMemberedGroup.address, ADDRESS_ZERO, ADDRESS_ZERO)
        ).revertedWith(`GroupNotEligible("${noMemberedGroup.address}")`);
      });
    });

    describe("when group is not elected", () => {
      it("reverts when trying to add non elected group", async () => {
        const nonElectedGroup = groups[10];
        await mineToNextEpoch(hre.web3);
        await revokeElectionOnMockValidatorGroupsAndUpdate(
          validators,
          accountsWrapper,
          groupHealthContract,
          [nonElectedGroup.address]
        );
        await expect(
          defaultStrategyContract.activateGroup(nonElectedGroup.address, ADDRESS_ZERO, ADDRESS_ZERO)
        ).revertedWith(`GroupNotEligible("${nonElectedGroup.address}")`);
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
      });

      it("emits a GroupActivated event", async () => {
        await expect(
          defaultStrategyContract.activateGroup(
            validatorGroupWithThreeValidators.address,
            ADDRESS_ZERO,
            ADDRESS_ZERO
          )
        )
          .to.emit(defaultStrategyContract, "GroupActivated")
          .withArgs(validatorGroupWithThreeValidators.address);
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
        await expect(
          defaultStrategyContract.activateGroup(slashedGroup.address, ADDRESS_ZERO, ADDRESS_ZERO)
        ).revertedWith(`GroupNotEligible("${slashedGroup.address}")`);
      });
    });

    describe("when some groups are already added", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
      });

      it("adds another group", async () => {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract.activateGroup(groupAddresses[3], ADDRESS_ZERO, head);
        const activeGroups = await getDefaultGroups(defaultStrategyContract);
        expect(activeGroups).to.deep.eq(groupAddresses.slice(0, 4));
      });

      it("emits a GroupActivated event", async () => {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await expect(defaultStrategyContract.activateGroup(groupAddresses[3], ADDRESS_ZERO, head))
          .to.emit(defaultStrategyContract, "GroupActivated")
          .withArgs(groupAddresses[3]);
      });

      it("reverts when trying to add an existing group", async () => {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await expect(
          defaultStrategyContract.activateGroup(groupAddresses[1], ADDRESS_ZERO, head)
        ).revertedWith(`GroupAlreadyAdded("${groupAddresses[1]}")`);
      });
    });

    describe("When activating groups with preexisting celo in protocol", () => {
      beforeEach(async () => {
        await account.setCeloForGroup(groupAddresses[0], 100);
        await defaultStrategyContract.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);
      });

      it("should revert when incorrect lesser and greater", async () => {
        await account.setCeloForGroup(groupAddresses[1], 200);
        await expect(
          defaultStrategyContract.activateGroup(groupAddresses[1], ADDRESS_ZERO, groupAddresses[0])
        ).revertedWith("get lesser and greater failure");
      });

      it("should insert with correct lesser and greater", async () => {
        await account.setCeloForGroup(groupAddresses[1], 200);
        await defaultStrategyContract.activateGroup(
          groupAddresses[1],
          groupAddresses[0],
          ADDRESS_ZERO
        );

        const stCelo = await defaultStrategyContract.stCeloInGroup(groupAddresses[1]);
        expect(stCelo).to.eq(200);
      });
    });

    describe("when maxNumGroupsVotedFor have been voted for", async () => {
      let additionalGroup: SignerWithAddress;

      beforeEach(async () => {
        additionalGroup = groups[10];
        await electGroup(additionalGroup.address, someone);

        for (let i = 0; i < 10; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
      });

      it("can add another group when enabled in Election contract", async () => {
        await updateMaxNumberOfGroups(account.address, election, nonOwner, true);

        const [head] = await defaultStrategyContract.getGroupsHead();
        await expect(
          defaultStrategyContract.activateGroup(additionalGroup.address, ADDRESS_ZERO, head)
        )
          .to.emit(defaultStrategyContract, "GroupActivated")
          .withArgs(additionalGroup.address);
      });

      describe("when some of the groups are currently deactivated", () => {
        beforeEach(async () => {
          await account.setCeloForGroup(groupAddresses[2], 100);
          for (let i = 0; i < 10; i++) {
            await manager.deposit({ value: (i + 1) * 1000 });
          }

          await account.setCeloForGroup(groupAddresses[7], 100);
        });

        it("reactivates a deactivated group", async () => {
          await defaultStrategyContract.deactivateGroup(groupAddresses[2]);
          await defaultStrategyContract.deactivateGroup(groupAddresses[7]);
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[2], ADDRESS_ZERO, head);
          const activeGroups = await getDefaultGroups(defaultStrategyContract);
          expect(activeGroups[8]).to.equal(groupAddresses[2]);
        });

        it("emits a GroupActivated event", async () => {
          await defaultStrategyContract.deactivateGroup(groupAddresses[2]);
          await defaultStrategyContract.deactivateGroup(groupAddresses[7]);
          const [head] = await defaultStrategyContract.getGroupsHead();
          await expect(defaultStrategyContract.activateGroup(groupAddresses[2], ADDRESS_ZERO, head))
            .to.emit(defaultStrategyContract, "GroupActivated")
            .withArgs(groupAddresses[2]);
        });
      });
    });
  });

  describe("#deactivateGroup()", () => {
    let deactivatedGroup: SignerWithAddress;

    describe("When 3 active groups", () => {
      beforeEach(async () => {
        deactivatedGroup = groups[1];
        for (let i = 0; i < 3; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
      });

      describe("when the group is voted for", () => {
        beforeEach(async () => {
          for (let i = 0; i < 3; i++) {
            await manager.deposit({ value: 100 });
          }
        });

        it("removes the group from the groups array", async () => {
          await defaultStrategyContract.deactivateGroup(deactivatedGroup.address);
          const activeGroups = await getDefaultGroups(defaultStrategyContract);
          expect(activeGroups).to.have.deep.members([groupAddresses[0], groupAddresses[2]]);
        });

        it("reverts when deprecating a non active group", async () => {
          await expect(defaultStrategyContract.deactivateGroup(groupAddresses[3])).revertedWith(
            `GroupNotActive("${groupAddresses[3]}")`
          );
        });

        it("cannot be called by a non owner", async () => {
          await expect(
            defaultStrategyContract.connect(nonOwner).deactivateGroup(deactivatedGroup.address)
          ).revertedWith("Ownable: caller is not the owner");
        });

        describe("When different ratios of CELO vs stCELO", () => {
          describe("when there is more CELO than stCELO in the system", () => {
            beforeEach(async () => {
              await account.setTotalCelo(600);
            });

            it("should schedule transfer to tail of default strategy", async () => {
              const [tail] = await defaultStrategyContract.getGroupsTail();
              const originalStCeloInTail = await defaultStrategyContract.stCeloInGroup(tail);
              await defaultStrategyContract.deactivateGroup(deactivatedGroup.address);

              expect(await defaultStrategyContract.stCeloInGroup(deactivatedGroup.address)).to.eq(
                0
              );
              expect(await defaultStrategyContract.stCeloInGroup(tail)).to.eq(
                originalStCeloInTail.add(100)
              );
            });
          });

          describe("when there is less CELO than stCELO in the system", () => {
            beforeEach(async () => {
              await account.setTotalCelo(150);
            });

            it("should schedule transfer to tail of default strategy", async () => {
              const [tail] = await defaultStrategyContract.getGroupsTail();
              const originalStCeloInTail = await defaultStrategyContract.stCeloInGroup(tail);
              await defaultStrategyContract.deactivateGroup(deactivatedGroup.address);

              expect(await defaultStrategyContract.stCeloInGroup(deactivatedGroup.address)).to.eq(
                0
              );
              expect(await defaultStrategyContract.stCeloInGroup(tail)).to.eq(
                originalStCeloInTail.add(100)
              );
            });
          });
        });

        it("should schedule transfer to tail of default strategy", async () => {
          const [tail] = await defaultStrategyContract.getGroupsTail();
          const originalStCeloInTail = await defaultStrategyContract.stCeloInGroup(tail);
          await defaultStrategyContract.deactivateGroup(deactivatedGroup.address);

          expect(await defaultStrategyContract.stCeloInGroup(deactivatedGroup.address)).to.eq(0);
          expect(await defaultStrategyContract.stCeloInGroup(tail)).to.eq(
            originalStCeloInTail.add(100)
          );
        });
      });

      describe("when the group is not voted for", () => {
        it("removes the group from the groups array", async () => {
          await defaultStrategyContract.deactivateGroup(deactivatedGroup.address);
          const activeGroups = await getDefaultGroups(defaultStrategyContract);
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[2]]);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(defaultStrategyContract.deactivateGroup(deactivatedGroup.address))
            .to.emit(defaultStrategyContract, "GroupRemoved")
            .withArgs(deactivatedGroup.address);
        });

        it("reverts when deprecating a non active group", async () => {
          await expect(defaultStrategyContract.deactivateGroup(groupAddresses[3])).revertedWith(
            `GroupNotActive("${groupAddresses[3]}")`
          );
        });

        it("cannot be called by a non owner", async () => {
          await expect(
            defaultStrategyContract.connect(nonOwner).deactivateGroup(deactivatedGroup.address)
          ).revertedWith("Ownable: caller is not the owner");
        });

        it("should not schedule transfer since group has no votes", async () => {
          await defaultStrategyContract.deactivateGroup(deactivatedGroup.address);

          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          expect(lastTransferFromGroups).to.have.deep.members([]);
          expect(lastTransferFromVotes).to.deep.eq([]);

          expect(lastTransferToGroups).to.have.deep.members([]);
          expect(lastTransferToVotes).to.deep.eq([]);
        });
      });
    });
  });

  describe("#getExpectedAndActualStCeloForGroup()", () => {
    beforeEach(async () => {
      let nextGroup = ADDRESS_ZERO;
      for (let i = 0; i < 3; i++) {
        await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
        nextGroup = groupAddresses[i];
      }
    });

    it("should return 0 when no deposit", async () => {
      const [expected, actual] = await defaultStrategyContract.getExpectedAndActualStCeloForGroup(
        groupAddresses[0]
      );
      expect(expected).to.deep.eq(BigNumber.from("0"));
      expect(actual).to.deep.eq(BigNumber.from("0"));
    });

    describe("When deposited", () => {
      let originalTail: string;
      beforeEach(async () => {
        [originalTail] = await defaultStrategyContract.getGroupsTail();
        await manager.deposit({ value: 100 });
      });

      it("should return more real stCelo in original tail / current head", async () => {
        const [currentHead] = await defaultStrategyContract.getGroupsHead();
        expect(currentHead).to.eq(originalTail);

        const [expected, actual] = await defaultStrategyContract.getExpectedAndActualStCeloForGroup(
          currentHead
        );
        expect(expected).to.deep.eq(BigNumber.from("34"));
        expect(actual).to.deep.eq(BigNumber.from("100"));
      });

      it("should return 0 real stCelo but correct expected for other than head", async () => {
        const [expected, actual] = await defaultStrategyContract.getExpectedAndActualStCeloForGroup(
          groupAddresses[1]
        );
        expect(groupAddresses[1]).not.eq(originalTail);
        expect(expected).to.deep.eq(BigNumber.from("33"));
        expect(actual).to.deep.eq(BigNumber.from("0"));
      });
    });
  });

  describe("#rebalance()", () => {
    beforeEach(async () => {
      let nextGroup = ADDRESS_ZERO;
      for (let i = 0; i < 3; i++) {
        await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
        nextGroup = groupAddresses[i];
      }
    });

    it("should revert when rebalancing from non active group", async () => {
      await expect(
        defaultStrategyContract.rebalance(groupAddresses[7], groupAddresses[0])
      ).revertedWith(`InvalidFromGroup("${groupAddresses[7]}")`);
    });

    it("should revert when rebalancing to non active group", async () => {
      await expect(
        defaultStrategyContract.rebalance(groupAddresses[0], groupAddresses[7])
      ).revertedWith(`InvalidToGroup("${groupAddresses[7]}")`);
    });

    it("should revert when nothing deposited", async () => {
      await expect(
        defaultStrategyContract.rebalance(groupAddresses[0], groupAddresses[1])
      ).revertedWith(`RebalanceNoExtraStCelo("${groupAddresses[0]}", 0, 0)`);
    });

    describe("When deposited", () => {
      let currentHead: string;
      beforeEach(async () => {
        await manager.deposit({ value: 49 });
        await manager.deposit({ value: 51 });
        [currentHead] = await defaultStrategyContract.getGroupsHead();
      });

      async function expectCorrectOrder() {
        const orderedActiveGroups = await getOrderedActiveGroups(defaultStrategyContract);
        let previous = BigNumber.from(0);
        for (let i = 0; i < orderedActiveGroups.length; i++) {
          expect(previous.lte(parseUnits(orderedActiveGroups[i].stCelo))).to.be.true;
          previous = parseUnits(orderedActiveGroups[i].stCelo);
        }
      }

      it("should have stCelo only in two groups", async () => {
        expect(await defaultStrategyContract.stCeloInGroup(currentHead)).to.deep.eq(
          BigNumber.from(51)
        );
        expect(await defaultStrategyContract.stCeloInGroup(groupAddresses[0])).to.deep.eq(
          BigNumber.from(0)
        );
        expect(await defaultStrategyContract.stCeloInGroup(groupAddresses[1])).to.deep.eq(
          BigNumber.from(51)
        );
        expect(await defaultStrategyContract.stCeloInGroup(groupAddresses[2])).to.deep.eq(
          BigNumber.from(49)
        );
        await expectCorrectOrder();
      });

      it("should rebalance correctly", async () => {
        await expectCorrectOrder();
        await defaultStrategyContract.rebalance(groupAddresses[1], groupAddresses[0]);
        await expectCorrectOrder();
        await defaultStrategyContract.rebalance(groupAddresses[2], groupAddresses[0]);
        await expectCorrectOrder();

        expect(await defaultStrategyContract.stCeloInGroup(currentHead)).to.deep.eq(
          BigNumber.from(34)
        );

        expect(await defaultStrategyContract.stCeloInGroup(groupAddresses[0])).to.deep.eq(
          BigNumber.from(32)
        );
        expect(await defaultStrategyContract.stCeloInGroup(groupAddresses[1])).to.deep.eq(
          BigNumber.from(34)
        );
        expect(await defaultStrategyContract.stCeloInGroup(groupAddresses[2])).to.deep.eq(
          BigNumber.from(34)
        );

        expect(await defaultStrategyContract.sorted()).to.be.true;
      });

      it("should revert when rebalancing from empty group", async () => {
        await expect(
          defaultStrategyContract.rebalance(groupAddresses[0], currentHead)
        ).revertedWith(`RebalanceNoExtraStCelo("${groupAddresses[0]}", 0, 33)`);
      });

      it("should revert when rebalancing to already rebalanced group", async () => {
        await manager.deposit({ value: 50 });
        await expect(
          defaultStrategyContract.rebalance(groupAddresses[1], groupAddresses[0])
        ).revertedWith(`RebalanceEnoughStCelo("${groupAddresses[0]}", 50, 50)`);
      });

      describe("When sorting loop limit 0 and rebalancing", () => {
        beforeEach(async () => {
          await defaultStrategyContract.setSortingParams(10, 10, 0);
          await defaultStrategyContract.rebalance(currentHead, groupAddresses[0]);
          expect(currentHead).not.eq(groupAddresses[0]);
        });

        it("should set sorted to false", async () => {
          expect(await defaultStrategyContract.sorted()).to.be.false;
        });

        it("should add rebalanced group to unsorted groups", async () => {
          const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
          expect(unsortedGroups).contain(currentHead);
          expect(unsortedGroups).contain(groupAddresses[0]);
        });
      });
    });
  });

  describe("#updateActiveGroupOrder()", () => {
    beforeEach(async () => {
      let nextGroup = ADDRESS_ZERO;
      for (let i = 0; i < 3; i++) {
        await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
        nextGroup = groupAddresses[i];
      }
    });

    it("should have sorted flag set to true", async () => {
      expect(await defaultStrategyContract.sorted()).to.be.true;
    });

    describe("when deposited with big enough sorting limit", () => {
      beforeEach(async () => {
        await defaultStrategyContract.setSortingParams(3, 3, 3);
        for (let i = 0; i < 3; i++) {
          await manager.deposit({ value: (i + 1) * 100 });
        }
      });

      it("should have sorted flag set to true", async () => {
        expect(await defaultStrategyContract.sorted()).to.be.true;
      });

      it("should have correctly ordered active groups", async () => {
        const orderedActiveGroups = await getOrderedActiveGroups(defaultStrategyContract);
        let previous = BigNumber.from(0);
        for (let i = 0; i < orderedActiveGroups.length; i++) {
          expect(previous.lte(parseUnits(orderedActiveGroups[i].stCelo))).to.be.true;
          previous = parseUnits(orderedActiveGroups[i].stCelo);
        }
      });
    });

    describe("when deposited with 0 sorting loop limit to TAIL only", () => {
      let originalTail: string;
      beforeEach(async () => {
        await defaultStrategyContract.setSortingParams(3, 3, 0);
        [originalTail] = await defaultStrategyContract.getGroupsTail();
        for (let i = 0; i < 3; i++) {
          await manager.deposit({ value: (i + 1) * 100 });
        }
      });

      it("should have sorted flag set to false", async () => {
        expect(await defaultStrategyContract.sorted()).to.be.false;
      });

      it("should have tail in unsorted groups", async () => {
        const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
        expect(unsortedGroups).to.have.deep.members([originalTail]);
      });

      describe("When updateActiveGroupOrder called", () => {
        beforeEach(async () => {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.updateActiveGroupOrder(originalTail, head, ADDRESS_ZERO);
        });

        it("should change the head", async () => {
          const [currentHead] = await defaultStrategyContract.getGroupsHead();
          expect(currentHead).to.eq(originalTail);
        });

        it("should change the tail", async () => {
          const [currentTail] = await defaultStrategyContract.getGroupsTail();
          expect(currentTail).to.not.eq(originalTail);
        });

        it("should empty unsorted groups", async () => {
          const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
          expect(unsortedGroups).to.have.deep.members([]);
        });

        it("should have sorted flag set to true", async () => {
          expect(await defaultStrategyContract.sorted()).to.be.true;
        });
      });
    });

    describe("when deposited with 1 sorting loop limit to TAIL only", () => {
      let originalTail: string;
      beforeEach(async () => {
        await defaultStrategyContract.setSortingParams(3, 3, 1);
        [originalTail] = await defaultStrategyContract.getGroupsTail();
        for (let i = 0; i < 3; i++) {
          await manager.deposit({ value: (i + 1) * 100 });
        }
      });

      it("should have sorted flag set to false", async () => {
        expect(await defaultStrategyContract.sorted()).to.be.false;
      });

      it("should have tail in unsorted groups", async () => {
        const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
        expect(unsortedGroups).to.have.deep.members([originalTail]);
      });

      describe("When updateActiveGroupOrder called", () => {
        beforeEach(async () => {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.updateActiveGroupOrder(originalTail, head, ADDRESS_ZERO);
        });

        it("should change the head", async () => {
          const [currentHead] = await defaultStrategyContract.getGroupsHead();
          expect(currentHead).to.eq(originalTail);
        });

        it("should change the tail", async () => {
          const [currentTail] = await defaultStrategyContract.getGroupsTail();
          expect(currentTail).to.not.eq(originalTail);
        });

        it("should empty unsorted groups", async () => {
          const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
          expect(unsortedGroups).to.have.deep.members([]);
        });

        it("should have sorted flag set to true", async () => {
          expect(await defaultStrategyContract.sorted()).to.be.true;
        });
      });
    });

    describe("when deposited with 0 sorting loop limit to more groups", () => {
      let originalTail: string;
      let originalOrderedGroups: OrderedGroup[];

      beforeEach(async () => {
        await defaultStrategyContract.setSortingParams(3, 3, 0);
        [originalTail] = await defaultStrategyContract.getGroupsTail();

        await prepareOverflow(
          defaultStrategyContract,
          election,
          lockedGold,
          voter,
          groupAddresses,
          false
        );
        originalOrderedGroups = await getOrderedActiveGroups(defaultStrategyContract);
        await manager.deposit({ value: parseUnits("250") });
      });

      it("should have sorted flag set to false", async () => {
        expect(await defaultStrategyContract.sorted()).to.be.false;
      });

      it("should have tail groups in unsorted groups", async () => {
        const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
        expect(unsortedGroups).to.have.deep.members(
          originalOrderedGroups.slice(0, 2).map((g) => g.group)
        );
      });

      describe("When updateActiveGroupOrder called", () => {
        beforeEach(async () => {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.updateActiveGroupOrder(originalTail, head, ADDRESS_ZERO);
          await defaultStrategyContract.updateActiveGroupOrder(
            originalOrderedGroups[1].group,
            head,
            ADDRESS_ZERO
          );
        });

        it("should change the head", async () => {
          const [currentHead] = await defaultStrategyContract.getGroupsHead();
          expect(currentHead).to.eq(originalTail);
        });

        it("should change the tail", async () => {
          const [currentTail] = await defaultStrategyContract.getGroupsTail();
          expect(currentTail).to.not.eq(originalTail);
        });

        it("should empty unsorted groups", async () => {
          const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
          expect(unsortedGroups).to.have.deep.members([]);
        });

        it("should have sorted flag set to true", async () => {
          expect(await defaultStrategyContract.sorted()).to.be.true;
        });
      });
    });

    describe("when withdrawn with big enough sorting limit", () => {
      let totalDeposited = 0;
      const withdrawn = 250;
      beforeEach(async () => {
        totalDeposited = 0;
        await defaultStrategyContract.setSortingParams(3, 3, 3);
        for (let i = 0; i < 3; i++) {
          const toDeposit = (i + 1) * 100;
          await manager.deposit({ value: toDeposit });
          totalDeposited += toDeposit;
        }
        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
        await manager.withdraw(withdrawn);
      });

      it("should have sorted flag set to true", async () => {
        expect(await defaultStrategyContract.sorted()).to.be.true;
      });

      it("should have correctly ordered active groups", async () => {
        const orderedActiveGroups = await getOrderedActiveGroups(defaultStrategyContract);
        let previous = BigNumber.from(0);
        let totalAmountInProtocol = 0;
        for (let i = 0; i < orderedActiveGroups.length; i++) {
          expect(previous.lte(parseUnits(orderedActiveGroups[i].stCelo))).to.be.true;
          previous = parseUnits(orderedActiveGroups[i].stCelo);
          totalAmountInProtocol += previous.toNumber();
        }
        expect(totalAmountInProtocol).to.eq(totalDeposited - withdrawn);
      });
    });

    describe("when withdrawing with 0 sorting loop limit", () => {
      let originalHead: string;
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.deposit({ value: (i + 1) * 100 });
        }
        [originalHead] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract.setSortingParams(3, 3, 0);
        expect(await defaultStrategyContract.sorted()).to.be.true;
      });

      describe("when withdrawing from 1 group", () => {
        beforeEach(async () => {
          await updateGroupCeloBasedOnProtocolStCelo(
            defaultStrategyContract,
            specificGroupStrategyContract,
            account,
            manager
          );
          await manager.withdraw(250);
        });

        it("should have sorted flag set to false", async () => {
          expect(await defaultStrategyContract.sorted()).to.be.false;
        });

        it("should have head in unsorted groups", async () => {
          const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
          expect(unsortedGroups).to.have.deep.members([originalHead]);
        });

        describe("When updateActiveGroupOrder called", () => {
          beforeEach(async () => {
            const [tail] = await defaultStrategyContract.getGroupsTail();
            await defaultStrategyContract.updateActiveGroupOrder(originalHead, ADDRESS_ZERO, tail);
          });

          it("should change the tail", async () => {
            const [currentTail] = await defaultStrategyContract.getGroupsTail();
            expect(currentTail).to.eq(originalHead);
          });

          it("should change the head", async () => {
            const [currentHead] = await defaultStrategyContract.getGroupsHead();
            expect(currentHead).to.not.eq(originalHead);
          });

          it("should empty unsorted groups", async () => {
            const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
            expect(unsortedGroups).to.have.deep.members([]);
          });

          it("should have sorted flag set to true", async () => {
            expect(await defaultStrategyContract.sorted()).to.be.true;
          });
        });
      });

      describe("when withdrawing from more groups", () => {
        let originalOrderedGroups: OrderedGroup[];

        beforeEach(async () => {
          originalOrderedGroups = await getOrderedActiveGroups(defaultStrategyContract);
          await updateGroupCeloBasedOnProtocolStCelo(
            defaultStrategyContract,
            specificGroupStrategyContract,
            account,
            manager
          );
          await manager.withdraw(450);
        });

        it("should have sorted flag set to false", async () => {
          expect(await defaultStrategyContract.sorted()).to.be.false;
        });

        it("should have head groups in unsorted groups", async () => {
          const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
          expect(unsortedGroups).to.have.deep.members(
            originalOrderedGroups.slice(originalOrderedGroups.length - 2).map((k) => k.group)
          );
        });

        describe("When updateActiveGroupOrder called", () => {
          beforeEach(async () => {
            const [tail] = await defaultStrategyContract.getGroupsTail();
            await defaultStrategyContract.updateActiveGroupOrder(
              originalOrderedGroups[originalOrderedGroups.length - 2].group,
              ADDRESS_ZERO,
              tail
            );
            await defaultStrategyContract.updateActiveGroupOrder(
              originalOrderedGroups[originalOrderedGroups.length - 1].group,
              ADDRESS_ZERO,
              tail
            );
          });

          it("should change the tail", async () => {
            const [currentTail] = await defaultStrategyContract.getGroupsTail();
            expect(currentTail).to.eq(originalHead);
          });

          it("should change the head", async () => {
            const [currentHead] = await defaultStrategyContract.getGroupsHead();
            expect(currentHead).to.not.eq(originalHead);
          });

          it("should empty unsorted groups", async () => {
            const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
            expect(unsortedGroups).to.have.deep.members([]);
          });

          it("should have sorted flag set to true", async () => {
            expect(await defaultStrategyContract.sorted()).to.be.true;
          });
        });
      });
    });

    describe("when withdrawing with 1 sorting loop limit", () => {
      let originalHead: string;
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await manager.deposit({ value: (i + 1) * 100 });
        }
        [originalHead] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract.setSortingParams(3, 3, 1);
        expect(await defaultStrategyContract.sorted()).to.be.true;
      });

      describe("when withdrawing from 1 group", () => {
        beforeEach(async () => {
          await updateGroupCeloBasedOnProtocolStCelo(
            defaultStrategyContract,
            specificGroupStrategyContract,
            account,
            manager
          );
          await manager.withdraw(250);
        });

        it("should have sorted flag set to false", async () => {
          expect(await defaultStrategyContract.sorted()).to.be.false;
        });

        it("should have head in unsorted groups", async () => {
          const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
          expect(unsortedGroups).to.have.deep.members([originalHead]);
        });

        describe("When updateActiveGroupOrder called", () => {
          beforeEach(async () => {
            const [tail] = await defaultStrategyContract.getGroupsTail();
            await defaultStrategyContract.updateActiveGroupOrder(originalHead, ADDRESS_ZERO, tail);
          });

          it("should change the tail", async () => {
            const [currentTail] = await defaultStrategyContract.getGroupsTail();
            expect(currentTail).to.eq(originalHead);
          });

          it("should change the head", async () => {
            const [currentHead] = await defaultStrategyContract.getGroupsHead();
            expect(currentHead).to.not.eq(originalHead);
          });

          it("should empty unsorted groups", async () => {
            const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
            expect(unsortedGroups).to.have.deep.members([]);
          });

          it("should have sorted flag set to true", async () => {
            expect(await defaultStrategyContract.sorted()).to.be.true;
          });
        });
      });

      describe("when withdrawing from more groups", () => {
        let originalOrderedGroups: OrderedGroup[];

        beforeEach(async () => {
          originalOrderedGroups = await getOrderedActiveGroups(defaultStrategyContract);
          await updateGroupCeloBasedOnProtocolStCelo(
            defaultStrategyContract,
            specificGroupStrategyContract,
            account,
            manager
          );
          await manager.withdraw(450);
        });

        it("should have sorted flag set to false", async () => {
          expect(await defaultStrategyContract.sorted()).to.be.false;
        });

        it("should have head groups in unsorted groups", async () => {
          const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
          expect(unsortedGroups).to.have.deep.members(
            originalOrderedGroups.slice(originalOrderedGroups.length - 2).map((k) => k.group)
          );
        });

        describe("When updateActiveGroupOrder called", () => {
          beforeEach(async () => {
            const [tail] = await defaultStrategyContract.getGroupsTail();
            await defaultStrategyContract.updateActiveGroupOrder(
              originalOrderedGroups[originalOrderedGroups.length - 2].group,
              ADDRESS_ZERO,
              tail
            );
            await defaultStrategyContract.updateActiveGroupOrder(
              originalOrderedGroups[originalOrderedGroups.length - 1].group,
              ADDRESS_ZERO,
              tail
            );
          });

          it("should change the tail", async () => {
            const [currentTail] = await defaultStrategyContract.getGroupsTail();
            expect(currentTail).to.eq(originalHead);
          });

          it("should change the head", async () => {
            const [currentHead] = await defaultStrategyContract.getGroupsHead();
            expect(currentHead).to.not.eq(originalHead);
          });

          it("should empty unsorted groups", async () => {
            const unsortedGroups = await getUnsortedGroups(defaultStrategyContract);
            expect(unsortedGroups).to.have.deep.members([]);
          });

          it("should have sorted flag set to true", async () => {
            expect(await defaultStrategyContract.sorted()).to.be.true;
          });
        });
      });
    });
  });

  describe("#generateDepositVoteDistribution", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        defaultStrategyContract
          .connect(nonManager)
          .generateDepositVoteDistribution(10, ADDRESS_ZERO)
      ).revertedWith(`CallerNotManagerNorStrategy("${nonManager.address}")`);
    });
  });

  describe("#generateWithdrawalVoteDistribution", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        defaultStrategyContract.connect(nonManager).generateWithdrawalVoteDistribution(10)
      ).revertedWith(`CallerNotManagerNorStrategy("${nonManager.address}")`);
    });
  });

  describe("#activateGroup", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        defaultStrategyContract
          .connect(nonManager)
          .activateGroup(nonVote.address, ADDRESS_ZERO, ADDRESS_ZERO)
      ).revertedWith(`Ownable: caller is not the owner`);
    });
  });

  describe("#getGroupsHead()", () => {
    it("returns empty when no active groups", async () => {
      const [head, previous] = await defaultStrategyContract.getGroupsHead();
      expect(head).to.eq(ADDRESS_ZERO);
      expect(previous).to.eq(ADDRESS_ZERO);
    });

    describe("When active groups", () => {
      beforeEach(async () => {
        let nextGroup = ADDRESS_ZERO;
        for (let i = 0; i < 3; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
          nextGroup = groupAddresses[i];
        }

        await manager.deposit({ value: 100 });
        await manager.deposit({ value: 50 });
      });

      it("should return head correctly", async () => {
        const allGroups = await getOrderedActiveGroups(defaultStrategyContract);
        const [head, previous] = await defaultStrategyContract.getGroupsHead();
        const sortedGroups = allGroups.sort((a, b) =>
          parseUnits(a.stCelo).lt(parseUnits(b.stCelo)) ? -1 : 1
        );
        expect(sortedGroups[sortedGroups.length - 1].group).to.eq(head);
        expect(sortedGroups[sortedGroups.length - 2].group).to.eq(previous);
      });
    });
  });

  describe("#getGroupsTail()", () => {
    it("returns empty when no active groups", async () => {
      const [tail, next] = await defaultStrategyContract.getGroupsTail();
      expect(tail).to.eq(ADDRESS_ZERO);
      expect(next).to.eq(ADDRESS_ZERO);
    });

    describe("When active groups", () => {
      beforeEach(async () => {
        let nextGroup = ADDRESS_ZERO;
        for (let i = 0; i < 3; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
          nextGroup = groupAddresses[i];
        }

        await manager.deposit({ value: 100 });
        await manager.deposit({ value: 50 });
      });

      it("should return tail correctly", async () => {
        const allGroups = await getOrderedActiveGroups(defaultStrategyContract);
        const [tail, next] = await defaultStrategyContract.getGroupsTail();
        const sortedGroups = allGroups.sort((a, b) =>
          parseUnits(a.stCelo).lt(parseUnits(b.stCelo)) ? -1 : 1
        );
        expect(sortedGroups[0].group).to.eq(tail);
        expect(sortedGroups[1].group).to.eq(next);
      });
    });
  });

  describe("#deactivateUnhealthyGroup()", () => {
    let deactivatedGroup: SignerWithAddress;

    beforeEach(async () => {
      deactivatedGroup = groups[1];
      for (let i = 0; i < 3; i++) {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract.activateGroup(groups[i].address, ADDRESS_ZERO, head);
      }
    });

    it("should revert when group is healthy", async () => {
      await expect(
        defaultStrategyContract.deactivateUnhealthyGroup(groupAddresses[1])
      ).revertedWith(`HealthyGroup("${groupAddresses[1]}")`);
    });

    describe("when the group is not elected", () => {
      beforeEach(async () => {
        await mineToNextEpoch(hre.web3);
        await revokeElectionOnMockValidatorGroupsAndUpdate(
          validators,
          accountsWrapper,
          groupHealthContract,
          [groupAddresses[1]]
        );
      });

      it("should remove group", async () => {
        await expect(await defaultStrategyContract.deactivateUnhealthyGroup(groupAddresses[1]))
          .to.emit(defaultStrategyContract, "GroupRemoved")
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

      it("should remove group", async () => {
        await expect(
          await defaultStrategyContract.deactivateUnhealthyGroup(deactivatedGroup.address)
        )
          .to.emit(defaultStrategyContract, "GroupRemoved")
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

      it("should remove group", async () => {
        await expect(
          await defaultStrategyContract.deactivateUnhealthyGroup(deactivatedGroup.address)
        )
          .to.emit(defaultStrategyContract, "GroupRemoved")
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
          defaultStrategyContract.deactivateUnhealthyGroup(
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

      it("should remove group", async () => {
        await expect(
          await defaultStrategyContract.deactivateUnhealthyGroup(deactivatedGroup.address)
        )
          .to.emit(defaultStrategyContract, "GroupRemoved")
          .withArgs(groupAddresses[1]);
      });
    });
  });

  describe("V1 -> V2 migration test", () => {
    const votes = [parseUnits("95824"), parseUnits("0"), parseUnits("95664")];

    beforeEach(async () => {
      for (let i = 0; i < 3; i++) {
        await account.setCeloForGroup(groupAddresses[i], votes[i]);
      }
    });

    it("should set correct accounting for group[0]", async () => {
      await defaultStrategyContract.activateGroup(groupAddresses[0], ADDRESS_ZERO, ADDRESS_ZERO);

      const stCeloInDefault = await defaultStrategyContract.stCeloInGroup(groupAddresses[0]);
      expect(stCeloInDefault).to.deep.eq(votes[0]);
    });

    it("should set correct accounting for group that has 0 celo locked", async () => {
      await defaultStrategyContract.activateGroup(groupAddresses[1], ADDRESS_ZERO, ADDRESS_ZERO);

      const stCeloInDefault = await defaultStrategyContract.stCeloInGroup(groupAddresses[1]);
      expect(stCeloInDefault).to.deep.eq(BigNumber.from("0"));
    });
  });
});
