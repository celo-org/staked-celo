import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { Manager } from "../typechain-types/Manager";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import {
  ADDRESS_ZERO,
  electMockValidatorGroupsAndUpdate,
  getImpersonatedSigner,
  mineToNextEpoch,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  resetNetwork,
  revokeElectionOnMockValidatorGroupsAndUpdate,
} from "./utils";

after(() => {
  hre.kit.stop();
});

describe("GroupHealth", () => {
  let manager: Manager;
  let groupHealthContract: MockGroupHealth;
  let nonVote: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;
  let nonManager: SignerWithAddress;

  let nonOwner: SignerWithAddress;
  let validatorsWrapper: ValidatorsWrapper;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  before(async function () {
    try {
      this.timeout(100000);
      await resetNetwork();

      await hre.deployments.fixture("FullTestManager");
      manager = await hre.ethers.getContract("Manager");
      groupHealthContract = await hre.ethers.getContract("MockGroupHealth");

      [nonOwner] = await randomSigner(parseUnits("100"));
      [nonVote] = await randomSigner(parseUnits("100000"));
      [nonStakedCelo] = await randomSigner(parseUnits("100"));
      [nonAccount] = await randomSigner(parseUnits("100"));
      [nonManager] = await randomSigner(parseUnits("100"));
    } catch (error) {
      console.error(error);
    }
  });

  beforeEach(async () => {
    snapshotId = await hre.ethers.provider.send("evm_snapshot", []);
    validatorsWrapper = await hre.kit.contracts.getValidators();
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

    it("reverts with zero StakedCelo address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(
            ADDRESS_ZERO,
            nonVote.address,
            nonVote.address,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("StakedCelo null");
    });

    it("reverts with zero Account address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(
            nonVote.address,
            ADDRESS_ZERO,
            nonVote.address,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("Account null");
    });

    it("reverts with zero specific group strategy address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(
            nonVote.address,
            nonVote.address,
            ADDRESS_ZERO,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("SpecificGroupStrategy null");
    });

    it("reverts with zero default strategy address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(
            nonVote.address,
            nonVote.address,
            nonVote.address,
            ADDRESS_ZERO,
            nonVote.address
          )
      ).revertedWith("DefaultStrategy null");
    });

    it("reverts with zero Manager address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(
            nonVote.address,
            nonVote.address,
            nonVote.address,
            nonVote.address,
            ADDRESS_ZERO
          )
      ).revertedWith("Manager null");
    });

    it("sets the vote contract", async () => {
      await groupHealthContract
        .connect(ownerSigner)
        .setDependencies(
          nonStakedCelo.address,
          nonAccount.address,
          nonVote.address,
          nonOwner.address,
          nonManager.address
        );

      const stakedCelo = await groupHealthContract.stakedCelo();
      expect(stakedCelo).to.eq(nonStakedCelo.address);

      const account = await groupHealthContract.account();
      expect(account).to.eq(nonAccount.address);

      const specificGroupStrategy = await groupHealthContract.specificGroupStrategy();
      expect(specificGroupStrategy).to.eq(nonVote.address);

      const defaultStrategy = await groupHealthContract.defaultStrategy();
      expect(defaultStrategy).to.eq(nonOwner.address);

      const manager = await groupHealthContract.manager();
      expect(manager).to.eq(nonManager.address);
    });

    it("cannot be called by a non-Owner account", async () => {
      await expect(
        groupHealthContract
          .connect(nonOwner)
          .setDependencies(
            nonStakedCelo.address,
            nonAccount.address,
            nonAccount.address,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("#isValidGroup()", () => {
    const groups: SignerWithAddress[] = [];
    const activatedGroupAddresses: string[] = [];
    const groupAddresses: string[] = [];
    const validators: SignerWithAddress[] = [];
    const validatorAddresses: string[] = [];

    before(async () => {
      try {
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

    it("should return invalid when not updated", async () => {
      const valid = await groupHealthContract.isValidGroup(nonManager.address);
      expect(false).to.eq(valid);
    });

    it("should revert update when invalid indexes length provided", async () => {
      await expect(
        groupHealthContract.updateGroupHealth(activatedGroupAddresses[0], [])
      ).revertedWith(`MembersLengthMismatch()`);
    });

    describe("When validity updated (invalid)", () => {
      beforeEach(async () => {
        await groupHealthContract.updateGroupHealth(activatedGroupAddresses[0], [
          Number.MAX_SAFE_INTEGER.toString(),
        ]);
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

        it("should not allow to update to valid again since it was updated to valid this epoch already", async () => {
          await expect(
            groupHealthContract.updateGroupHealth(activatedGroupAddresses[0], [])
          ).revertedWith(`ValidatorGroupAlreadyUpdatedInEpoch("${activatedGroupAddresses[0]}")`);
        });

        it("should not allow to update to invalid again since it was updated to valid this epoch already", async () => {
          const mockIndex = 6;
          await groupHealthContract.setElectedValidator(mockIndex, ADDRESS_ZERO);
          await expect(
            groupHealthContract.updateGroupHealth(activatedGroupAddresses[0], [mockIndex])
          ).revertedWith(`ValidatorGroupAlreadyUpdatedInEpoch("${activatedGroupAddresses[0]}")`);
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

            it("should not allow to update again since it was updated to valid this epoch already", async () => {
              await expect(
                groupHealthContract.updateGroupHealth(activatedGroupAddresses[0], [])
              ).revertedWith(
                `ValidatorGroupAlreadyUpdatedInEpoch("${activatedGroupAddresses[0]}")`
              );
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

            it("should allow to update again since group is invalid", async () => {
              const indexes: number[] = [];
              const validatorGroupDetail = await validatorsWrapper.getValidatorGroup(
                activatedGroupAddresses[0]
              );
              for (let i = 0; i < validatorGroupDetail.members.length; i++) {
                await groupHealthContract.setElectedValidator(i, validatorGroupDetail.members[i]);
                indexes.push(i);
              }

              await groupHealthContract.updateGroupHealth(activatedGroupAddresses[0], indexes);
            });
          });
        });
      });
    });
  });
});
