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
  electMockValidatorGroupsAndUpdate,
  getDefaultGroups,
  getImpersonatedSigner,
  getSpecificGroups,
  mineToNextEpoch,
  prepareOverflow,
  randomSigner,
  rebalanceDefaultGroups,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
  resetNetwork,
  revokeElectionOnMockValidatorGroupsAndUpdate,
  updateGroupCeloBasedOnProtocolStCelo,
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
  let groupHealthContract: MockGroupHealth;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategyContract: MockDefaultStrategy;
  let nonVote: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;

  let election: ElectionWrapper;
  let lockedGold: LockedGoldWrapper;
  let validators: ValidatorsWrapper;
  let accountsWrapper: AccountsWrapper;

  let owner: SignerWithAddress;
  let nonOwner: SignerWithAddress;
  let someone: SignerWithAddress;
  let mockSlasher: SignerWithAddress;
  let depositor: SignerWithAddress;
  let depositor2: SignerWithAddress;
  let voter: SignerWithAddress;
  let groups: SignerWithAddress[];
  let groupAddresses: string[];
  let pauser: SignerWithAddress;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  before(async function () {
    try {
      this.timeout(100000);
      await resetNetwork();
      lockedGold = await hre.kit.contracts.getLockedGold();
      election = await hre.kit.contracts.getElection();
      validators = await hre.kit.contracts.getValidators();
      accountsWrapper = await hre.kit.contracts.getAccounts();

      await hre.deployments.fixture("FullTestManager");
      manager = await hre.ethers.getContract("Manager");
      groupHealthContract = await hre.ethers.getContract("MockGroupHealth");
      specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");
      defaultStrategyContract = await hre.ethers.getContract("MockDefaultStrategy");

      owner = await hre.ethers.getNamedSigner("owner");
      [nonOwner] = await randomSigner(parseUnits("100"));
      [someone] = await randomSigner(parseUnits("100"));
      [mockSlasher] = await randomSigner(parseUnits("100"));
      [depositor] = await randomSigner(parseUnits("500"));
      [depositor2] = await randomSigner(parseUnits("500"));
      [voter] = await randomSigner(parseUnits("10000000000"));
      [nonVote] = await randomSigner(parseUnits("100000"));
      [nonStakedCelo] = await randomSigner(parseUnits("100"));
      [nonAccount] = await randomSigner(parseUnits("100"));
      pauser = owner;

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

      await manager.connect(owner).setPauser();
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

  describe("#deposit()", () => {
    it("reverts when there are no active groups", async () => {
      await expect(manager.connect(depositor).deposit({ value: 100 })).revertedWith(
        "NoActiveGroups()"
      );
    });

    describe("when having active groups", () => {
      let originalTail: string;

      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
        [originalTail] = await defaultStrategyContract.getGroupsTail();
        await manager.connect(depositor).deposit({ value: 99 });
      });

      it("distributes votes to tail", async () => {
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([originalTail]);
        expect(votes).to.deep.equal([BigNumber.from("99")]);
      });

      it("should change the tail", async () => {
        const [newTail] = await defaultStrategyContract.getGroupsTail();
        expect(originalTail).not.eq(newTail);
      });

      it("should update head", async () => {
        const [newHead] = await defaultStrategyContract.getGroupsHead();
        expect(newHead).to.eq(originalTail);
      });

      describe("When another deposit is made", () => {
        let tailAfterFirstDeposit: string;
        beforeEach(async () => {
          [tailAfterFirstDeposit] = await defaultStrategyContract.getGroupsTail();
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should update tail accordingly", async () => {
          const [newTail] = await defaultStrategyContract.getGroupsTail();
          expect(originalTail).not.eq(newTail);
          expect(tailAfterFirstDeposit).not.eq(newTail);
        });

        it("should update head", async () => {
          const [newHead] = await defaultStrategyContract.getGroupsHead();
          expect(newHead).to.eq(tailAfterFirstDeposit);
        });
      });

      describe("when tail group is deactivated", () => {
        beforeEach(async () => {
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await defaultStrategyContract.connect(owner).connect(owner).deactivateGroup(tail);
        });

        it("distributes votes to new tail", async () => {
          const [currentTail] = await defaultStrategyContract.getGroupsTail();
          await manager.connect(depositor).deposit({ value: 100 });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([currentTail]);
          expect(votes).to.deep.equal([BigNumber.from("100")]);
        });
      });
    });

    describe("stCELO minting", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
      });

      describe("when there are no tokens in the system", () => {
        beforeEach(async () => {
          await account.setTotalCelo(0);
        });

        describe("When it mints CELO 1:1 with stCELO", () => {
          let tail: string;
          beforeEach(async () => {
            [tail] = await defaultStrategyContract.getGroupsTail();
            await manager.connect(depositor).deposit({ value: 100 });
          });

          it("should have correct stCELO balance", async () => {
            const stCelo = await stakedCelo.balanceOf(depositor.address);
            expect(stCelo).to.eq(100);
          });

          it("should have correct stCELO in defaultStrategy", async () => {
            const stCelo = await defaultStrategyContract.totalStCeloInStrategy();
            expect(stCelo).to.eq(100);
          });

          it("should have correct votes scheduled", async () => {
            const [votedGroups, votes] = await account.getLastScheduledVotes();
            expect(votedGroups).to.have.deep.members([tail]);
            expect(votes).to.have.deep.members([BigNumber.from(100)]);
          });
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

        describe("When it mints CELO 1:1 with stCELO", () => {
          let tail: string;
          beforeEach(async () => {
            [tail] = await defaultStrategyContract.getGroupsTail();
            await manager.connect(depositor).deposit({ value: 100 });
          });

          it("should have correct stCELO balance", async () => {
            const stCelo = await stakedCelo.balanceOf(depositor.address);
            expect(stCelo).to.eq(100);
          });

          it("should have correct stCELO in defaultStrategy", async () => {
            const stCelo = await defaultStrategyContract.totalStCeloInStrategy();
            expect(stCelo).to.eq(100);
          });

          it("should have correct votes scheduled", async () => {
            const [votedGroups, votes] = await account.getLastScheduledVotes();
            expect(votedGroups).to.have.deep.members([tail]);
            expect(votes).to.have.deep.members([BigNumber.from(100)]);
          });
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

        describe("When it calculates less stCELO than the input CELO", () => {
          let tail: string;
          beforeEach(async () => {
            [tail] = await defaultStrategyContract.getGroupsTail();
            await manager.connect(depositor).deposit({ value: 100 });
          });

          it("should have correct stCELO balance", async () => {
            const stCelo = await stakedCelo.balanceOf(depositor.address);
            expect(stCelo).to.eq(50);
          });

          it("should have correct stCELO in defaultStrategy", async () => {
            const stCelo = await defaultStrategyContract.totalStCeloInStrategy();
            expect(stCelo).to.eq(50);
          });

          it("should have correct votes scheduled", async () => {
            const [votedGroups, votes] = await account.getLastScheduledVotes();
            expect(votedGroups).to.have.deep.members([tail]);
            expect(votes).to.have.deep.members([BigNumber.from(100)]);
          });
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

        describe("When it calculates more stCELO than the input CELO", () => {
          let tail: string;
          beforeEach(async () => {
            [tail] = await defaultStrategyContract.getGroupsTail();
            await manager.connect(depositor).deposit({ value: 100 });
          });

          it("should have correct stCELO balance", async () => {
            const stCelo = await stakedCelo.balanceOf(depositor.address);
            expect(stCelo).to.eq(200);
          });

          it("should have correct stCELO in defaultStrategy", async () => {
            const stCelo = await defaultStrategyContract.totalStCeloInStrategy();
            expect(stCelo).to.eq(200);
          });

          it("should have correct votes scheduled", async () => {
            const [votedGroups, votes] = await account.getLastScheduledVotes();
            expect(votedGroups).to.have.deep.members([tail]);
            expect(votes).to.have.deep.members([BigNumber.from(100)]);
          });
        });

        it("calculates more stCELO than the input CELO for a different amount", async () => {
          await manager.connect(depositor).deposit({ value: 10 });
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(20);
        });
      });
    });

    describe("when groups are close to their voting limit", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      const secondGroupCapacity = parseUnits("99.25");

      beforeEach(async () => {
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses
        );
      });

      it("Deposit to only one group if within capacity", async () => {
        await manager.connect(depositor).deposit({ value: parseUnits("30") });

        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([groupAddresses[0]]);

        expect(votes).to.deep.equal([parseUnits("30")]);
      });

      it("Deposit to 2 groups when over capacity of first", async () => {
        await manager.connect(depositor).deposit({ value: parseUnits("50") });

        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([groupAddresses[0], groupAddresses[1]]);

        expect(votes).to.deep.equal([firstGroupCapacity, parseUnits("50").sub(firstGroupCapacity)]);
      });

      it("Deposit to 3 groups when over capacity of first and second", async () => {
        await manager.connect(depositor).deposit({ value: parseUnits("150") });

        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.have.deep.members([
          groupAddresses[0],
          groupAddresses[1],
          groupAddresses[2],
        ]);

        expect(votes).to.have.deep.members([
          firstGroupCapacity,
          secondGroupCapacity,
          parseUnits("150").sub(firstGroupCapacity).sub(secondGroupCapacity),
        ]);
      });

      it("reverts when the deposit total would push all groups over their capacity", async () => {
        await expect(manager.connect(depositor).deposit({ value: parseUnits("350") })).revertedWith(
          "NotAbleToDistributeVotes()"
        );
      });

      describe("when there are scheduled votes for the groups", () => {
        const firstGroupScheduled = parseUnits("30");
        const secondGroupScheduled = parseUnits("50");
        const thirdGroupScheduled = parseUnits("170");

        beforeEach(async () => {
          await account.setCeloForGroup(groupAddresses[0], firstGroupScheduled);
          await account.setCeloForGroup(groupAddresses[1], secondGroupScheduled);
          await account.setCeloForGroup(groupAddresses[2], thirdGroupScheduled);
        });

        it("Deposit to only one group if within capacity", async () => {
          await manager.connect(depositor).deposit({ value: parseUnits("5") });

          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[0]]);

          expect(votes).to.deep.equal([parseUnits("5")]);
        });

        it("Deposit to 2 groups when over capacity of first", async () => {
          await manager.connect(depositor).deposit({ value: parseUnits("50") });

          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[0], groupAddresses[1]]);

          expect(votes).to.deep.equal([
            firstGroupCapacity.sub(firstGroupScheduled),
            parseUnits("50").sub(firstGroupCapacity.sub(firstGroupScheduled)),
          ]);
        });

        it("Deposit to 3 groups when over capacity of first and second", async () => {
          await manager.connect(depositor).deposit({ value: parseUnits("80") });

          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([
            groupAddresses[0],
            groupAddresses[1],
            groupAddresses[2],
          ]);

          expect(votes).to.deep.equal([
            firstGroupCapacity.sub(firstGroupScheduled),
            secondGroupCapacity.sub(secondGroupScheduled),
            parseUnits("80")
              .sub(firstGroupCapacity.sub(firstGroupScheduled))
              .sub(secondGroupCapacity.sub(secondGroupScheduled)),
          ]);
        });

        it("reverts when the deposit total would push all groups over their capacity", async () => {
          await expect(
            manager.connect(depositor).deposit({ value: parseUnits("100") })
          ).revertedWith("NotAbleToDistributeVotes()");
        });
      });

      describe("When voting for specific strategy with overflow", () => {
        const depositAmount = parseUnits("100");

        beforeEach(async () => {
          await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        });

        describe("When different ratios of CELO vs stCELO", () => {
          describe("When 1:1", () => {
            beforeEach(async () => {
              await manager.connect(depositor).deposit({ value: depositAmount });
            });

            it("should overflow to default strategy", async () => {
              const [stCeloInStrategy, overflowAmount] =
                await specificGroupStrategyContract.getStCeloInGroup(groupAddresses[0]);
              expect(stCeloInStrategy).to.eq(depositAmount);
              expect(overflowAmount).to.eq(depositAmount.sub(firstGroupCapacity));
            });

            it("should schedule the overflow to default strategy", async () => {
              const [votedGroups, votes] = await account.getLastScheduledVotes();
              expect(votedGroups).to.have.deep.members([groupAddresses[0], groupAddresses[1]]);

              expect(votes).to.have.deep.members([
                firstGroupCapacity,
                depositAmount.sub(firstGroupCapacity),
              ]);
            });

            it("should not change total stCelo of default strategy", async () => {
              const currentDefaultStrategyStCeloBalance =
                await defaultStrategyContract.totalStCeloInStrategy();
              expect(currentDefaultStrategyStCeloBalance).to.deep.eq(
                depositAmount.sub(firstGroupCapacity)
              );
            });
          });

          describe("When there is more CELO than stCELO", () => {
            let firstGroupCapacityInStCelo: BigNumber;
            beforeEach(async () => {
              await account.setTotalCelo(parseUnits("200"));
              await stakedCelo.mint(someone.address, parseUnits("100"));
              firstGroupCapacityInStCelo = await manager.toStakedCelo(firstGroupCapacity);
              await manager.connect(depositor).deposit({ value: depositAmount });
            });

            it("should overflow to default strategy", async () => {
              const [stCeloInStrategy, overflowAmount] =
                await specificGroupStrategyContract.getStCeloInGroup(groupAddresses[0]);
              expect(stCeloInStrategy).to.eq(depositAmount.div(2));
              expect(overflowAmount).to.eq(depositAmount.div(2).sub(firstGroupCapacityInStCelo));
            });

            it("should schedule the overflow to default strategy", async () => {
              const [votedGroups, votes] = await account.getLastScheduledVotes();
              expect(votedGroups).to.have.deep.members([groupAddresses[0], groupAddresses[1]]);

              expect(votes).to.have.deep.members([
                firstGroupCapacity,
                depositAmount.sub(firstGroupCapacity),
              ]);
            });

            it("should not change total stCelo of default strategy", async () => {
              const currentDefaultStrategyStCeloBalance =
                await defaultStrategyContract.totalStCeloInStrategy();
              expect(currentDefaultStrategyStCeloBalance).to.deep.eq(
                depositAmount.div(2).sub(firstGroupCapacityInStCelo)
              );
            });
          });

          describe("When there is less CELO than stCELO", () => {
            let firstGroupCapacityInStCelo: BigNumber;
            beforeEach(async () => {
              await account.setTotalCelo(parseUnits("50"));
              await stakedCelo.mint(someone.address, parseUnits("100"));
              firstGroupCapacityInStCelo = await manager.toStakedCelo(firstGroupCapacity);
              await manager.connect(depositor).deposit({ value: depositAmount });
            });

            it("should overflow to default strategy", async () => {
              const [stCeloInStrategy, overflowAmount] =
                await specificGroupStrategyContract.getStCeloInGroup(groupAddresses[0]);
              expect(stCeloInStrategy).to.eq(depositAmount.mul(2));
              expect(overflowAmount).to.eq(depositAmount.mul(2).sub(firstGroupCapacityInStCelo));
            });

            it("should schedule the overflow to default strategy", async () => {
              const [votedGroups, votes] = await account.getLastScheduledVotes();
              expect(votedGroups).to.have.deep.members([groupAddresses[0], groupAddresses[1]]);

              expect(votes).to.have.deep.members([
                firstGroupCapacity,
                depositAmount.sub(firstGroupCapacity),
              ]);
            });

            it("should not change total stCelo of default strategy", async () => {
              const currentDefaultStrategyStCeloBalance =
                await defaultStrategyContract.totalStCeloInStrategy();
              expect(currentDefaultStrategyStCeloBalance).to.deep.eq(
                depositAmount.mul(2).sub(firstGroupCapacityInStCelo)
              );
            });
          });
        });
      });
    });

    describe("When voted for specific strategy", () => {
      beforeEach(async () => {
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor).deposit({ value: 100 });
      });

      it("should add group to voted strategies", async () => {
        const activeGroups = await getDefaultGroups(defaultStrategyContract);
        const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
        expect(activeGroups.length).to.eq(0);
        expect(specificStrategies.length).to.eq(1);
        expect(specificStrategies[0]).to.eq(groupAddresses[0]);
      });

      it("should schedule votes for specific group strategy", async () => {
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
      let originalTail: string;
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }

        await manager.connect(depositor).changeStrategy(groupAddresses[4]);
        await account.setCeloForGroup(groupAddresses[4], 100);
        await updateGroupSlashingMultiplier(
          registryContract,
          lockedGoldContract,
          validatorsContract,
          groups[4],
          mockSlasher
        );
        await mineToNextEpoch(hre.web3);
        await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          groups[4].address,
        ]);

        [originalTail] = await defaultStrategyContract.getGroupsTail();
        await manager.connect(depositor).deposit({ value: 100 });
      });

      it("should add group to voted strategies", async () => {
        const activeGroups = await getDefaultGroups(defaultStrategyContract);
        const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
        expect(activeGroups).to.have.deep.members(groupAddresses.slice(0, 3));
        expect(specificStrategies).to.deep.eq([groups[4].address]);
      });

      it("should schedule votes for default groups", async () => {
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([originalTail]);
        expect(votes).to.deep.equal([BigNumber.from("100")]);
      });

      it("should set correct stCelo and UnhealthyStCelo in group", async () => {
        const [total, overflow, unhealthy] = await specificGroupStrategyContract.getStCeloInGroup(
          groups[4].address
        );
        expect(total).to.deep.equal(BigNumber.from("100"));
        expect(overflow).to.deep.equal(BigNumber.from("0"));
        expect(unhealthy).to.deep.equal(BigNumber.from("100"));
      });

      it("should not schedule transfers to default strategy when no balance for specific strategy", async () => {
        await specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[4]);
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

    describe("When voted for deactivated group", () => {
      const depositedValue = 1000;
      let specificGroupStrategyAddress: string;

      describe("Block strategy - group other than active", () => {
        beforeEach(async () => {
          for (let i = 0; i < 2; i++) {
            const [head] = await defaultStrategyContract.getGroupsHead();
            await defaultStrategyContract
              .connect(owner)
              .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            await account.setCeloForGroup(groupAddresses[i], 100);
          }
          specificGroupStrategyAddress = groupAddresses[2];

          await manager.changeStrategy(specificGroupStrategyAddress);
          await manager.deposit({ value: depositedValue });
          await account.setCeloForGroup(specificGroupStrategyAddress, depositedValue);
          await specificGroupStrategyContract
            .connect(owner)
            .blockGroup(specificGroupStrategyAddress);
        });

        it("should schedule votes for default strategy", async () => {
          const secondDepositedValue = 1000;
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await manager.deposit({ value: secondDepositedValue });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.have.deep.members([tail]);
          expect(votes).to.have.deep.members([BigNumber.from(secondDepositedValue)]);
        });
      });

      describe("Block strategy - group one of active", () => {
        beforeEach(async () => {
          for (let i = 0; i < 3; i++) {
            const [head] = await defaultStrategyContract.getGroupsHead();
            await defaultStrategyContract
              .connect(owner)
              .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            await account.setCeloForGroup(groupAddresses[i], 100);
          }
          specificGroupStrategyAddress = groupAddresses[0];

          await manager.changeStrategy(specificGroupStrategyAddress);
          await manager.deposit({ value: depositedValue });
          await account.setCeloForGroup(specificGroupStrategyAddress, depositedValue);
          await specificGroupStrategyContract
            .connect(owner)
            .blockGroup(specificGroupStrategyAddress);
        });

        it("should schedule votes for default strategy", async () => {
          const secondDepositedValue = 1000;
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await manager.deposit({ value: secondDepositedValue });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.have.deep.members([tail]);
          expect(votes).to.have.deep.members([BigNumber.from(secondDepositedValue)]);
        });
      });
    });

    describe("When we have 2 active validator groups", () => {
      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }
      });

      describe("When voted for specific validator group which is not in active groups", () => {
        beforeEach(async () => {
          await manager.connect(depositor).changeStrategy(groupAddresses[2]);
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should add group to voted strategies", async () => {
          const activeGroups = await getDefaultGroups(defaultStrategyContract);
          const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(specificStrategies).to.deep.eq([groupAddresses[2]]);
        });

        it("should schedule votes for specific group strategy", async () => {
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([groupAddresses[2]]);
          expect(votes).to.deep.equal([BigNumber.from("100")]);
        });

        it("should mint 1:1 stCelo", async () => {
          const stCelo = await stakedCelo.balanceOf(depositor.address);
          expect(stCelo).to.eq(100);
        });
      });

      describe("When voted for specific validator group which is in active groups", () => {
        let specificGroupStrategyAddress: string;
        beforeEach(async () => {
          specificGroupStrategyAddress = groupAddresses[0];
          await manager.connect(depositor).changeStrategy(specificGroupStrategyAddress);
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should add group to voted strategies", async () => {
          const activeGroups = await getDefaultGroups(defaultStrategyContract);
          const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(specificStrategies).to.deep.eq([specificGroupStrategyAddress]);
        });

        it("should schedule votes for specific group strategy", async () => {
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

    describe("When depositing originally healthy overflowing specific group that became unhealthy", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      const depositOverCapacity = parseUnits("10");
      let deposit: BigNumber;
      let specificGroupAddress: string;

      beforeEach(async () => {
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses.slice(0, 3),
          true
        );
        deposit = firstGroupCapacity.add(depositOverCapacity);
        specificGroupAddress = groupAddresses[0];
        await manager.connect(depositor).changeStrategy(specificGroupAddress);
        await manager.connect(depositor).deposit({ value: deposit });

        await revokeElectionOnMockValidatorGroupsAndUpdate(
          validators,
          accountsWrapper,
          groupHealthContract,
          [specificGroupAddress]
        );
      });

      describe("When different ratios of CELO vs stCELO", () => {
        describe("When 1:1", () => {
          let nextToTail: string;
          const deposit2 = parseUnits("5");
          beforeEach(async () => {
            await manager.connect(depositor).deposit({ value: deposit2 });
            [, nextToTail] = await defaultStrategyContract.getGroupsTail();
          });

          it("should schedule transfers correctly", async () => {
            const [votedGroups, votes] = await account.getLastScheduledVotes();
            expect(votedGroups).to.deep.equal([nextToTail]);
            expect(votes).to.deep.equal([deposit2]);
          });

          it("should have stCelo in strategy", async () => {
            const [total, overflow, unhealthy] =
              await specificGroupStrategyContract.getStCeloInGroup(specificGroupAddress);
            expect(total).to.deep.eq(deposit2.add(deposit));
            expect(overflow).to.deep.eq(depositOverCapacity);
            expect(unhealthy).to.deep.eq(deposit2);
            // there is only deposit2 since rebalanceWhenHealthChanged was not called
          });
        });

        describe("When there is more CELO than stCELO", () => {
          let nextToTail: string;
          const deposit2 = parseUnits("5");
          let deposit2InStCelo: BigNumber;
          beforeEach(async () => {
            await account.setTotalCelo(deposit.mul(2));
            deposit2InStCelo = await manager.toStakedCelo(deposit2);
            await manager.connect(depositor).deposit({ value: deposit2 });
            [, nextToTail] = await defaultStrategyContract.getGroupsTail();
          });

          it("should schedule transfers correctly", async () => {
            const [votedGroups, votes] = await account.getLastScheduledVotes();
            expect(votedGroups).to.deep.equal([nextToTail]);
            expect(votes).to.deep.equal([deposit2]);
          });

          it("should have stCelo in strategy", async () => {
            const [total, overflow, unhealthy] =
              await specificGroupStrategyContract.getStCeloInGroup(specificGroupAddress);
            expect(total).to.deep.eq(deposit.add(deposit2InStCelo));
            expect(overflow).to.deep.eq(depositOverCapacity);
            expect(unhealthy).to.deep.eq(deposit2InStCelo);
          });
        });
      });
    });
  });

  describe("#withdraw()", () => {
    it("reverts when there are no active or deactivated groups", async () => {
      await expect(manager.connect(depositor).withdraw(100)).revertedWith("NoActiveGroups()");
    });

    describe("when groups are activated", () => {
      let originalHead: string;

      beforeEach(async () => {
        let nextGroup = ADDRESS_ZERO;
        for (let i = 0; i < 3; i++) {
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], nextGroup, tail);
          nextGroup = groupAddresses[i];
          await account.setCeloForGroup(groupAddresses[i], 100);
          await manager.connect(depositor2).deposit({ value: 100 });
        }

        [originalHead] = await defaultStrategyContract.getGroupsHead();
      });

      describe("When withdrawn from head", () => {
        const withdrawn1 = 77;
        beforeEach(async () => {
          await manager.connect(depositor2).withdraw(withdrawn1);
        });

        it("should change current head", async () => {
          const [currentHead] = await defaultStrategyContract.getGroupsHead();
          expect(currentHead).not.eq(originalHead);
        });

        it("should update current tail", async () => {
          const [currentTail] = await defaultStrategyContract.getGroupsTail();
          expect(currentTail).to.eq(originalHead);
        });

        it("should update totalStCELO in Default strategy", async () => {
          const totalStCeloInDefault = (
            await defaultStrategyContract.totalStCeloInStrategy()
          ).toNumber();
          expect(totalStCeloInDefault).to.eq(223);
        });

        describe("When withdrawn again", () => {
          const withdrawn2 = 77;
          let headAfterWithdrawal1: string;
          let tailAfterWithdrawal1: string;
          beforeEach(async () => {
            headAfterWithdrawal1 = (await defaultStrategyContract.getGroupsHead())[0];
            tailAfterWithdrawal1 = (await defaultStrategyContract.getGroupsTail())[0];
            await manager.connect(depositor2).withdraw(withdrawn2);
          });

          it("should change current head", async () => {
            const [currentHead] = await defaultStrategyContract.getGroupsHead();
            expect(currentHead).not.eq(headAfterWithdrawal1);
          });

          it("should update current tail", async () => {
            const [currentTail] = await defaultStrategyContract.getGroupsTail();
            expect(currentTail).to.eq(tailAfterWithdrawal1);
          });

          it("should update totalStCELO in Default strategy", async () => {
            const totalStCeloInDefault = (
              await defaultStrategyContract.totalStCeloInStrategy()
            ).toNumber();
            expect(totalStCeloInDefault).to.eq(146);
          });
        });
      });

      describe("When withdrawing from multiple groups", () => {
        let originalHead: string;
        let originalPreviousHead: string;

        beforeEach(async () => {
          [originalHead] = await defaultStrategyContract.getGroupsHead();
          [originalPreviousHead] = await defaultStrategyContract.getGroupPreviousAndNext(
            originalHead
          );
        });

        it("should schedule transfer from 2 groups", async () => {
          await manager.connect(depositor2).withdraw(150);
          const [votedGroups, votes] = await account.getLastScheduledWithdrawals();
          expect(votedGroups).to.have.deep.members([originalHead, originalPreviousHead]);
          expect(votes).to.have.deep.members([BigNumber.from("100"), BigNumber.from("50")]);
        });

        it("should schedule transfer from 3 groups", async () => {
          await manager.connect(depositor2).withdraw(300);
          const [votedGroups, votes] = await account.getLastScheduledWithdrawals();
          expect(votedGroups).to.have.deep.members(groupAddresses.slice(0, 3));
          expect(votes).to.have.deep.members([
            BigNumber.from("100"),
            BigNumber.from("100"),
            BigNumber.from("100"),
          ]);
        });
      });
    });

    describe("stCELO burning", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], 100);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(groupAddresses[i], 100);
        }
        await manager.connect(depositor).deposit({ value: 100 });
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

        it("burns the stCELO for a different amount", async () => {
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

        it("burns the stCELO 2", async () => {
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

    describe("When voted for specific validator group - no active groups", () => {
      beforeEach(async () => {
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor).deposit({ value: 100 });
        await account.setCeloForGroup(groupAddresses[0], 100);
      });

      it("should withdraw less than originally deposited from specific group strategy", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[0]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
      });

      it("should withdraw same amount as originally deposited from specific group strategy", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[0]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("100")]);
      });

      it("should revert when withdraw more amount than originally deposited from specific group strategy", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `CantWithdrawAccordingToStrategy("${groupAddresses[0]}")`
        );
      });
    });

    describe("When there are other active groups besides specific validator group - voted is different from active", () => {
      const withdrawals = [40, 50];
      const specificGroupStrategyWithdrawal = 100;
      let specificGroupStrategy: SignerWithAddress;

      beforeEach(async () => {
        specificGroupStrategy = groups[2];
        let nextGroup = ADDRESS_ZERO;
        for (let i = 0; i < 2; i++) {
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
          nextGroup = groupAddresses[i];
          await manager.connect(depositor2).deposit({ value: withdrawals[i] });
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        await account.setCeloForGroup(
          specificGroupStrategy.address,
          specificGroupStrategyWithdrawal
        );

        await manager.connect(depositor).changeStrategy(specificGroupStrategy.address);
        await manager.connect(depositor).deposit({ value: specificGroupStrategyWithdrawal });
      });

      it("added group to voted strategies", async () => {
        const activeGroups = await getDefaultGroups(defaultStrategyContract);
        const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
        expect(activeGroups).to.have.deep.members([groupAddresses[0], groupAddresses[1]]);
        expect(specificStrategies).to.deep.eq([specificGroupStrategy.address]);
      });

      it("should withdraw less than originally deposited from specific group strategy", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([specificGroupStrategy.address]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
        const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
        expect(specificStrategies).to.deep.eq([specificGroupStrategy.address]);
      });

      it("should withdraw same amount as originally deposited from specific group strategy", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect([specificGroupStrategy.address]).to.deep.equal(withdrawnGroups);
        expect([BigNumber.from("100")]).to.deep.equal(withdrawals);
        const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
        expect([specificGroupStrategy.address]).to.deep.eq(specificStrategies);
      });

      it("should withdraw same amount as originally deposited from active groups after strategy is blocked", async () => {
        await specificGroupStrategyContract
          .connect(owner)
          .blockGroup(specificGroupStrategy.address);
        await specificGroupStrategyContract.rebalanceWhenHealthChanged(
          specificGroupStrategy.address
        );

        const [groupHead] = await defaultStrategyContract.getGroupsHead();
        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, groupWithdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupHead]);
        expect(groupWithdrawals).to.deep.equal([BigNumber.from("100")]);
        const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
        expect(specificStrategies).to.deep.eq([specificGroupStrategy.address]);
      });

      it("should revert when withdraw more amount than originally deposited from specific group strategy", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `CantWithdrawAccordingToStrategy("${specificGroupStrategy.address}")`
        );
      });

      describe("When strategy blocked", () => {
        beforeEach(async () => {
          await specificGroupStrategyContract
            .connect(owner)
            .blockGroup(specificGroupStrategy.address);
          await specificGroupStrategyContract.rebalanceWhenHealthChanged(
            specificGroupStrategy.address
          );
        });

        it('should withdraw correctly after "rebalance"', async () => {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await updateGroupCeloBasedOnProtocolStCelo(
            defaultStrategyContract,
            specificGroupStrategyContract,
            account,
            manager
          );
          await manager.connect(depositor).withdraw(specificGroupStrategyWithdrawal);

          const [withdrawnGroups, groupWithdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([head]);
          expect(groupWithdrawals).to.deep.equal([BigNumber.from(specificGroupStrategyWithdrawal)]);

          const [stCelo, overflow, unhealthy] =
            await specificGroupStrategyContract.getStCeloInGroup(specificGroupStrategy.address);
          expect(stCelo).to.deep.eq(BigNumber.from("0"));
          expect(overflow).to.deep.eq(BigNumber.from("0"));
          expect(unhealthy).to.deep.eq(BigNumber.from("0"));
        });

        it('should withdraw correctly after "rebalance" when withdrawing less than deposited', async () => {
          const toWithdraw = specificGroupStrategyWithdrawal - 10;

          const [head] = await defaultStrategyContract.getGroupsHead();
          await updateGroupCeloBasedOnProtocolStCelo(
            defaultStrategyContract,
            specificGroupStrategyContract,
            account,
            manager
          );
          await manager.connect(depositor).withdraw(toWithdraw);

          const [withdrawnGroups, groupWithdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([head]);
          expect(groupWithdrawals).to.deep.equal([BigNumber.from(toWithdraw)]);

          const [stCelo, overflow, unhealthy] =
            await specificGroupStrategyContract.getStCeloInGroup(specificGroupStrategy.address);
          expect(stCelo).to.deep.eq(BigNumber.from("10"));
          expect(overflow).to.deep.eq(BigNumber.from("0"));
          expect(unhealthy).to.deep.eq(BigNumber.from("10"));
        });
      });
    });

    describe("When there are other active groups besides specific validator group - voted is one of the active groups", () => {
      const withdrawals = [40, 50];
      const specificGroupStrategyWithdrawal = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        await account.setCeloForGroup(
          groupAddresses[1],
          withdrawals[1] + specificGroupStrategyWithdrawal
        );

        await manager.connect(depositor).changeStrategy(groupAddresses[1]);
        await manager.connect(depositor).deposit({ value: specificGroupStrategyWithdrawal });
      });

      it("should withdraw less than originally deposited from specific group strategy", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[1]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
      });

      it("should withdraw same amount as originally deposited from specific group strategy", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupAddresses[1]]);
        expect(withdrawals).to.deep.equal([BigNumber.from("100")]);
      });

      it("should revert when withdraw more amount than originally deposited from specific group strategy", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `CantWithdrawAccordingToStrategy("${groupAddresses[1]}")`
        );
      });
    });

    describe("when groups are close to their voting limit", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      const depositAmount = parseUnits("50");
      let originalDefaultHead: string;
      let previousOfHead: string;
      let originalOverflow: BigNumber;

      beforeEach(async () => {
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses
        );

        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor).deposit({ value: depositAmount });
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await rebalanceDefaultGroups(defaultStrategyContract as any);
        [originalDefaultHead] = await defaultStrategyContract.getGroupsHead();
        [previousOfHead] = await defaultStrategyContract.getGroupPreviousAndNext(
          originalDefaultHead
        );
        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
        originalOverflow = await specificGroupStrategyContract.totalStCeloOverflow();
      });

      describe("When withdrawing amount only from overflow", () => {
        const toWithdraw = parseUnits("5");

        beforeEach(async () => {
          await manager.connect(depositor).withdraw(toWithdraw);
        });

        it("should remove overflow from default strategy", async () => {
          const [stCeloInStrategy, overflowAmount] =
            await specificGroupStrategyContract.getStCeloInGroup(groupAddresses[0]);
          expect(stCeloInStrategy).to.eq(depositAmount.sub(toWithdraw));
          expect(overflowAmount).to.eq(depositAmount.sub(firstGroupCapacity).sub(toWithdraw));
        });

        it("should schedule withdraw from default strategy only", async () => {
          const [groups, votes] = await account.getLastScheduledWithdrawals();

          expect(groups).to.have.deep.members([previousOfHead, originalDefaultHead]);
          expect(votes).to.have.deep.members([
            originalOverflow.div(3),
            toWithdraw.sub(originalOverflow.div(3)),
          ]);
        });

        it("should add overflow to default strategy stCelo balance", async () => {
          const currentDefaultStrategyStCeloBalance =
            await defaultStrategyContract.totalStCeloInStrategy();
          const [, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
            groupAddresses[0]
          );
          expect(currentDefaultStrategyStCeloBalance).to.deep.eq(overflow);
        });
      });

      describe("When withdrawing amount over overflow", () => {
        const toWithdraw = parseUnits("20");

        describe("When different ratio of CELO vs stCELO", () => {
          describe("When 1:1", () => {
            beforeEach(async () => {
              await manager.connect(depositor).withdraw(toWithdraw);
            });

            it("should remove overflow from default strategy", async () => {
              const [stCeloInStrategy, overflowAmount] =
                await specificGroupStrategyContract.getStCeloInGroup(groupAddresses[0]);
              expect(stCeloInStrategy).to.eq(depositAmount.sub(toWithdraw));
              expect(overflowAmount).to.eq(0);
            });

            it("should schedule withdraw from default and specific strategy", async () => {
              const [groups, votes] = await account.getLastScheduledWithdrawals();

              const originalOverflow = depositAmount.sub(firstGroupCapacity);
              expect(groups).to.have.deep.members([
                groupAddresses[0],
                groupAddresses[1],
                groupAddresses[2],
                groupAddresses[0],
              ]);
              expect(votes).to.have.deep.members([
                originalOverflow.div(3),
                originalOverflow.div(3),
                originalOverflow.div(3),
                toWithdraw.sub(originalOverflow),
              ]);
            });

            it("should add overflow to default strategy stCelo balance", async () => {
              const currentDefaultStrategyStCeloBalance =
                await defaultStrategyContract.totalStCeloInStrategy();
              const [, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
                groupAddresses[0]
              );
              expect(currentDefaultStrategyStCeloBalance).to.deep.eq(overflow);
            });
          });

          describe("When there is more CELO than stCELO", () => {
            beforeEach(async () => {
              await account.setTotalCelo(depositAmount.mul(2));
              await updateGroupCeloBasedOnProtocolStCelo(
                defaultStrategyContract,
                specificGroupStrategyContract,
                account,
                manager
              );
              await manager.connect(depositor).withdraw(toWithdraw);
            });

            it("should remove overflow from default strategy", async () => {
              const [stCeloInStrategy, overflowAmount] =
                await specificGroupStrategyContract.getStCeloInGroup(groupAddresses[0]);
              expect(stCeloInStrategy).to.eq(depositAmount.sub(toWithdraw));
              expect(overflowAmount).to.eq(0);
            });

            it("should schedule withdraw from default and specific strategy", async () => {
              const [groups, votes] = await account.getLastScheduledWithdrawals();

              const originalOverflow = depositAmount.sub(firstGroupCapacity);
              expect(groups).to.have.deep.members([
                groupAddresses[0],
                groupAddresses[1],
                groupAddresses[2],
                groupAddresses[0],
              ]);
              expect(votes).to.have.deep.members([
                originalOverflow.div(3).mul(2),
                originalOverflow.div(3).mul(2),
                originalOverflow.div(3).mul(2),
                toWithdraw.sub(originalOverflow).mul(2),
              ]);
            });

            it("should add overflow to default strategy stCelo balance", async () => {
              const currentDefaultStrategyStCeloBalance =
                await defaultStrategyContract.totalStCeloInStrategy();
              const [, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
                groupAddresses[0]
              );
              expect(currentDefaultStrategyStCeloBalance).to.deep.eq(overflow);
            });
          });

          describe("When there is less CELO than stCELO", () => {
            beforeEach(async () => {
              await account.setTotalCelo(depositAmount.div(2));
              await manager.connect(depositor).withdraw(toWithdraw);
            });

            it("should remove overflow from default strategy", async () => {
              const [stCeloInStrategy, overflowAmount] =
                await specificGroupStrategyContract.getStCeloInGroup(groupAddresses[0]);
              expect(stCeloInStrategy).to.eq(depositAmount.sub(toWithdraw));
              expect(overflowAmount).to.eq(0);
            });

            it("should schedule withdraw from default and specific strategy", async () => {
              const [groups, votes] = await account.getLastScheduledWithdrawals();

              const originalOverflow = depositAmount.sub(firstGroupCapacity);
              expect(groups).to.have.deep.members([
                groupAddresses[0],
                groupAddresses[1],
                groupAddresses[2],
                groupAddresses[0],
              ]);
              expect(votes).to.have.deep.members([
                originalOverflow.div(3).div(2),
                originalOverflow.div(3).div(2),
                originalOverflow.div(3).div(2),
                toWithdraw.sub(originalOverflow).div(2),
              ]);
            });

            it("should add overflow to default strategy stCelo balance", async () => {
              const currentDefaultStrategyStCeloBalance =
                await defaultStrategyContract.totalStCeloInStrategy();
              const [, overflow] = await specificGroupStrategyContract.getStCeloInGroup(
                groupAddresses[0]
              );
              expect(currentDefaultStrategyStCeloBalance).to.deep.eq(overflow);
            });
          });
        });
      });
    });

    describe("When withdrawing from originally healthy overflowing group that became unhealthy", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      const depositOverCapacity = parseUnits("10");
      let deposit: BigNumber;
      let specificGroupAddress: string;

      beforeEach(async () => {
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses.slice(0, 3),
          true
        );
        deposit = firstGroupCapacity.add(depositOverCapacity);
        specificGroupAddress = groupAddresses[0];
        await manager.connect(depositor).changeStrategy(specificGroupAddress);
        await manager.connect(depositor).deposit({ value: deposit });

        await revokeElectionOnMockValidatorGroupsAndUpdate(
          validators,
          accountsWrapper,
          groupHealthContract,
          [specificGroupAddress]
        );
      });

      describe("When depositing to unhealthy specific group", () => {
        let nextToTail: string;
        const deposit2 = parseUnits("5");
        beforeEach(async () => {
          await manager.connect(depositor).deposit({ value: deposit2 });
          [, nextToTail] = await defaultStrategyContract.getGroupsTail();
        });

        it("should schedule transfers correctly", async () => {
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect(votedGroups).to.deep.equal([nextToTail]);
          expect(votes).to.deep.equal([deposit2]);
        });

        it("should have stCelo in strategy", async () => {
          const [total, overflow, unhealthy] = await specificGroupStrategyContract.getStCeloInGroup(
            specificGroupAddress
          );
          expect(total).to.deep.eq(deposit2.add(deposit));
          expect(overflow).to.deep.eq(depositOverCapacity);
          expect(unhealthy).to.deep.eq(deposit2);
          // there is only deposit2 since rebalanceWhenHealthChanged was not called
        });

        describe("When withdrawing from unhealthy overflowed group", () => {
          describe("When different ratio of CELO vs stCELO", () => {
            describe("When 1:1", () => {
              const withdraw = parseUnits("14");
              let head: string;
              let perviousToHead: string;
              beforeEach(async () => {
                await updateGroupCeloBasedOnProtocolStCelo(
                  defaultStrategyContract,
                  specificGroupStrategyContract,
                  account,
                  manager
                );
                [head, perviousToHead] = await defaultStrategyContract.getGroupsHead();
                await manager.connect(depositor).withdraw(withdraw);
              });

              it("should have stCelo in strategy", async () => {
                const [total, overflow, unhealthy] =
                  await specificGroupStrategyContract.getStCeloInGroup(specificGroupAddress);
                expect(total).to.deep.eq(deposit2.add(deposit).sub(withdraw));
                expect(overflow).to.deep.eq(BigNumber.from(0));
                expect(unhealthy).to.deep.eq(parseUnits("1"));
              });

              it("should schedule withdrawal from default strategy", async () => {
                const [votedGroups, votes] = await account.getLastScheduledWithdrawals();
                expect(votedGroups).to.have.deep.members([head, perviousToHead]);
                expect(votes[0].add(votes[1])).to.deep.eq(withdraw);
              });
            });

            describe("When less CELO than stCELO", () => {
              const withdraw = parseUnits("14");
              let head: string;
              let perviousToHead: string;
              beforeEach(async () => {
                await account.setTotalCelo(deposit.add(deposit2).div(2));
                await updateGroupCeloBasedOnProtocolStCelo(
                  defaultStrategyContract,
                  specificGroupStrategyContract,
                  account,
                  manager
                );

                await updateGroupCeloBasedOnProtocolStCelo(
                  defaultStrategyContract,
                  specificGroupStrategyContract,
                  account,
                  manager
                );
                [head, perviousToHead] = await defaultStrategyContract.getGroupsHead();
                await manager.connect(depositor).withdraw(withdraw);
              });

              it("should have stCelo in strategy", async () => {
                const [total, overflow, unhealthy] =
                  await specificGroupStrategyContract.getStCeloInGroup(specificGroupAddress);
                expect(total).to.deep.eq(deposit2.add(deposit).sub(withdraw));
                expect(overflow).to.deep.eq(BigNumber.from(0));
                expect(unhealthy).to.deep.eq(parseUnits("1"));
              });

              it("should schedule withdrawal from default strategy", async () => {
                const [votedGroups, votes] = await account.getLastScheduledWithdrawals();
                expect(votedGroups).to.have.deep.members([head, perviousToHead]);
                expect(votes[0].add(votes[1])).to.deep.eq(withdraw.div(2));
              });
            });
          });
        });
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
          .setDependencies(
            ADDRESS_ZERO,
            nonAccount.address,
            nonVote.address,
            nonVote.address,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero account address", async () => {
      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(
            nonStakedCelo.address,
            ADDRESS_ZERO,
            nonVote.address,
            nonVote.address,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero vote address", async () => {
      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(
            nonStakedCelo.address,
            nonAccount.address,
            ADDRESS_ZERO,
            nonVote.address,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero groupHealth address", async () => {
      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(
            nonStakedCelo.address,
            nonAccount.address,
            nonVote.address,
            ADDRESS_ZERO,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero specific group strategy address", async () => {
      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(
            nonStakedCelo.address,
            nonAccount.address,
            nonVote.address,
            nonVote.address,
            ADDRESS_ZERO,
            nonVote.address
          )
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("reverts with zero default strategy address", async () => {
      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(
            nonStakedCelo.address,
            nonAccount.address,
            nonVote.address,
            nonVote.address,
            nonVote.address,
            ADDRESS_ZERO
          )
      ).revertedWith("AddressZeroNotAllowed");
    });

    it("sets the vote contract", async () => {
      await manager
        .connect(ownerSigner)
        .setDependencies(
          nonStakedCelo.address,
          nonAccount.address,
          nonVote.address,
          nonVote.address,
          nonVote.address,
          nonVote.address
        );
      const newVoteContract = await manager.voteContract();
      expect(newVoteContract).to.eq(nonVote.address);
    });

    it("emits a VoteContractSet event", async () => {
      const managerOwner = await manager.owner();
      const ownerSigner = await getImpersonatedSigner(managerOwner);

      await expect(
        manager
          .connect(ownerSigner)
          .setDependencies(
            nonStakedCelo.address,
            nonAccount.address,
            nonVote.address,
            nonVote.address,
            nonVote.address,
            nonVote.address
          )
      )
        .to.emit(manager, "VoteContractSet")
        .withArgs(nonVote.address);
    });

    it("cannot be called by a non-Owner account", async () => {
      await expect(
        manager
          .connect(nonOwner)
          .setDependencies(
            nonStakedCelo.address,
            nonAccount.address,
            nonVote.address,
            nonVote.address,
            nonVote.address,
            nonVote.address
          )
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
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        defaultGroupDeposit = BigNumber.from(1000); //parseUnits("1");
        await manager.connect(depositor).deposit({ value: defaultGroupDeposit });
        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
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
        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );

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

      describe("When changing strategy from default -> specific", () => {
        const specificGroupStrategyDeposit = 100;
        let specificGroupStrategyAddress: string;
        beforeEach(async () => {
          specificGroupStrategyAddress = groupAddresses[2];
          await manager.connect(depositor2).changeStrategy(specificGroupStrategyAddress);
          await manager.connect(depositor2).deposit({ value: specificGroupStrategyDeposit });
          await updateGroupCeloBasedOnProtocolStCelo(
            defaultStrategyContract,
            specificGroupStrategyContract,
            account,
            manager
          );
        });

        describe("When different ratio of CELO vs stCELO", () => {
          describe("When there is more CELO than stCELO", () => {
            beforeEach(async () => {
              await account.setTotalCelo(2200);
              await updateGroupCeloBasedOnProtocolStCelo(
                defaultStrategyContract,
                specificGroupStrategyContract,
                account,
                manager
              );
            });

            it("should schedule transfers if default strategy => specific strategy", async () => {
              await manager
                .connect(stakedCeloSigner)
                .transfer(depositor.address, depositor2.address, defaultGroupDeposit);
              const [
                lastTransferFromGroups,
                lastTransferFromVotes,
                lastTransferToGroups,
                lastTransferToVotes,
              ] = await account.getLastTransferValues();

              const [head] = await defaultStrategyContract.getGroupsHead();

              expect(lastTransferFromGroups).to.deep.eq([head]);
              expect(lastTransferFromVotes).to.deep.eq([defaultGroupDeposit.mul(2)]);

              expect(lastTransferToGroups).to.deep.eq([specificGroupStrategyAddress]);
              expect(lastTransferToVotes).to.deep.eq([defaultGroupDeposit.mul(2)]);
            });
          });

          describe("When there is less CELO than stCELO", () => {
            beforeEach(async () => {
              await account.setTotalCelo(550);
            });

            it("should schedule transfers if default strategy => specific strategy", async () => {
              await manager
                .connect(stakedCeloSigner)
                .transfer(depositor.address, depositor2.address, defaultGroupDeposit);
              const [
                lastTransferFromGroups,
                lastTransferFromVotes,
                lastTransferToGroups,
                lastTransferToVotes,
              ] = await account.getLastTransferValues();

              const [head] = await defaultStrategyContract.getGroupsHead();

              expect(lastTransferFromGroups).to.deep.eq([head]);
              expect(lastTransferFromVotes).to.deep.eq([defaultGroupDeposit.div(2)]);

              expect(lastTransferToGroups).to.deep.eq([specificGroupStrategyAddress]);
              expect(lastTransferToVotes).to.deep.eq([defaultGroupDeposit.div(2)]);
            });
          });
        });

        it("should schedule transfers if default strategy => specific strategy", async () => {
          await manager
            .connect(stakedCeloSigner)
            .transfer(depositor.address, depositor2.address, defaultGroupDeposit);
          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          const [head] = await defaultStrategyContract.getGroupsHead();

          expect(lastTransferFromGroups).to.deep.eq([head]);
          expect(lastTransferFromVotes).to.deep.eq([defaultGroupDeposit]);

          expect(lastTransferToGroups).to.deep.eq([specificGroupStrategyAddress]);
          expect(lastTransferToVotes).to.deep.eq([defaultGroupDeposit]);
        });
      });
    });

    describe("When depositor voted for specific strategy", () => {
      const withdrawals = [40, 50];
      let specificGroupStrategyAddress: string;
      let specificGroupStrategyDeposit: BigNumber;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        specificGroupStrategyAddress = groupAddresses[2];
        specificGroupStrategyDeposit = BigNumber.from(100);
        await account.setCeloForGroup(specificGroupStrategyAddress, specificGroupStrategyDeposit);

        await manager.connect(depositor).changeStrategy(specificGroupStrategyAddress);
        await manager.connect(depositor).deposit({ value: specificGroupStrategyDeposit });
      });

      it("should not schedule any transfers if second account also voted for same specific group strategy", async () => {
        const differentSpecificGroupStrategyDeposit = parseUnits("1");
        await manager.connect(depositor2).changeStrategy(specificGroupStrategyAddress);
        await manager.connect(depositor2).deposit({ value: differentSpecificGroupStrategyDeposit });

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

      describe("When different ration between CELO and stCELO", () => {
        describe("When there is more CELO than stCELO", () => {
          beforeEach(async () => {
            await account.setTotalCelo(200);
          });

          it("should schedule transfers if specific strategy => default strategy", async () => {
            const [tail] = await defaultStrategyContract.getGroupsTail();
            await manager
              .connect(stakedCeloSigner)
              .transfer(depositor.address, depositor2.address, specificGroupStrategyDeposit);
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.deep.eq([specificGroupStrategyAddress]);
            expect(lastTransferFromVotes).to.deep.eq([specificGroupStrategyDeposit.mul(2)]);

            expect(lastTransferToGroups).to.deep.eq([tail]);
            expect(lastTransferToVotes).to.deep.eq([specificGroupStrategyDeposit.mul(2)]);
          });
        });

        describe("When there is less CELO than stCELO", () => {
          beforeEach(async () => {
            await account.setTotalCelo(50);
          });

          it("should schedule transfers if specific strategy => default strategy", async () => {
            const [tail] = await defaultStrategyContract.getGroupsTail();
            await manager
              .connect(stakedCeloSigner)
              .transfer(depositor.address, depositor2.address, specificGroupStrategyDeposit);
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.deep.eq([specificGroupStrategyAddress]);
            expect(lastTransferFromVotes).to.deep.eq([specificGroupStrategyDeposit.div(2)]);

            expect(lastTransferToGroups).to.deep.eq([tail]);
            expect(lastTransferToVotes).to.deep.eq([specificGroupStrategyDeposit.div(2)]);
          });
        });
      });

      it("should schedule transfers if specific strategy => default strategy", async () => {
        const [tail] = await defaultStrategyContract.getGroupsTail();
        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor.address, depositor2.address, specificGroupStrategyDeposit);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([specificGroupStrategyAddress]);
        expect(lastTransferFromVotes).to.deep.eq([specificGroupStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([tail]);
        expect(lastTransferToVotes).to.deep.eq([specificGroupStrategyDeposit]);
      });

      it("should schedule transfers if specific strategy => different specific strategy", async () => {
        const differentSpecificGroupStrategyDeposit = parseUnits("1");
        await manager.connect(depositor2).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor2).deposit({ value: differentSpecificGroupStrategyDeposit });

        await account.setCeloForGroup(groupAddresses[0], differentSpecificGroupStrategyDeposit);

        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor2.address, depositor.address, differentSpecificGroupStrategyDeposit);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0]]);
        expect(lastTransferFromVotes).to.deep.eq([differentSpecificGroupStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([specificGroupStrategyAddress]);
        expect(lastTransferToVotes).to.deep.eq([differentSpecificGroupStrategyDeposit]);
      });

      it("should schedule transfers to default if different specific strategy was blocked", async () => {
        const differentSpecificGroupStrategyDeposit = BigNumber.from(100);
        const differentSpecificGroupStrategyAddress = groupAddresses[0];
        await specificGroupStrategyContract.connect(owner).blockGroup(specificGroupStrategyAddress);
        await manager.connect(depositor2).changeStrategy(differentSpecificGroupStrategyAddress);
        await manager.connect(depositor2).deposit({ value: differentSpecificGroupStrategyDeposit });
        await account.setCeloForGroup(
          differentSpecificGroupStrategyAddress,
          differentSpecificGroupStrategyDeposit
        );

        const [tail] = await defaultStrategyContract.getGroupsTail();

        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor2.address, depositor.address, differentSpecificGroupStrategyDeposit);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([differentSpecificGroupStrategyAddress]);
        expect(lastTransferFromVotes).to.deep.eq([differentSpecificGroupStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([tail]);
        expect(lastTransferToVotes).to.deep.eq([specificGroupStrategyDeposit]);
      });

      it("should schedule transfers from default if specific strategy was blocked", async () => {
        const differentSpecificGroupStrategyDeposit = BigNumber.from(1000);
        const differentSpecificGroupStrategyAddress = groupAddresses[0];
        await manager.connect(depositor2).changeStrategy(differentSpecificGroupStrategyAddress);
        await manager.connect(depositor2).deposit({ value: differentSpecificGroupStrategyDeposit });
        await account.setCeloForGroup(
          differentSpecificGroupStrategyAddress,
          differentSpecificGroupStrategyDeposit.add(withdrawals[0])
        );
        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
        await specificGroupStrategyContract
          .connect(owner)
          .blockGroup(differentSpecificGroupStrategyAddress);
        await account.setCeloForGroup(
          differentSpecificGroupStrategyAddress,
          differentSpecificGroupStrategyDeposit
        );

        const [head] = await defaultStrategyContract.getGroupsHead();
        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
        await manager
          .connect(stakedCeloSigner)
          .transfer(depositor2.address, depositor.address, differentSpecificGroupStrategyDeposit);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([head]);
        expect(lastTransferFromVotes).to.deep.eq([differentSpecificGroupStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([specificGroupStrategyAddress]);
        expect(lastTransferToVotes).to.deep.eq([differentSpecificGroupStrategyDeposit]);
      });
    });

    describe("When depositor voted for specific strategy that is overflowing and unhealthy -> different specific strategy", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      const depositOverCapacity = parseUnits("10");
      let specificGroup: string;
      let deposit: BigNumber;
      let differentSpecificGroupStrategy: string;
      let originalTail: string;
      let originalHead: string;

      beforeEach(async () => {
        specificGroup = groupAddresses[0];
        differentSpecificGroupStrategy = groupAddresses[4];
        deposit = firstGroupCapacity.add(depositOverCapacity);
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses.slice(0, 3),
          false
        );
        await defaultStrategyContract
          .connect(owner)
          .activateGroup(groupAddresses[1], ADDRESS_ZERO, ADDRESS_ZERO);
        await defaultStrategyContract
          .connect(owner)
          .activateGroup(groupAddresses[2], ADDRESS_ZERO, groupAddresses[1]);

        [originalTail] = await defaultStrategyContract.getGroupsTail();
        [originalHead] = await defaultStrategyContract.getGroupsHead();
        await manager.connect(depositor).changeStrategy(specificGroup);
        await manager.connect(depositor).deposit({ value: deposit });

        await revokeElectionOnMockValidatorGroupsAndUpdate(
          validators,
          accountsWrapper,
          groupHealthContract,
          [specificGroup]
        );
        await groupHealthContract.updateGroupHealth(specificGroup);
        await specificGroupStrategyContract.rebalanceWhenHealthChanged(specificGroup);

        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
      });

      describe("When different ratio of CELO and stCELO", () => {
        describe("When 1:1", () => {
          beforeEach(async () => {
            await manager.connect(depositor).changeStrategy(differentSpecificGroupStrategy);
          });
          it("should schedule correct transfer", async () => {
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect([originalTail, originalHead]).to.have.deep.members(lastTransferFromGroups);
            expect([depositOverCapacity, firstGroupCapacity]).to.have.deep.members(
              lastTransferFromVotes
            );
            expect([differentSpecificGroupStrategy]).to.have.deep.members(lastTransferToGroups);
            expect([deposit]).to.have.deep.members(lastTransferToVotes);
          });
        });

        describe("When less CELO than stCELO", () => {
          beforeEach(async () => {
            await account.setTotalCelo(deposit.div(2));
            await manager.connect(depositor).changeStrategy(differentSpecificGroupStrategy);
          });

          it("should schedule correct transfer", async () => {
            await manager.connect(depositor).changeStrategy(differentSpecificGroupStrategy);
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect([originalTail, originalHead]).to.have.deep.members(lastTransferFromGroups);
            expect([depositOverCapacity.div(2), firstGroupCapacity.div(2)]).to.have.deep.members(
              lastTransferFromVotes
            );
            expect([differentSpecificGroupStrategy]).to.have.deep.members(lastTransferToGroups);
            expect([deposit.div(2)]).to.have.deep.members(lastTransferToVotes);
          });
        });
      });
    });
  });

  describe("#getAddressStrategy()", () => {
    it("should return default strategy", async () => {
      const strategy = await manager.getAddressStrategy(depositor.address);
      expect(strategy).to.eq(ADDRESS_ZERO);
    });

    describe("When strategy changed", () => {
      let specificGroupStrategyAddress: string;
      const withdrawals = [40, 50];

      beforeEach(async () => {
        specificGroupStrategyAddress = groupAddresses[2];
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        await manager.connect(depositor).changeStrategy(specificGroupStrategyAddress);
      });

      it("should return specific strategy", async () => {
        const strategy = await manager.getAddressStrategy(depositor.address);
        expect(strategy).to.eq(specificGroupStrategyAddress);
      });

      describe("When strategy blocked", () => {
        beforeEach(async () => {
          await specificGroupStrategyContract
            .connect(owner)
            .blockGroup(specificGroupStrategyAddress);
        });

        it("should return default strategy", async () => {
          const strategy = await manager.getAddressStrategy(depositor.address);
          expect(strategy).to.eq(ADDRESS_ZERO);
        });
      });

      describe("When group unhealthy", () => {
        beforeEach(async () => {
          await updateGroupSlashingMultiplier(
            registryContract,
            lockedGoldContract,
            validatorsContract,
            groups[2],
            mockSlasher
          );
          await groupHealthContract.updateGroupHealth(specificGroupStrategyAddress);
        });

        it("should return default strategy", async () => {
          const strategy = await manager.getAddressStrategy(depositor.address);
          expect(strategy).to.eq(ADDRESS_ZERO);
        });
      });
    });
  });

  describe("#changeStrategy()", () => {
    const withdrawals = [40, 50];
    let specificGroupStrategyAddress: string;

    beforeEach(async () => {
      specificGroupStrategyAddress = groupAddresses[2];
      for (let i = 0; i < 2; i++) {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract
          .connect(owner)
          .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
      }
    });

    it("should revert when not valid group", async () => {
      const slashedGroup = groups[0];
      await updateGroupSlashingMultiplier(
        registryContract,
        lockedGoldContract,
        validatorsContract,
        slashedGroup,
        mockSlasher
      );
      await mineToNextEpoch(hre.web3);
      await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
        slashedGroup.address,
      ]);
      await expect(manager.changeStrategy(slashedGroup.address)).revertedWith(
        `GroupNotEligible("${slashedGroup.address}")`
      );
    });

    describe("When changing with no previous stCelo", () => {
      beforeEach(async () => {
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
      });

      it("should add group to voted strategies", async () => {
        await manager.connect(depositor).deposit({ value: 100 });
        const specificStrategies = await getSpecificGroups(specificGroupStrategyContract);
        expect([groupAddresses[0]]).to.deep.eq(specificStrategies);
      });

      it("should change account strategy ", async () => {
        const strategy = await manager.connect(depositor).getAddressStrategy(depositor.address);
        expect(groupAddresses[0]).to.eq(strategy);
      });
    });

    describe("When depositor chose specific strategy", () => {
      let specificGroupStrategyDeposit: BigNumber;

      beforeEach(async () => {
        specificGroupStrategyDeposit = parseUnits("2");
        await manager.changeStrategy(specificGroupStrategyAddress);
        await manager.deposit({ value: specificGroupStrategyDeposit });
        await account.setCeloForGroup(specificGroupStrategyAddress, specificGroupStrategyDeposit);
      });

      it("should schedule nothing when trying to change to same specific strategy", async () => {
        await manager.changeStrategy(specificGroupStrategyAddress);
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

      it("should schedule transfers when changing to different specific strategy", async () => {
        const differentSpecificGroupStrategy = groupAddresses[0];

        await manager.changeStrategy(differentSpecificGroupStrategy);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect([specificGroupStrategyAddress]).to.deep.eq(lastTransferFromGroups);
        expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferFromVotes);
        expect([differentSpecificGroupStrategy]).to.deep.eq(lastTransferToGroups);
        expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferToVotes);
        expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferToVotes);
      });

      it("should emit StrategyChanged event", async () => {
        const differentSpecificGroupStrategy = groupAddresses[0];

        await expect(manager.changeStrategy(differentSpecificGroupStrategy))
          .to.emit(manager, "StrategyChanged")
          .withArgs(differentSpecificGroupStrategy);
      });

      it("should schedule transfers when changing to default strategy", async () => {
        const [tail] = await defaultStrategyContract.getGroupsTail();
        await manager.changeStrategy(ADDRESS_ZERO);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([specificGroupStrategyAddress]);
        expect(lastTransferFromVotes).to.deep.eq([specificGroupStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([tail]);
        expect(lastTransferToVotes).to.deep.eq([specificGroupStrategyDeposit]);
      });

      describe("When chosen group is unhealthy", () => {
        beforeEach(async () => {
          await updateGroupSlashingMultiplier(
            registryContract,
            lockedGoldContract,
            validatorsContract,
            groups[2],
            mockSlasher
          );
          await groupHealthContract.updateGroupHealth(specificGroupStrategyAddress);
        });

        it("should schedule transfers from group (since group was not rebalanced) when changing to different specific strategy", async () => {
          const differentSpecificGroupStrategy = groupAddresses[0];
          const [head] = await defaultStrategyContract.getGroupsHead();
          await account.setCeloForGroup(head, specificGroupStrategyDeposit);

          await manager.changeStrategy(differentSpecificGroupStrategy);
          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          expect([specificGroupStrategyAddress]).to.deep.eq(lastTransferFromGroups);
          expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferFromVotes);
          expect([differentSpecificGroupStrategy]).to.deep.eq(lastTransferToGroups);
          expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferToVotes);
        });

        describe("When rebalanced", () => {
          beforeEach(async () => {
            await specificGroupStrategyContract.rebalanceWhenHealthChanged(
              specificGroupStrategyAddress
            );
            await updateGroupCeloBasedOnProtocolStCelo(
              defaultStrategyContract,
              specificGroupStrategyContract,
              account,
              manager
            );
          });

          it("should schedule transfers when changing to default strategy", async () => {
            const [tail] = await defaultStrategyContract.getGroupsTail();
            const [head] = await defaultStrategyContract.getGroupsHead();
            await manager.changeStrategy(ADDRESS_ZERO);
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect([head]).to.deep.eq(lastTransferFromGroups);
            expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferFromVotes);
            expect([tail]).to.deep.eq(lastTransferToGroups);
            expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferToVotes);
          });
        });

        it("should schedule transfers when changing to default strategy", async () => {
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await manager.changeStrategy(ADDRESS_ZERO);
          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          expect([specificGroupStrategyAddress]).to.deep.eq(lastTransferFromGroups);
          expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferFromVotes);
          expect([tail]).to.deep.eq(lastTransferToGroups);
          expect([specificGroupStrategyDeposit]).to.deep.eq(lastTransferToVotes);
        });
      });
    });

    describe("When depositor chose default strategy", () => {
      let defaultGroupDeposit: BigNumber;

      beforeEach(async () => {
        defaultGroupDeposit = parseUnits("2");
        await manager.deposit({ value: defaultGroupDeposit });
        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
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

      it("should schedule transfers when changing to specific strategy", async () => {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await manager.changeStrategy(specificGroupStrategyAddress);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([head]);
        expect(lastTransferFromVotes).to.deep.eq([defaultGroupDeposit]);

        expect(lastTransferToGroups).to.deep.eq([specificGroupStrategyAddress]);
        expect(lastTransferToVotes).to.deep.eq([defaultGroupDeposit]);
      });
    });
  });

  describe("#getExpectedAndActualCeloForGroup()", () => {
    describe("When strategy is blocked", () => {
      const withdrawals = [50, 50];
      const depositedValue = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        await manager.changeStrategy(groupAddresses[2]);
        await manager.deposit({ value: depositedValue });
        await account.setCeloForGroup(groupAddresses[2], depositedValue);
        await specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[2]);
      });

      it("should return correct amount for real and expected", async () => {
        const [expected, real] = await manager.getExpectedAndActualCeloForGroup(groupAddresses[2]);
        expect(expected).to.eq(0);
        expect(real).to.eq(depositedValue);
      });
    });

    describe("When specific strategy is overflowing and unhealthy", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      const depositOverCapacity = parseUnits("10");
      let specificGroup: string;
      let deposit: BigNumber;
      let originalTail: string;

      beforeEach(async () => {
        specificGroup = groupAddresses[0];
        deposit = firstGroupCapacity.add(depositOverCapacity);
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses.slice(0, 3),
          false
        );
        await defaultStrategyContract
          .connect(owner)
          .activateGroup(groupAddresses[1], ADDRESS_ZERO, ADDRESS_ZERO);
        await defaultStrategyContract
          .connect(owner)
          .activateGroup(groupAddresses[2], ADDRESS_ZERO, groupAddresses[1]);
        [originalTail] = await defaultStrategyContract.getGroupsTail();
        await manager.connect(depositor).changeStrategy(specificGroup);
        await manager.connect(depositor).deposit({ value: deposit });

        await updateGroupCeloBasedOnProtocolStCelo(
          defaultStrategyContract,
          specificGroupStrategyContract,
          account,
          manager
        );
      });

      it("should return correct amount for real and expected in specific strategy", async () => {
        const [expected, real] = await manager.getExpectedAndActualCeloForGroup(specificGroup);
        expect(expected).to.eq(firstGroupCapacity);
        expect(real).to.eq(firstGroupCapacity);
      });

      it("should return correct amount for real and expected in default strategy", async () => {
        const [expected, real] = await manager.getExpectedAndActualCeloForGroup(originalTail);
        expect(expected).to.eq(depositOverCapacity);
        expect(real).to.eq(depositOverCapacity);
      });

      describe("When group becomes unhealthy", () => {
        let newTail: string;
        beforeEach(async () => {
          await revokeElectionOnMockValidatorGroupsAndUpdate(
            validators,
            accountsWrapper,
            groupHealthContract,
            [specificGroup]
          );
          [newTail] = await defaultStrategyContract.getGroupsTail();
          await specificGroupStrategyContract.rebalanceWhenHealthChanged(specificGroup);
          await updateGroupCeloBasedOnProtocolStCelo(
            defaultStrategyContract,
            specificGroupStrategyContract,
            account,
            manager
          );
        });

        it("should return correct amount for real and expected in specific strategy", async () => {
          const [expected, real] = await manager.getExpectedAndActualCeloForGroup(specificGroup);
          expect(expected).to.eq(BigNumber.from(0));
          expect(real).to.eq(BigNumber.from(0));
        });

        it("should return correct amount for real and expected in default strategy", async () => {
          const [expected, real] = await manager.getExpectedAndActualCeloForGroup(originalTail);
          expect(expected).to.eq(depositOverCapacity);
          expect(real).to.eq(depositOverCapacity);

          const [expected2, real2] = await manager.getExpectedAndActualCeloForGroup(newTail);
          expect(expected2).to.eq(firstGroupCapacity);
          expect(real2).to.eq(firstGroupCapacity);
        });
      });
    });

    describe("When group is deactivated", () => {
      const withdrawals = [50, 50];
      const depositedValue = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        await manager.deposit({ value: depositedValue });
        await defaultStrategyContract.connect(owner).deactivateGroup(groupAddresses[0]);
      });

      it("should return correct amount for real and expected", async () => {
        const [expected, real] = await manager.getExpectedAndActualCeloForGroup(groupAddresses[0]);
        expect(expected).to.eq(0);
        expect(real).to.eq(depositedValue / 2);
      });
    });

    describe("When group is only in specific group strategy", () => {
      const depositedValue = 100;
      beforeEach(async () => {
        await manager.changeStrategy(groupAddresses[0]);
        await manager.deposit({ value: depositedValue });
      });

      it("should return same amount for real and expected", async () => {
        await account.setCeloForGroup(groupAddresses[0], depositedValue);

        const [expected, real] = await manager.getExpectedAndActualCeloForGroup(groupAddresses[0]);
        expect(expected).to.eq(real);
      });

      it("should return different amount for real and expected", async () => {
        const celoForGroup = 50;
        await account.setCeloForGroup(groupAddresses[0], celoForGroup);

        const [expected, real] = await manager.getExpectedAndActualCeloForGroup(groupAddresses[0]);
        expect(expected).to.eq(depositedValue);
        expect(real).to.eq(celoForGroup);
      });
    });

    describe("When there are active groups", () => {
      const withdrawals = [50, 50];

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
      });

      describe("When group is only in active", () => {
        const depositedValue = 100;
        beforeEach(async () => {
          await manager.deposit({ value: depositedValue });
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          await rebalanceDefaultGroups(defaultStrategyContract as any);
        });

        it("should return same amount for real and expected", async () => {
          const [expected, real] = await manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
          );
          expect(expected).to.eq(real);
        });

        it("should return different amount for real and expected", async () => {
          const celoForGroup = 60;
          await account.setCeloForGroup(groupAddresses[0], celoForGroup);

          const [expected, real] = await manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
          );
          expect(expected).to.eq(depositedValue / 2);
          expect(real).to.eq(celoForGroup);
        });
      });

      describe("When group is in both active and voted", () => {
        const defaultDepositedValue = 100;
        const specificGroupStrategyDepositedValue = 100;

        beforeEach(async () => {
          await manager.connect(depositor).deposit({ value: defaultDepositedValue });
          await manager.connect(depositor2).changeStrategy(groupAddresses[0]);
          await manager.connect(depositor2).deposit({ value: specificGroupStrategyDepositedValue });
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          await rebalanceDefaultGroups(defaultStrategyContract as any);
        });

        it("should return same amount for real and expected", async () => {
          await account.setCeloForGroup(
            groupAddresses[0],
            defaultDepositedValue / 2 + specificGroupStrategyDepositedValue
          );
          const [expected, real] = await manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
          );
          expect(expected).to.eq(real);
        });

        it("should return different amount for real and expected", async () => {
          const celoForGroup = 60;
          await account.setCeloForGroup(groupAddresses[0], celoForGroup);

          const [expected, real] = await manager.getExpectedAndActualCeloForGroup(
            groupAddresses[0]
          );
          expect(expected).to.eq(defaultDepositedValue / 2 + specificGroupStrategyDepositedValue);
          expect(real).to.eq(celoForGroup);
        });

        describe("When having different ratio of CELO vs stCELO", () => {
          describe("When there is more CELO than stCELO", () => {
            beforeEach(async () => {
              await account.setTotalCelo(400);
            });

            it("should return different amount for real and expected", async () => {
              const celoForGroup = 50;
              await account.setCeloForGroup(groupAddresses[0], celoForGroup);

              const [expected, real] = await manager.getExpectedAndActualCeloForGroup(
                groupAddresses[0]
              );
              expect(expected).to.eq(
                (defaultDepositedValue / 2 + specificGroupStrategyDepositedValue) * 2
              );
              expect(real).to.eq(celoForGroup);
            });
          });

          describe("When there is less CELO than stCELO", () => {
            beforeEach(async () => {
              await account.setTotalCelo(100);
            });

            it("should return different amount for real and expected", async () => {
              const celoForGroup = 50;
              await account.setCeloForGroup(groupAddresses[0], celoForGroup);

              const [expected, real] = await manager.getExpectedAndActualCeloForGroup(
                groupAddresses[0]
              );
              expect(expected).to.eq(
                (defaultDepositedValue / 2 + specificGroupStrategyDepositedValue) / 2
              );
              expect(real).to.eq(celoForGroup);
            });
          });
        });
      });
    });

    describe("when groups are close to their voting limit", () => {
      const thirdGroupCapacity = parseUnits("200.166666666666666666");

      beforeEach(async () => {
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses.slice(0, 3),
          false
        );
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract
            .connect(owner)
            .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        }
      });

      describe("When depositing to specific strategy that is not used in active groups", () => {
        const deposit = parseUnits("250");
        beforeEach(async () => {
          await manager.connect(depositor).changeStrategy(groupAddresses[2]);
          await manager.connect(depositor).deposit({ value: deposit });
          await account.setCeloForGroup(groupAddresses[2], thirdGroupCapacity);
        });

        it("should return expected without overflow", async () => {
          const [expected, actual] = await manager.getExpectedAndActualCeloForGroup(
            groupAddresses[2]
          );
          const stCeloInDefaultStrategy = await defaultStrategyContract.totalStCeloInStrategy();
          expect(expected).to.deep.eq(thirdGroupCapacity);
          expect(actual).to.deep.eq(thirdGroupCapacity);
          expect(stCeloInDefaultStrategy).to.deep.eq(deposit.sub(thirdGroupCapacity));
        });
      });
    });
  });

  describe("#rebalance()", () => {
    const fromGroupDepositedValue = 100;
    const toGroupDepositedValue = 77;

    it("should revert when trying to balance some and 0x0 group", async () => {
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });

      await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue + 1);

      await expect(manager.rebalance(groupAddresses[0], ADDRESS_ZERO)).revertedWith(
        `RebalanceEnoughCelo("${ADDRESS_ZERO}", 0, 0)`
      );
    });

    it("should revert when trying to balance 0x0 and 0x0 group", async () => {
      await expect(manager.rebalance(ADDRESS_ZERO, ADDRESS_ZERO)).revertedWith(
        `RebalanceNoExtraCelo("${ADDRESS_ZERO}", 0, 0)`
      );
    });

    it("should revert when fromGroup has less Celo than it should", async () => {
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });

      await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
      await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });

      await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue - 1);
      await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
        `RebalanceNoExtraCelo("${groupAddresses[0]}", ${
          fromGroupDepositedValue - 1
        }, ${fromGroupDepositedValue})`
      );
    });

    it("should revert when fromGroup has same Celo as it should", async () => {
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });

      await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
      await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });

      await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue);
      await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
        `RebalanceNoExtraCelo("${groupAddresses[0]}", ${fromGroupDepositedValue}, ${fromGroupDepositedValue})`
      );
    });

    describe("When fromGroup has valid properties", () => {
      const toGroupDepositedValue = 77;

      beforeEach(async () => {
        await manager.changeStrategy(groupAddresses[0]);
        await manager.deposit({ value: fromGroupDepositedValue });
        await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue + 1);
      });

      it("should revert when toGroup has more Celo than it should", async () => {
        await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
        await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });
        await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue + 1);

        await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
          `RebalanceEnoughCelo("${groupAddresses[1]}", ${
            toGroupDepositedValue + 1
          }, ${toGroupDepositedValue})`
        );
      });

      it("should revert when toGroup has same Celo as it should", async () => {
        await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
        await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });
        await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue);

        await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
          `RebalanceEnoughCelo("${groupAddresses[1]}", ${toGroupDepositedValue}, ${toGroupDepositedValue})`
        );
      });

      describe("When toGroup has valid properties", () => {
        beforeEach(async () => {
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

        describe("When having same active groups and strategies get blocked", () => {
          beforeEach(async () => {
            for (let i = 0; i < 2; i++) {
              const [head] = await defaultStrategyContract.getGroupsHead();
              await defaultStrategyContract
                .connect(owner)
                .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            }
            await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue);

            await specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[0]);
            await specificGroupStrategyContract.rebalanceWhenHealthChanged(groupAddresses[0]);
            await specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[1]);
            await specificGroupStrategyContract.rebalanceWhenHealthChanged(groupAddresses[1]);
          });

          it("should schedule transfer from deactivated group", async () => {
            await defaultStrategyContract.connect(owner).deactivateGroup(groupAddresses[0]);
            const exRe0 = await manager.getExpectedAndActualCeloForGroup(groupAddresses[0]);
            await manager.rebalance(groupAddresses[0], groupAddresses[1]);

            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0]]);
            expect(lastTransferFromVotes).to.deep.eq([BigNumber.from(exRe0[1].sub(exRe0[0]))]);
            expect(lastTransferToGroups).to.deep.eq([groupAddresses[1]]);
            expect(lastTransferToVotes).to.deep.eq([BigNumber.from(exRe0[1].sub(exRe0[0]))]);
          });

          it("should revert when rebalance to deactivated group", async () => {
            await defaultStrategyContract.connect(owner).deactivateGroup(groupAddresses[1]);
            await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
              `InvalidToGroup("${groupAddresses[1]}")`
            );
          });
        });

        describe("When having different active groups", () => {
          beforeEach(async () => {
            for (let i = 2; i < 4; i++) {
              const [head] = await defaultStrategyContract.getGroupsHead();
              await defaultStrategyContract
                .connect(owner)
                .activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            }
          });

          it("should schedule transfer from disspecific strategy", async () => {
            await specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[0]);
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

          it("should revert when rebalance to disspecific strategy", async () => {
            await specificGroupStrategyContract.connect(owner).blockGroup(groupAddresses[1]);
            await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
              `InvalidToGroup("${groupAddresses[1]}")`
            );
          });
        });
      });
    });
  });

  describe("#scheduleTransferWithinStrategy()", () => {
    it("should revert when not called by strategy", async () => {
      await expect(
        manager.connect(depositor).scheduleTransferWithinStrategy([], [], [], [])
      ).revertedWith(`CallerNotStrategy("${depositor.address}")`);
    });

    it("should schedule transfer when called by strategy", async () => {
      const strategyAddress = await manager.defaultStrategy();
      await depositor.sendTransaction({ to: strategyAddress, value: parseUnits("10") });
      const strategySigner = await getImpersonatedSigner(strategyAddress);

      const fromGroups = [groupAddresses[6], groupAddresses[7]];
      const fromVotes = [BigNumber.from(100), BigNumber.from(200)];

      const toGroups = [groupAddresses[8], groupAddresses[9]];
      const toVotes = [BigNumber.from(300), BigNumber.from(400)];

      await manager
        .connect(strategySigner)
        .scheduleTransferWithinStrategy(fromGroups, toGroups, fromVotes, toVotes);

      const [
        lastTransferFromGroups,
        lastTransferFromVotes,
        lastTransferToGroups,
        lastTransferToVotes,
      ] = await account.getLastTransferValues();

      expect(lastTransferFromGroups).to.have.deep.members(fromGroups);
      expect(lastTransferFromVotes).to.deep.eq(fromVotes);

      expect(lastTransferToGroups).to.have.deep.members(toGroups);
      expect(lastTransferToVotes).to.deep.eq(toVotes);
    });
  });

  describe("#getReceivableVotesForGroup()", () => {
    it("should revert when not validator group", async () => {
      await expect(manager.getReceivableVotesForGroup(nonAccount.address)).revertedWith(
        "Not validator group"
      );
    });

    describe("When having validator groups close to voting limit", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");

      beforeEach(async () => {
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses
        );
      });

      it("should return correct amount of receivable votes", async () => {
        const receivableAmount = await manager.getReceivableVotesForGroup(groupAddresses[0]);
        expect(receivableAmount).to.eq(firstGroupCapacity);
      });

      describe("When having some votes scheduled", () => {
        let scheduledVotes: BigNumber;
        beforeEach(async () => {
          scheduledVotes = parseUnits("2");
          await account.setCeloForGroup(groupAddresses[0], scheduledVotes);
        });

        it("should return correct amount", async () => {
          const receivableAmount = await manager.getReceivableVotesForGroup(groupAddresses[0]);
          expect(receivableAmount).to.eq(firstGroupCapacity.sub(scheduledVotes));
        });
      });
    });
  });

  describe("#rebalanceOverflow()", () => {
    it("should revert when to group not active", async () => {
      await expect(manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1])).revertedWith(
        `InvalidToGroup("${groupAddresses[1]}")`
      );
    });

    describe("When active groups", () => {
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      beforeEach(async () => {
        await prepareOverflow(
          defaultStrategyContract.connect(owner),
          election,
          lockedGold,
          voter,
          groupAddresses
        );
      });

      it("should revert when from group not overflowing", async () => {
        await expect(manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1])).revertedWith(
          `FromGroupNotOverflowing("${groupAddresses[0]}")`
        );
      });

      describe("When scheduled votes are still receivable", () => {
        beforeEach(async () => {
          await account.setCeloForGroup(groupAddresses[0], firstGroupCapacity);
        });

        it("should revert when from group has no scheduled votes", async () => {
          await expect(
            manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1])
          ).revertedWith(`FromGroupNotOverflowing("${groupAddresses[0]}")`);
        });
      });

      describe("When from group overflowing", () => {
        beforeEach(async () => {
          await account.setCeloForGroup(groupAddresses[0], firstGroupCapacity.mul(2));
        });

        describe("When to group is overflowing", () => {
          const secondGroupCapacity = parseUnits("99.25");
          beforeEach(async () => {
            await account.setScheduledVotes(groupAddresses[0], firstGroupCapacity.mul(2));
            await account.setCeloForGroup(groupAddresses[1], secondGroupCapacity.mul(2));
          });

          it("should revert", async () => {
            await expect(
              manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1])
            ).revertedWith(`ToGroupOverflowing("${groupAddresses[1]}")`);
          });
        });

        describe("When scheduled votes that are still receivable", () => {
          beforeEach(async () => {
            await account.setScheduledVotes(groupAddresses[0], firstGroupCapacity.mul(2));
            await account.setScheduledRevokeForGroup(groupAddresses[0], parseUnits("1"));
            await account.setScheduledWithdrawalsForGroup(groupAddresses[0], parseUnits("1"));
            await manager.rebalanceOverflow(groupAddresses[0], groupAddresses[1]);
          });

          it("should schedule transfer", async () => {
            const [
              lastTransferFromGroups,
              lastTransferFromVotes,
              lastTransferToGroups,
              lastTransferToVotes,
            ] = await account.getLastTransferValues();

            expect(lastTransferFromGroups).to.have.deep.members([groupAddresses[0]]);
            expect(lastTransferFromVotes).to.deep.eq([firstGroupCapacity.sub(parseUnits("2"))]);

            expect(lastTransferToGroups).to.have.deep.members([groupAddresses[1]]);
            expect(lastTransferToVotes).to.deep.eq([firstGroupCapacity.sub(parseUnits("2"))]);
          });
        });
      });
    });
  });

  describe("#setPauser", () => {
    it("sets the pauser address to the owner of the contract", async () => {
      await manager.connect(owner).setPauser();
      const newPauser = await manager.pauser();
      expect(newPauser).to.eq(owner.address);
    });

    it("emits a PauserSet event", async () => {
      await expect(manager.connect(owner).setPauser())
        .to.emit(manager, "PauserSet")
        .withArgs(owner.address);
    });

    it("cannot be called by a non-owner", async () => {
      await expect(manager.connect(nonOwner).setPauser()).revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    describe("when the owner is changed", async () => {
      beforeEach(async () => {
        await manager.connect(owner).transferOwnership(nonOwner.address);
      });

      it("sets the pauser to the new owner", async () => {
        await manager.connect(nonOwner).setPauser();
        const newPauser = await manager.pauser();
        expect(newPauser).to.eq(nonOwner.address);
      });
    });
  });

  describe("#pause", () => {
    it("can be called by the pauser", async () => {
      await manager.connect(pauser).pause();
      const isPaused = await manager.isPaused();
      expect(isPaused).to.be.true;
    });

    it("emits a ContractPaused event", async () => {
      await expect(manager.connect(pauser).pause()).to.emit(manager, "ContractPaused");
    });

    it("cannot be called by a random account", async () => {
      await expect(manager.connect(nonOwner).pause()).revertedWith("OnlyPauser()");
      const isPaused = await manager.isPaused();
      expect(isPaused).to.be.false;
    });
  });

  describe("#unpause", () => {
    beforeEach(async () => {
      await manager.connect(pauser).pause();
    });

    it("can be called by the pauser", async () => {
      await manager.connect(pauser).unpause();
      const isPaused = await manager.isPaused();
      expect(isPaused).to.be.false;
    });

    it("emits a ContractUnpaused event", async () => {
      await expect(manager.connect(pauser).unpause()).to.emit(manager, "ContractUnpaused");
    });

    it("cannot be called by a random account", async () => {
      await expect(manager.connect(nonOwner).unpause()).revertedWith("OnlyPauser()");
      const isPaused = await manager.isPaused();
      expect(isPaused).to.be.true;
    });
  });

  describe("when paused", () => {
    beforeEach(async () => {
      await manager.connect(pauser).pause();
    });

    it("can't call withdraw", async () => {
      await expect(manager.connect(nonOwner).withdraw(100)).revertedWith("Paused()");
    });

    it("can't call revokeVotes", async () => {
      await expect(manager.connect(nonOwner).revokeVotes(0, 0)).revertedWith("Paused()");
    });

    it("can't call updateHistoryAndReturnLockedStCeloInVoting", async () => {
      await expect(
        manager.connect(nonOwner).updateHistoryAndReturnLockedStCeloInVoting(nonOwner.address)
      ).revertedWith("Paused()");
    });

    it("can't call deposit", async () => {
      await expect(manager.connect(nonOwner).deposit({ value: 100 })).revertedWith("Paused()");
    });

    it("can't call changeStrategy", async () => {
      await expect(manager.connect(nonOwner).changeStrategy(ADDRESS_ZERO)).revertedWith("Paused()");
    });

    it("can't call rebalance", async () => {
      await expect(manager.connect(nonOwner).rebalance(ADDRESS_ZERO, ADDRESS_ZERO)).revertedWith(
        "Paused()"
      );
    });

    it("can't call rebalanceOverflow", async () => {
      await expect(
        manager.connect(nonOwner).rebalanceOverflow(ADDRESS_ZERO, ADDRESS_ZERO)
      ).revertedWith("Paused()");
    });

    it("can't call voteProposal", async () => {
      await expect(manager.connect(nonOwner).voteProposal(0, 0, 0, 0, 0)).revertedWith("Paused()");
    });
  });
});
