import { AccountsWrapper } from "@celo/contractkit/lib/wrappers/Accounts";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { MockLockedGold__factory } from "../typechain-types/factories/MockLockedGold__factory";
import { MockRegistry__factory } from "../typechain-types/factories/MockRegistry__factory";
import { MockValidators__factory } from "../typechain-types/factories/MockValidators__factory";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { MockLockedGold } from "../typechain-types/MockLockedGold";
import { MockRegistry } from "../typechain-types/MockRegistry";
import { MockValidators } from "../typechain-types/MockValidators";
import {
  ADDRESS_ZERO,
  deregisterValidatorGroup,
  electMockValidatorGroupsAndUpdate,
  mineToNextEpoch,
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

describe("GroupHealth", () => {
  let groupHealthContract: MockGroupHealth;
  let nonManager: SignerWithAddress;
  let pauser: SignerWithAddress;

  let validatorsWrapper: ValidatorsWrapper;
  let accountsWrapper: AccountsWrapper;
  let registryContract: MockRegistry;
  let owner: SignerWithAddress;
  let lockedGoldContract: MockLockedGold;
  let validatorsContract: MockValidators;
  let lockedGold: LockedGoldWrapper;
  let mockSlasher: SignerWithAddress;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  const groups: SignerWithAddress[] = [];
  const activatedGroups: SignerWithAddress[] = [];
  const activatedGroupAddresses: string[] = [];
  const groupAddresses: string[] = [];
  const validators: SignerWithAddress[] = [];
  const validatorAddresses: string[] = [];

  before(async function () {
    try {
      this.timeout(0);
      await resetNetwork();

      [nonManager] = await randomSigner(parseUnits("100"));
      owner = await hre.ethers.getNamedSigner("owner");
      [mockSlasher] = await randomSigner(parseUnits("100"));
      [pauser] = await randomSigner(parseUnits("100"));

      lockedGold = await hre.kit.contracts.getLockedGold();
      validatorsWrapper = await hre.kit.contracts.getValidators();
      accountsWrapper = await hre.kit.contracts.getAccounts();

      await hre.deployments.fixture("FullTestManager");
      groupHealthContract = await hre.ethers.getContract("MockGroupHealth");

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
      validatorsContract = validatorsFactory.attach(validatorsWrapper.address);

      const validatorMembers = 3;

      for (let i = 0; i < 10; i++) {
        const [group] = await randomSigner(parseUnits("11000").mul(validatorMembers));
        groups.push(group);
        if (i < 3) {
          activatedGroupAddresses.push(groups[i].address);
          activatedGroups.push(groups[i]);
        }
        groupAddresses.push(groups[i].address);

        await registerValidatorGroup(groups[i], validatorMembers);

        for (let j = 0; j < validatorMembers; j++) {
          const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
          validators.push(validator);
          validatorAddresses.push(validator.address);
          await registerValidatorAndAddToGroupMembers(groups[i], validator, validatorWallet);
        }

        await groupHealthContract.connect(owner).setPauser(pauser.address);
      }
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

  describe("#isGroupValid()", () => {
    it("should return invalid when not updated", async () => {
      const valid = await groupHealthContract.isGroupValid(nonManager.address);
      expect(false).to.eq(valid);
    });

    describe("When validity updated (invalid)", () => {
      beforeEach(async () => {
        for (let i = 0; i < 150; i++) {
          await groupHealthContract.setElectedValidator(i, nonManager.address);
        }

        await groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]);
      });

      it("should return invalid", async () => {
        const valid = await groupHealthContract.isGroupValid(nonManager.address);
        expect(false).to.eq(valid);
      });

      describe("When valid group and updated", () => {
        beforeEach(async () => {
          await electMockValidatorGroupsAndUpdate(
            validatorsWrapper,
            groupHealthContract,
            activatedGroupAddresses
          );
        });

        it("should be valid", async () => {
          const valid = await groupHealthContract.isGroupValid(activatedGroupAddresses[0]);
          expect(true).to.eq(valid);
        });

        describe("When in next epoch", () => {
          beforeEach(async () => {
            await mineToNextEpoch(hre.web3);
          });

          describe("When updated to valid", () => {
            beforeEach(async () => {
              await electMockValidatorGroupsAndUpdate(validatorsWrapper, groupHealthContract, [
                activatedGroupAddresses[0],
              ]);
            });

            it("should return valid", async () => {
              const valid = await groupHealthContract.isGroupValid(activatedGroupAddresses[0]);
              expect(true).to.eq(valid);
            });
          });

          describe("When updated to invalid", () => {
            beforeEach(async () => {
              await revokeElectionOnMockValidatorGroupsAndUpdate(
                validatorsWrapper,
                accountsWrapper,
                groupHealthContract,
                [activatedGroupAddresses[0]]
              );
            });

            it("should return invalid", async () => {
              const valid = await groupHealthContract.isGroupValid(activatedGroupAddresses[0]);
              expect(false).to.eq(valid);
            });
          });
        });
      });
    });
  });

  describe("#updateGroupHealth()", () => {
    describe("When updated", () => {
      beforeEach(async () => {
        await electMockValidatorGroupsAndUpdate(
          validatorsWrapper,
          groupHealthContract,
          activatedGroupAddresses,
          false,
          false
        );
      });

      it("should update to valid", async () => {
        await expect(groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]))
          .to.emit(groupHealthContract, "GroupHealthUpdated")
          .withArgs(activatedGroupAddresses[0], true);
      });

      describe("When valid", () => {
        beforeEach(async () => {
          await groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]);
          expect(await groupHealthContract.isGroupValid(activatedGroupAddresses[0])).to.be.true;
        });

        it("should update to invalid when slashed", async () => {
          await updateGroupSlashingMultiplier(
            registryContract,
            lockedGoldContract,
            validatorsContract,
            activatedGroups[0],
            mockSlasher
          );
          await expect(groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]))
            .to.emit(groupHealthContract, "GroupHealthUpdated")
            .withArgs(activatedGroupAddresses[0], false);
        });

        it("should update to invalid when no members", async () => {
          await removeMembersFromGroup(activatedGroups[0]);
          await expect(groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]))
            .to.emit(groupHealthContract, "GroupHealthUpdated")
            .withArgs(activatedGroupAddresses[0], false);
        });

        it("should update to invalid when group not registered", async () => {
          await deregisterValidatorGroup(activatedGroups[0]);
          await expect(groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]))
            .to.emit(groupHealthContract, "GroupHealthUpdated")
            .withArgs(activatedGroupAddresses[0], false);
        });

        it("should update to invalid when group not elected", async () => {
          await revokeElectionOnMockValidatorGroupsAndUpdate(
            validatorsWrapper,
            accountsWrapper,
            groupHealthContract,
            [activatedGroupAddresses[0]],
            false
          );
          await expect(groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]))
            .to.emit(groupHealthContract, "GroupHealthUpdated")
            .withArgs(activatedGroupAddresses[0], false);
        });
      });
    });
  });

  describe("#markGroupHealthy()", () => {
    it("reverts when group is already healthy", async () => {
      const mockedIndexes = await electMockValidatorGroupsAndUpdate(
        validatorsWrapper,
        groupHealthContract,
        activatedGroupAddresses
      );
      await expect(
        groupHealthContract.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes)
      ).revertedWith(`GroupHealthy("${activatedGroupAddresses[0]}")`);
    });

    it("should revert when wrong index length provided", async () => {
      await expect(groupHealthContract.markGroupHealthy(groupAddresses[0], [])).revertedWith(
        `MembersLengthMismatch()`
      );
    });

    describe("When validator members elected", () => {
      let mockedIndexes: number[];
      beforeEach(async () => {
        mockedIndexes = await electMockValidatorGroupsAndUpdate(
          validatorsWrapper,
          groupHealthContract,
          [activatedGroupAddresses[0]],
          false,
          false
        );
        expect(await groupHealthContract.isGroupValid(groupAddresses[0])).to.be.false;
      });

      it("should update group to healthy when correct indexes were provided", async () => {
        await groupHealthContract.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        expect(await groupHealthContract.isGroupValid(groupAddresses[0])).to.be.true;
      });

      it("should not update group to healthy when group slashed", async () => {
        await updateGroupSlashingMultiplier(
          registryContract,
          lockedGoldContract,
          validatorsContract,
          activatedGroups[0],
          mockSlasher
        );
        await groupHealthContract.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        expect(await groupHealthContract.isGroupValid(groupAddresses[0])).to.be.false;
      });

      it("should not update group to healthy when group not validator group", async () => {
        await deregisterValidatorGroup(activatedGroups[0]);
        await groupHealthContract.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        expect(await groupHealthContract.isGroupValid(groupAddresses[0])).to.be.false;
      });

      it("should not update group to healthy when validator groups not elected", async () => {
        await revokeElectionOnMockValidatorGroupsAndUpdate(
          validatorsWrapper,
          accountsWrapper,
          groupHealthContract,
          [activatedGroupAddresses[0]]
        );
        await groupHealthContract.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        expect(await groupHealthContract.isGroupValid(groupAddresses[0])).to.be.false;
      });

      it("should not update group to healthy when no members", async () => {
        await removeMembersFromGroup(activatedGroups[0]);
        await groupHealthContract.markGroupHealthy(activatedGroupAddresses[0], mockedIndexes);
        expect(await groupHealthContract.isGroupValid(groupAddresses[0])).to.be.false;
      });
    });
  });

  describe("#setPauser", () => {
    it("sets the pauser address", async () => {
      await groupHealthContract.connect(owner).setPauser(nonManager.address);
      const newPauser = await groupHealthContract.pauser();
      expect(newPauser).to.eq(nonManager.address);
    });

    it("emits a PauserSet event", async () => {
      await expect(groupHealthContract.connect(owner).setPauser(nonManager.address))
        .to.emit(groupHealthContract, "PauserSet")
        .withArgs(nonManager.address);
    });

    it("cannot be called by a non-owner", async () => {
      await expect(
        groupHealthContract.connect(nonManager).setPauser(nonManager.address)
      ).revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("#pause", () => {
    it("can be called by the pauser", async () => {
      await groupHealthContract.connect(pauser).pause();
      const isPaused = await groupHealthContract.isPaused();
      expect(isPaused).to.be.true;
    });

    it("emits a ContractPaused event", async () => {
      await expect(groupHealthContract.connect(pauser).pause()).to.emit(
        groupHealthContract,
        "ContractPaused"
      );
    });

    it("cannot be called by the owner", async () => {
      await expect(groupHealthContract.connect(owner).pause()).revertedWith("OnlyPauser()");
      const isPaused = await groupHealthContract.isPaused();
      expect(isPaused).to.be.false;
    });

    it("cannot be called by a random account", async () => {
      await expect(groupHealthContract.connect(nonManager).pause()).revertedWith("OnlyPauser()");
      const isPaused = await groupHealthContract.isPaused();
      expect(isPaused).to.be.false;
    });
  });

  describe("#unpause", () => {
    beforeEach(async () => {
      await groupHealthContract.connect(pauser).pause();
    });

    it("can be called by the pauser", async () => {
      await groupHealthContract.connect(pauser).unpause();
      const isPaused = await groupHealthContract.isPaused();
      expect(isPaused).to.be.false;
    });

    it("emits a ContractUnpaused event", async () => {
      await expect(groupHealthContract.connect(pauser).unpause()).to.emit(
        groupHealthContract,
        "ContractUnpaused"
      );
    });

    it("cannot be called by the owner", async () => {
      await expect(groupHealthContract.connect(owner).pause()).revertedWith("OnlyPauser()");
      const isPaused = await groupHealthContract.isPaused();
      expect(isPaused).to.be.true;
    });

    it("cannot be called by a random account", async () => {
      await expect(groupHealthContract.connect(nonManager).unpause()).revertedWith("OnlyPauser()");
      const isPaused = await groupHealthContract.isPaused();
      expect(isPaused).to.be.true;
    });
  });

  describe("when paused", () => {
    beforeEach(async () => {
      await groupHealthContract.connect(pauser).pause();
    });

    it("can't call updateGroupHealth", async () => {
      await expect(
        groupHealthContract.connect(nonManager).updateGroupHealth(ADDRESS_ZERO)
      ).revertedWith("Paused()");
    });

    it("can't call markGroupHealthy", async () => {
      await expect(
        groupHealthContract.connect(nonManager).markGroupHealthy(ADDRESS_ZERO, [0])
      ).revertedWith("Paused()");
    });
  });
});
