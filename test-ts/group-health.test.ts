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

  let validatorsWrapper: ValidatorsWrapper;
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
      this.timeout(100000);
      await resetNetwork();

      [nonManager] = await randomSigner(parseUnits("100"));
      [owner] = await randomSigner(parseUnits("100"));
      [mockSlasher] = await randomSigner(parseUnits("100"));

      lockedGold = await hre.kit.contracts.getLockedGold();
      validatorsWrapper = await hre.kit.contracts.getValidators();

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

  describe("#isValidGroup()", () => {
    it("should return invalid when not updated", async () => {
      const valid = await groupHealthContract.isValidGroup(nonManager.address);
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
        const valid = await groupHealthContract.isValidGroup(nonManager.address);
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
          const valid = await groupHealthContract.isValidGroup(activatedGroupAddresses[0]);
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
              const valid = await groupHealthContract.isValidGroup(activatedGroupAddresses[0]);
              expect(true).to.eq(valid);
            });
          });

          describe("When updated to invalid", () => {
            beforeEach(async () => {
              await revokeElectionOnMockValidatorGroupsAndUpdate(
                validatorsWrapper,
                groupHealthContract,
                [activatedGroupAddresses[0]]
              );
            });

            it("should return invalid", async () => {
              const valid = await groupHealthContract.isValidGroup(activatedGroupAddresses[0]);
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
          activatedGroupAddresses
        );
      });

      it("should update to valid", async () => {
        await expect(groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]))
          .to.emit(groupHealthContract, "GroupHealthUpdated")
          .withArgs(activatedGroupAddresses[0], true);
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
        await revokeElectionOnMockValidatorGroupsAndUpdate(validatorsWrapper, groupHealthContract, [
          activatedGroupAddresses[0],
        ]);
        await expect(groupHealthContract.updateGroupHealth(activatedGroupAddresses[0]))
          .to.emit(groupHealthContract, "GroupHealthUpdated")
          .withArgs(activatedGroupAddresses[0], false);
      });
    });
  });
});
