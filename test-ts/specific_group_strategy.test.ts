import { AccountsWrapper } from "@celo/contractkit/lib/wrappers/Accounts";
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
import { MockStakedCelo__factory } from "../typechain-types/factories/MockStakedCelo__factory";
import { MockVote__factory } from "../typechain-types/factories/MockVote__factory";
import { Manager } from "../typechain-types/Manager";
import { MockAccount } from "../typechain-types/MockAccount";
import { MockDefaultStrategy } from "../typechain-types/MockDefaultStrategy";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { MockStakedCelo } from "../typechain-types/MockStakedCelo";
import { MockVote } from "../typechain-types/MockVote";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import {
  ADDRESS_ZERO,
  deregisterValidatorGroup,
  electMockValidatorGroupsAndUpdate,
  getBlockedSpecificGroupStrategies,
  getDefaultGroups,
  getImpersonatedSigner,
  getSpecificGroups,
  prepareOverflow,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  resetNetwork,
  revokeElectionOnMockValidatorGroupsAndUpdate,
  updateGroupCeloBasedOnProtocolStCelo,
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
  let stakedCelo: MockStakedCelo;
  let voteContract: MockVote;
  let groupHealthContract: MockGroupHealth;
  let defaultStrategyContract: MockDefaultStrategy;
  let election: ElectionWrapper;
  let lockedGold: LockedGoldWrapper;
  let validatorsWrapper: ValidatorsWrapper;
  let accountsWrapper: AccountsWrapper;

  let pauser: SignerWithAddress;
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

      owner = await hre.ethers.getNamedSigner("owner");
      pauser = owner;
      [nonOwner] = await randomSigner(parseUnits("100"));
      [nonVote] = await randomSigner(parseUnits("100000"));
      [nonStakedCelo] = await randomSigner(parseUnits("100"));
      [nonAccount] = await randomSigner(parseUnits("100"));
      [nonManager] = await randomSigner(parseUnits("100"));
      [voter] = await randomSigner(parseUnits("10000000000"));
      [someone] = await randomSigner(parseUnits("100"));
      [depositor] = await randomSigner(parseUnits("500"));
      validatorsWrapper = await hre.kit.contracts.getValidators();
      accountsWrapper = await hre.kit.contracts.getAccounts();

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

      await manager
        .connect(owner)
        .setDependencies(
          stakedCelo.address,
          account.address,
          voteContract.address,
          groupHealthContract.address,
          specificGroupStrategyContract.address,
          defaultStrategyContract.address
        );

      await specificGroupStrategyContract
        .connect(owner)
        .setDependencies(
          account.address,
          groupHealthContract.address,
          defaultStrategyContract.address
        );

      await defaultStrategyContract
        .connect(owner)
        .setDependencies(
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

      await specificGroupStrategyContract.connect(owner).setPauser();
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
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero groupHealth address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, ADDRESS_ZERO, nonVote.address)
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero defaultStrategy address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, nonVote.address, ADDRESS_ZERO)
      ).revertedWith("AddressZeroNotAllowed");
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

  describe("#generateWithdrawalVoteDistribution()", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(nonManager)
          .generateWithdrawalVoteDistribution(nonVote.address, 10, 10, false)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#generateDepositVoteDistribution()", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(nonManager)
          .generateDepositVoteDistribution(nonVote.address, 10, 10)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#blockGroup()", () => {
    it("reverts when no active groups", async () => {
      await expect(
        specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[3])
      ).revertedWith(`NoActiveGroups()`);
    });

    describe("When 2 active groups", () => {
      let specificGroupStrategy: SignerWithAddress;
      beforeEach(async () => {
        specificGroupStrategy = groups[2];
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.connect(owner).addActivatableGroup(groups[i].address);
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
          const activeGroups = await getDefaultGroups(defaultStrategyContract);
          const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(specificStrategies).to.deep.eq([specificGroupStrategy.address]);
        });

        it("adds the group to blocked groups array", async () => {
          await specificGroupStrategyContract
            .connect(owner)
            .blockGroup(specificGroupStrategy.address);
          const activeGroups = await getDefaultGroups(defaultStrategyContract);
          const blockedGroups = await getBlockedSpecificGroupStrategies(
            specificGroupStrategyContract
          );
          const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
          expect(activeGroups).to.have.deep.members([groupAddresses[0], groupAddresses[1]]);
          expect(specificStrategies).to.deep.eq([specificGroupStrategy.address]);
          expect(blockedGroups).to.deep.eq([specificGroupStrategy.address]);
        });

        it("emits a StrategyBlocked event", async () => {
          await expect(
            specificGroupStrategyContract.connect(owner).blockGroup(specificGroupStrategy.address)
          )
            .to.emit(specificGroupStrategyContract, "GroupBlocked")
            .withArgs(specificGroupStrategy.address);
        });

        it("should add blocked strategy to blocked strategies", async () => {
          await specificGroupStrategyContract
            .connect(owner)
            .blockGroup(specificGroupStrategy.address);
          await specificGroupStrategyContract.rebalanceWhenHealthChanged(
            specificGroupStrategy.address
          );
          const blockedStrategies = await getBlockedSpecificGroupStrategies(
            specificGroupStrategyContract
          );
          expect(blockedStrategies).to.have.deep.members([specificGroupStrategy.address]);
        });

        it("should update accounting correctly", async () => {
          await specificGroupStrategyContract
            .connect(owner)
            .blockGroup(specificGroupStrategy.address);
          await specificGroupStrategyContract.rebalanceWhenHealthChanged(
            specificGroupStrategy.address
          );
          const [total, overflow, unhealthy] = await specificGroupStrategyContract.getStCeloInGroup(
            specificGroupStrategy.address
          );
          expect(total).to.deep.eq(BigNumber.from(specificGroupStrategyDeposit));
          expect(overflow).to.deep.eq(BigNumber.from("0"));
          expect(unhealthy).to.deep.eq(BigNumber.from(specificGroupStrategyDeposit));
        });

        it("reverts when blocking already blocked strategy", async () => {
          await specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[3]);
          await expect(
            specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[3])
          ).revertedWith(`GroupAlreadyBlocked("${groupAddresses[3]}")`);
        });

        it("cannot be called by a non owner", async () => {
          await expect(
            specificGroupStrategyContract
              .connect(nonOwner)
              .blockGroup(specificGroupStrategy.address)
          ).revertedWith("Ownable: caller is not the owner");
        });

        it("should schedule transfers to default strategy", async () => {
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await specificGroupStrategyContract
            .connect(owner)
            .blockGroup(specificGroupStrategy.address);
          await specificGroupStrategyContract.rebalanceWhenHealthChanged(
            specificGroupStrategy.address
          );
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

  describe("#unblockGroup", () => {
    it("should revert when unhealthy group", async () => {
      await deregisterValidatorGroup(groups[0]);
      await groupHealthContract.updateGroupHealth(groupAddresses[0]);
      await expect(
        specificGroupStrategyContract.connect(owner).unblockGroup(groupAddresses[0])
      ).revertedWith(`GroupNotEligible("${groupAddresses[0]}")`);
    });

    it("should revert when not blocked strategy", async () => {
      await expect(
        specificGroupStrategyContract.connect(owner).unblockGroup(groupAddresses[0])
      ).revertedWith(`FailedToUnblockGroup("${groupAddresses[0]}")`);
    });

    describe("when the group is blocked", () => {
      let specificGroupStrategy: SignerWithAddress;
      let specificGroupStrategyDeposit: BigNumber;
      beforeEach(async () => {
        specificGroupStrategy = groups[2];
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.connect(owner).addActivatableGroup(groups[i].address);
          await defaultStrategyContract.activateGroup(groups[i].address, ADDRESS_ZERO, head);
        }

        specificGroupStrategyDeposit = parseUnits("1");
        await account.setCeloForGroup(specificGroupStrategy.address, specificGroupStrategyDeposit);
        await manager.connect(depositor).changeStrategy(specificGroupStrategy.address);
        await manager.connect(depositor).deposit({ value: specificGroupStrategyDeposit });
        await specificGroupStrategyContract
          .connect(owner)
          .blockGroup(specificGroupStrategy.address);
      });

      it("should have blocked strategy", async () => {
        const blockedGroups = await getBlockedSpecificGroupStrategies(
          specificGroupStrategyContract
        );
        expect(blockedGroups).to.have.deep.members([specificGroupStrategy.address]);
      });

      it("should allow to unblock strategy", async () => {
        await specificGroupStrategyContract
          .connect(owner)
          .unblockGroup(specificGroupStrategy.address);
        const blockedGroups = await getBlockedSpecificGroupStrategies(
          specificGroupStrategyContract
        );
        expect(blockedGroups).to.have.deep.members([]);
      });
    });
  });

  describe("#rebalanceOverflowedGroup()", () => {
    const thirdGroupCapacity = parseUnits("200.166666666666666666");

    beforeEach(async () => {
      await prepareOverflow(
        defaultStrategyContract.connect(owner),
        election,
        lockedGold,
        voter,
        groupAddresses
      );
    });

    it("should revert when from group is not overflowing", async () => {
      await expect(
        specificGroupStrategyContract.rebalanceOverflowedGroup(groupAddresses[0])
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
          specificGroupStrategyContract.rebalanceOverflowedGroup(groupAddresses[2])
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
          [, originalOverflow] = await specificGroupStrategyContract.getStCeloInGroup(
            groupAddresses[2]
          );
        });

        describe("When different ratio of CELO vs stCELO", () => {
          describe("When 1:1", () => {
            beforeEach(async () => {
              await specificGroupStrategyContract.rebalanceOverflowedGroup(groupAddresses[2]);
            });

            it("should return 0 overflow", async () => {
              const [total, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
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

          describe("When there is more CELO than stCELO", () => {
            beforeEach(async () => {
              await account.setTotalCelo(deposit.mul(2));
              await updateGroupCeloBasedOnProtocolStCelo(
                defaultStrategyContract,
                specificGroupStrategyContract,
                account,
                manager
              );
              await account.setCeloForGroup(groupAddresses[2], BigNumber.from("0"));
              await specificGroupStrategyContract.rebalanceOverflowedGroup(groupAddresses[2]);
            });

            it("should return 0 overflow", async () => {
              const [total, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
                groupAddresses[2]
              );
              expect(overflow).to.deep.eq(BigNumber.from("0"));
              expect(total).to.deep.eq(deposit);
            });

            it("should remove stCelo from default strategy", async () => {
              const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
              expect(stCeloInDefault).to.deep.eq(BigNumber.from(0));
            });

            it("should remove overflow from specific group strategy", async () => {
              const [, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
                groupAddresses[2]
              );
              expect(overflow).to.deep.eq(BigNumber.from(0));
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
                originalOverflow.mul(2)
              );

              expect(lastTransferToGroups).to.have.deep.members([groupAddresses[2]]);
              expect(lastTransferToVotes).to.have.deep.members([originalOverflow.mul(2)]);
            });
          });

          describe("When there is less CELO than stCELO", () => {
            beforeEach(async () => {
              await account.setTotalCelo(deposit.div(2));
              await updateGroupCeloBasedOnProtocolStCelo(
                defaultStrategyContract,
                specificGroupStrategyContract,
                account,
                manager
              );

              await specificGroupStrategyContract.rebalanceOverflowedGroup(groupAddresses[2]);
            });

            it("should return 0 overflow", async () => {
              const [total, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
                groupAddresses[2]
              );
              expect(overflow).to.deep.eq(BigNumber.from("0"));
              expect(total).to.deep.eq(deposit);
            });

            it("should remove stCelo from default strategy", async () => {
              const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
              expect(stCeloInDefault).to.deep.eq(BigNumber.from(0));
            });

            it("should remove overflow from specific group strategy", async () => {
              const [, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
                groupAddresses[2]
              );
              expect(overflow).to.deep.eq(BigNumber.from(0));
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
                originalOverflow.div(2)
              );

              expect(lastTransferToGroups).to.have.deep.members([groupAddresses[2]]);
              expect(lastTransferToVotes).to.have.deep.members([originalOverflow.div(2)]);
            });
          });
        });
      });
    });
  });

  describe("#rebalanceWhenHealthChanged()", () => {
    let specificGroupAddress: string;

    beforeEach(async () => {
      specificGroupAddress = groupAddresses[4];
    });

    it("should revert when healthy and no unhealthy stCelo", async () => {
      expect(
        specificGroupStrategyContract.rebalanceWhenHealthChanged(specificGroupAddress)
      ).revertedWith(`GroupBalanced("${specificGroupAddress}")`);
    });

    describe("When group is unhealthy", () => {
      beforeEach(async () => {
        await revokeElectionOnMockValidatorGroupsAndUpdate(
          validatorsWrapper,
          accountsWrapper,
          groupHealthContract,
          [specificGroupAddress]
        );
      });

      it("should have unhealthy group", async () => {
        const isGroupValid = await groupHealthContract.isGroupValid(specificGroupAddress);
        expect(isGroupValid).to.be.false;
      });

      it("should revert when no stCelo in group", async () => {
        expect(
          specificGroupStrategyContract.rebalanceWhenHealthChanged(specificGroupAddress)
        ).revertedWith(`GroupBalanced("${specificGroupAddress}")`);
      });

      describe("When Celo deposited in group", () => {
        let deposit: BigNumber;

        beforeEach(async () => {
          deposit = parseUnits("1");
          await electMockValidatorGroupsAndUpdate(validatorsWrapper, groupHealthContract, [
            specificGroupAddress,
          ]);
          await manager.connect(depositor).changeStrategy(specificGroupAddress);
          await manager.connect(depositor).deposit({ value: deposit });
          await revokeElectionOnMockValidatorGroupsAndUpdate(
            validatorsWrapper,
            accountsWrapper,
            groupHealthContract,
            [specificGroupAddress]
          );
        });

        it("should have stCelo in strategy", async () => {
          const [total, overflow, unhealthy] = await specificGroupStrategyContract.getStCeloInGroup(
            specificGroupAddress
          );
          expect(total).to.deep.eq(deposit);
          expect(overflow).to.deep.eq(BigNumber.from("0"));
          expect(unhealthy).to.deep.eq(BigNumber.from("0"));
        });

        it("should revert when no active groups", async () => {
          await expect(
            specificGroupStrategyContract.rebalanceWhenHealthChanged(specificGroupAddress)
          ).revertedWith(`NoActiveGroups()`);
        });

        describe("When active groups and rebalanceWhenHealthChanged called", () => {
          let tail: string;
          beforeEach(async () => {
            await prepareOverflow(
              defaultStrategyContract.connect(owner),
              election,
              lockedGold,
              voter,
              groupAddresses
            );
            [tail] = await defaultStrategyContract.getGroupsTail();
            await specificGroupStrategyContract.rebalanceWhenHealthChanged(specificGroupAddress);
          });

          it("should have stCelo unhealthy stCelo in strategy", async () => {
            const [total, overflow, unhealthy] =
              await specificGroupStrategyContract.getStCeloInGroup(specificGroupAddress);
            expect(total).to.deep.eq(deposit);
            expect(overflow).to.deep.eq(BigNumber.from("0"));
            expect(unhealthy).to.deep.eq(deposit);
          });

          it("should schedule transfers", async () => {
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.have.deep.members([specificGroupAddress]);
            expect(lastTransferFromVotes).to.deep.eq([deposit]);

            expect(lastTransferToGroups).to.have.deep.members([tail]);
            expect(lastTransferToVotes).to.deep.eq([deposit]);
          });

          it("should update stCelo in Default strategy", async () => {
            const stCeloInDefault = await defaultStrategyContract.stCeloInGroup(tail);
            expect(stCeloInDefault).to.deep.eq(deposit);
          });

          describe("When group becomes healthy again", () => {
            let head: string;
            beforeEach(async () => {
              [head] = await defaultStrategyContract.getGroupsHead();
              await electMockValidatorGroupsAndUpdate(validatorsWrapper, groupHealthContract, [
                specificGroupAddress,
              ]);
              await updateGroupCeloBasedOnProtocolStCelo(
                defaultStrategyContract,
                specificGroupStrategyContract,
                account,
                manager
              );
              await specificGroupStrategyContract.rebalanceWhenHealthChanged(specificGroupAddress);
            });

            it("should remove unhealthy stCelo", async () => {
              const [total, overflow, unhealthy] =
                await specificGroupStrategyContract.getStCeloInGroup(specificGroupAddress);
              expect(total).to.deep.eq(deposit);
              expect(overflow).to.deep.eq(BigNumber.from("0"));
              expect(unhealthy).to.deep.eq(BigNumber.from("0"));
            });

            it("should schedule transfers", async () => {
              const [
                lastTransferFromGroups,
                lastTransferFromVotes,
                lastTransferToGroups,
                lastTransferToVotes,
              ] = await account.getLastTransferValues();

              expect(lastTransferFromGroups).to.have.deep.members([head]);
              expect(lastTransferFromVotes).to.deep.eq([deposit]);

              expect(lastTransferToGroups).to.have.deep.members([specificGroupAddress]);
              expect(lastTransferToVotes).to.deep.eq([deposit]);
            });

            it("should update stCelo in Default strategy", async () => {
              const stCeloInDefault = await defaultStrategyContract.stCeloInGroup(tail);
              expect(stCeloInDefault).to.deep.eq(BigNumber.from("0"));
            });
          });
        });
      });
    });

    describe("When overflowing group is blocked", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      const depositOverCapacity = parseUnits("10");
      let deposit: BigNumber;
      let tail: string;
      let specificOverflowingGroup: string;

      describe("When different ratio of CELO vs stCELO", () => {
        describe("When ratio 1:1", () => {
          beforeEach(async () => {
            specificOverflowingGroup = groupAddresses[0];
            deposit = firstGroupCapacity.add(depositOverCapacity);
            await manager.connect(depositor).changeStrategy(specificOverflowingGroup);
            await prepareOverflow(
              defaultStrategyContract.connect(owner),
              election,
              lockedGold,
              voter,
              groupAddresses
            );
            [tail] = await defaultStrategyContract.getGroupsTail();
            await manager.connect(depositor).deposit({ value: deposit });
            await specificGroupStrategyContract.connect(owner).blockGroup(specificOverflowingGroup);
            await specificGroupStrategyContract.rebalanceWhenHealthChanged(
              specificOverflowingGroup
            );
          });

          it("should have blocked group", async () => {
            const isGroupBlocked = await specificGroupStrategyContract.isBlockedGroup(
              specificOverflowingGroup
            );
            expect(isGroupBlocked).to.be.true;
          });

          it("should have stCelo unhealthy stCelo in strategy", async () => {
            const [total, overflow, unhealthy] =
              await specificGroupStrategyContract.getStCeloInGroup(specificOverflowingGroup);
            expect(total).to.deep.eq(deposit);
            expect(overflow).to.deep.eq(depositOverCapacity);
            expect(unhealthy).to.deep.eq(firstGroupCapacity);
          });

          it("should schedule transfers", async () => {
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.have.deep.members([specificOverflowingGroup]);
            expect(lastTransferFromVotes).to.deep.eq([firstGroupCapacity]);

            expect(lastTransferToGroups).to.have.deep.members([tail]);
            expect(lastTransferToVotes).to.deep.eq([firstGroupCapacity]);
          });

          it("should update stCelo in Default strategy", async () => {
            const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
            expect(stCeloInDefault).to.deep.eq(deposit);
          });

          describe("When group becomes unblocked again", () => {
            let head: string;
            beforeEach(async () => {
              [head] = await defaultStrategyContract.getGroupsHead();
              await specificGroupStrategyContract
                .connect(owner)
                .unblockGroup(specificOverflowingGroup);
              await updateGroupCeloBasedOnProtocolStCelo(
                defaultStrategyContract,
                specificGroupStrategyContract,
                account,
                manager
              );
              await specificGroupStrategyContract.rebalanceWhenHealthChanged(
                specificOverflowingGroup
              );
            });

            it("should remove unhealthy stCelo", async () => {
              const [total, overflow, unhealthy] =
                await specificGroupStrategyContract.getStCeloInGroup(specificOverflowingGroup);
              expect(total).to.deep.eq(deposit);
              expect(overflow).to.deep.eq(depositOverCapacity);
              expect(unhealthy).to.deep.eq(BigNumber.from("0"));
            });

            it("should schedule transfers", async () => {
              const [
                lastTransferFromGroups,
                lastTransferFromVotes,
                lastTransferToGroups,
                lastTransferToVotes,
              ] = await account.getLastTransferValues();

              expect(lastTransferFromGroups).to.have.deep.members([head]);
              expect(lastTransferFromVotes).to.deep.eq([firstGroupCapacity]);

              expect(lastTransferToGroups).to.have.deep.members([specificOverflowingGroup]);
              expect(lastTransferToVotes).to.deep.eq([firstGroupCapacity]);
            });

            it("should update stCelo in Default strategy", async () => {
              const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
              expect(stCeloInDefault).to.deep.eq(depositOverCapacity);
            });
          });
        });

        describe("When there is more CELO than stCELO", () => {
          beforeEach(async () => {
            specificOverflowingGroup = groupAddresses[0];
            deposit = firstGroupCapacity.add(depositOverCapacity);
            await manager.connect(depositor).changeStrategy(specificOverflowingGroup);
            await prepareOverflow(
              defaultStrategyContract.connect(owner),
              election,
              lockedGold,
              voter,
              groupAddresses
            );
            [tail] = await defaultStrategyContract.getGroupsTail();
            await manager.connect(depositor).deposit({ value: deposit });

            await account.setTotalCelo(deposit.mul(2));
            await updateGroupCeloBasedOnProtocolStCelo(
              defaultStrategyContract,
              specificGroupStrategyContract,
              account,
              manager
            );
            await specificGroupStrategyContract.connect(owner).blockGroup(specificOverflowingGroup);
            await account.setCeloForGroup(specificOverflowingGroup, BigNumber.from("0"));

            await specificGroupStrategyContract.rebalanceWhenHealthChanged(
              specificOverflowingGroup
            );
          });

          it("should have blocked group", async () => {
            const isGroupBlocked = await specificGroupStrategyContract.isBlockedGroup(
              specificOverflowingGroup
            );
            expect(isGroupBlocked).to.be.true;
          });

          it("should have stCelo unhealthy stCelo in strategy", async () => {
            const [total, overflow, unhealthy] =
              await specificGroupStrategyContract.getStCeloInGroup(specificOverflowingGroup);
            expect(total).to.deep.eq(deposit);
            expect(overflow).to.deep.eq(depositOverCapacity);
            expect(unhealthy).to.deep.eq(firstGroupCapacity);
          });

          it("should schedule transfers", async () => {
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.have.deep.members([specificOverflowingGroup]);
            expect(lastTransferFromVotes).to.deep.eq([firstGroupCapacity.mul(2)]);

            expect(lastTransferToGroups.length).to.eq(2);
            expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).to.deep.eq(
              firstGroupCapacity.mul(2)
            );
          });

          it("should update stCelo in Default strategy", async () => {
            const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
            expect(stCeloInDefault).to.deep.eq(deposit);
          });

          describe("When group becomes unblocked again", () => {
            let head: string;
            let previousToHead: string;
            beforeEach(async () => {
              [head, previousToHead] = await defaultStrategyContract.getGroupsHead();
              await specificGroupStrategyContract
                .connect(owner)
                .unblockGroup(specificOverflowingGroup);
              await updateGroupCeloBasedOnProtocolStCelo(
                defaultStrategyContract,
                specificGroupStrategyContract,
                account,
                manager
              );
              await specificGroupStrategyContract.rebalanceWhenHealthChanged(
                specificOverflowingGroup
              );
            });

            it("should remove unhealthy stCelo", async () => {
              const [total, overflow, unhealthy] =
                await specificGroupStrategyContract.getStCeloInGroup(specificOverflowingGroup);
              expect(total).to.deep.eq(deposit);
              expect(overflow).to.deep.eq(depositOverCapacity);
              expect(unhealthy).to.deep.eq(BigNumber.from("0"));
            });

            it("should schedule transfers", async () => {
              const [
                lastTransferFromGroups,
                lastTransferFromVotes,
                lastTransferToGroups,
                lastTransferToVotes,
              ] = await account.getLastTransferValues();

              expect(lastTransferFromGroups).to.have.deep.members([head, previousToHead]);
              expect(lastTransferFromVotes[0].add(lastTransferFromVotes[1])).to.deep.eq(
                firstGroupCapacity.mul(2)
              );

              expect(lastTransferToGroups).to.have.deep.members([specificOverflowingGroup]);
              expect(lastTransferToVotes).to.deep.eq([firstGroupCapacity.mul(2)]);
            });

            it("should update stCelo in Default strategy", async () => {
              const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
              expect(stCeloInDefault).to.deep.eq(depositOverCapacity);
            });
          });
        });

        describe("When there is less CELO than stCELO", () => {
          beforeEach(async () => {
            specificOverflowingGroup = groupAddresses[0];
            deposit = firstGroupCapacity.add(depositOverCapacity);
            await manager.connect(depositor).changeStrategy(specificOverflowingGroup);
            await prepareOverflow(
              defaultStrategyContract.connect(owner),
              election,
              lockedGold,
              voter,
              groupAddresses
            );
            [tail] = await defaultStrategyContract.getGroupsTail();
            await manager.connect(depositor).deposit({ value: deposit });

            await account.setTotalCelo(deposit.div(2));
            await updateGroupCeloBasedOnProtocolStCelo(
              defaultStrategyContract,
              specificGroupStrategyContract,
              account,
              manager
            );
            await specificGroupStrategyContract.connect(owner).blockGroup(specificOverflowingGroup);

            await specificGroupStrategyContract.rebalanceWhenHealthChanged(
              specificOverflowingGroup
            );
          });

          it("should have blocked group", async () => {
            const isGroupBlocked = await specificGroupStrategyContract.isBlockedGroup(
              specificOverflowingGroup
            );
            expect(isGroupBlocked).to.be.true;
          });

          it("should have stCelo unhealthy stCelo in strategy", async () => {
            const [total, overflow, unhealthy] =
              await specificGroupStrategyContract.getStCeloInGroup(specificOverflowingGroup);
            expect(total).to.deep.eq(deposit);
            expect(overflow).to.deep.eq(depositOverCapacity);
            expect(unhealthy).to.deep.eq(firstGroupCapacity);
          });

          it("should schedule transfers", async () => {
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.have.deep.members([specificOverflowingGroup]);
            expect(lastTransferFromVotes).to.deep.eq([firstGroupCapacity.div(2)]);

            expect(lastTransferToGroups.length).to.eq(1);
            expect(lastTransferToVotes).to.have.deep.members([firstGroupCapacity.div(2)]);
          });

          it("should update stCelo in Default strategy", async () => {
            const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
            expect(stCeloInDefault).to.deep.eq(deposit);
          });

          describe("When group becomes unblocked again", () => {
            let head: string;
            beforeEach(async () => {
              [head] = await defaultStrategyContract.getGroupsHead();
              await specificGroupStrategyContract
                .connect(owner)
                .unblockGroup(specificOverflowingGroup);
              await updateGroupCeloBasedOnProtocolStCelo(
                defaultStrategyContract,
                specificGroupStrategyContract,
                account,
                manager
              );
              await specificGroupStrategyContract.rebalanceWhenHealthChanged(
                specificOverflowingGroup
              );
            });

            it("should remove unhealthy stCelo", async () => {
              const [total, overflow, unhealthy] =
                await specificGroupStrategyContract.getStCeloInGroup(specificOverflowingGroup);
              expect(total).to.deep.eq(deposit);
              expect(overflow).to.deep.eq(depositOverCapacity);
              expect(unhealthy).to.deep.eq(BigNumber.from("0"));
            });

            it("should schedule transfers", async () => {
              const [
                lastTransferFromGroups,
                lastTransferFromVotes,
                lastTransferToGroups,
                lastTransferToVotes,
              ] = await account.getLastTransferValues();

              expect(lastTransferFromGroups).to.have.deep.members([head]);
              expect(lastTransferFromVotes[0]).to.deep.eq(firstGroupCapacity.div(2));

              expect(lastTransferToGroups).to.have.deep.members([specificOverflowingGroup]);
              expect(lastTransferToVotes).to.deep.eq([firstGroupCapacity.div(2)]);
            });

            it("should update stCelo in Default strategy", async () => {
              const stCeloInDefault = await defaultStrategyContract.totalStCeloInStrategy();
              expect(stCeloInDefault).to.deep.eq(depositOverCapacity);
            });
          });
        });
      });
    });
  });

  describe("#setPauser", () => {
    it("sets the pauser address to the owner of the contract", async () => {
      await specificGroupStrategyContract.connect(owner).setPauser();
      const newPauser = await specificGroupStrategyContract.pauser();
      expect(newPauser).to.eq(owner.address);
    });

    it("emits a PauserSet event", async () => {
      await expect(specificGroupStrategyContract.connect(owner).setPauser())
        .to.emit(specificGroupStrategyContract, "PauserSet")
        .withArgs(owner.address);
    });

    it("cannot be called by a non-owner", async () => {
      await expect(specificGroupStrategyContract.connect(nonManager).setPauser()).revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    describe("when the owner is changed", async () => {
      beforeEach(async () => {
        await specificGroupStrategyContract.connect(owner).transferOwnership(nonManager.address);
      });

      it("sets the pauser to the new owner", async () => {
        await specificGroupStrategyContract.connect(nonManager).setPauser();
        const newPauser = await specificGroupStrategyContract.pauser();
        expect(newPauser).to.eq(nonManager.address);
      });
    });
  });

  describe("#pause", () => {
    it("can be called by the pauser", async () => {
      await specificGroupStrategyContract.connect(pauser).pause();
      const isPaused = await specificGroupStrategyContract.isPaused();
      expect(isPaused).to.be.true;
    });

    it("emits a ContractPaused event", async () => {
      await expect(specificGroupStrategyContract.connect(pauser).pause()).to.emit(
        specificGroupStrategyContract,
        "ContractPaused"
      );
    });

    it("cannot be called by a random account", async () => {
      await expect(specificGroupStrategyContract.connect(nonManager).pause()).revertedWith(
        "OnlyPauser()"
      );
      const isPaused = await specificGroupStrategyContract.isPaused();
      expect(isPaused).to.be.false;
    });
  });

  describe("#unpause", () => {
    beforeEach(async () => {
      await specificGroupStrategyContract.connect(pauser).pause();
    });

    it("can be called by the pauser", async () => {
      await specificGroupStrategyContract.connect(pauser).unpause();
      const isPaused = await specificGroupStrategyContract.isPaused();
      expect(isPaused).to.be.false;
    });

    it("emits a ContractUnpaused event", async () => {
      await expect(specificGroupStrategyContract.connect(pauser).unpause()).to.emit(
        specificGroupStrategyContract,
        "ContractUnpaused"
      );
    });

    it("cannot be called by a random account", async () => {
      await expect(specificGroupStrategyContract.connect(nonManager).unpause()).revertedWith(
        "OnlyPauser()"
      );
      const isPaused = await specificGroupStrategyContract.isPaused();
      expect(isPaused).to.be.true;
    });
  });

  describe("when paused", () => {
    beforeEach(async () => {
      await specificGroupStrategyContract.connect(pauser).pause();
    });

    it("can't call rebalanceWhenHealthChanged", async () => {
      await expect(
        specificGroupStrategyContract.connect(nonManager).rebalanceWhenHealthChanged(ADDRESS_ZERO)
      ).revertedWith("Paused()");
    });

    it("can't call rebalanceOverflowedGroup", async () => {
      await expect(
        specificGroupStrategyContract.connect(nonManager).rebalanceOverflowedGroup(ADDRESS_ZERO)
      ).revertedWith("Paused()");
    });
  });
});
