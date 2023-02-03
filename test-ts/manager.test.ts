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
  electMockValidatorGroupsAndUpdate,
  getDefaultGroupsSafe,
  getImpersonatedSigner,
  mineToNextEpoch,
  randomSigner,
  rebalanceDefaultGroups,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
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
  let groupHealthContract: MockGroupHealth;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategyContract: MockDefaultStrategy;
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
    try {
      this.timeout(100000);
      await resetNetwork();
      lockedGold = await hre.kit.contracts.getLockedGold();
      election = await hre.kit.contracts.getElection();
      validators = await hre.kit.contracts.getValidators();

      await hre.deployments.fixture("FullTestManager");
      manager = await hre.ethers.getContract("Manager");
      groupHealthContract = await hre.ethers.getContract("MockGroupHealth");
      specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");
      defaultStrategyContract = await hre.ethers.getContract("MockDefaultStrategy");

      [owner] = await randomSigner(parseUnits("100"));
      [nonOwner] = await randomSigner(parseUnits("100"));
      [someone] = await randomSigner(parseUnits("100"));
      [mockSlasher] = await randomSigner(parseUnits("100"));
      [depositor] = await randomSigner(parseUnits("500"));
      [depositor2] = await randomSigner(parseUnits("500"));
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
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
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

      describe("when tail group is deprecated", () => {
        beforeEach(async () => {
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await defaultStrategyContract.deprecateGroup(tail);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
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
      const firstGroupCapacity = parseUnits("40.166666666666666666");
      const secondGroupCapacity = parseUnits("99.25");

      beforeEach(async () => {
        // These numbers are derived from a system of linear equations such that
        // given 12 validators registered and elected, as above, we have the following
        // limits for the first three groups:
        // group[0] and group[2]: 95864 Locked CELO
        // group[1]: 143797 Locked CELO
        // and the remaining receivable votes are [40, 100, 200] (in CELO) for
        // the three groups, respectively.
        const votes = [parseUnits("95824"), parseUnits("143697"), parseUnits("95664")];

        for (let i = 2; i >= 0; i--) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);

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
        expect(votedGroups).to.deep.equal([
          groupAddresses[0],
          groupAddresses[1],
          groupAddresses[2],
        ]);

        expect(votes).to.deep.equal([
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
          await account.setScheduledVotes(groupAddresses[0], firstGroupScheduled);
          await account.setScheduledVotes(groupAddresses[1], secondGroupScheduled);
          await account.setScheduledVotes(groupAddresses[2], thirdGroupScheduled);
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
        const depositAmount = parseUnits("50");

        beforeEach(async () => {
          await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
          await manager.connect(depositor).changeStrategy(groupAddresses[0]);
          await manager.connect(depositor).deposit({ value: depositAmount });
        });

        it("should overflow to default strategy", async () => {
          const [stCeloInStrategy, overflowAmount] =
            await specificGroupStrategyContract.getStCeloInStrategy(groupAddresses[0]);
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
            await defaultStrategyContract.totalStCeloInDefaultStrategy();
          expect(currentDefaultStrategyStCeloBalance).to.deep.eq(
            depositAmount.sub(firstGroupCapacity)
          );
        });
      });
    });

    describe("When voted for specific strategy", () => {
      beforeEach(async () => {
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor).deposit({ value: 100 });
      });

      it("should add group to allowed strategies", async () => {
        const activeGroups = await getDefaultGroupsSafe(defaultStrategyContract);
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect(activeGroups.length).to.eq(0);
        expect(allowedStrategies.length).to.eq(1);
        expect(allowedStrategies[0]).to.eq(groupAddresses[0]);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }

        await specificGroupStrategyContract.allowStrategy(groupAddresses[4]);
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

      it("should not add group to allowed strategies", async () => {
        const activeGroups = await getDefaultGroupsSafe(defaultStrategyContract);
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect(activeGroups).to.have.deep.members(groupAddresses.slice(0, 3));
        expect(allowedStrategies).to.deep.eq([groupAddresses[4]]);
      });

      it("should schedule votes for default groups", async () => {
        const [votedGroups, votes] = await account.getLastScheduledVotes();
        expect(votedGroups).to.deep.equal([originalTail]);
        expect(votes).to.deep.equal([BigNumber.from("100")]);
      });

      it("should not schedule transfers to default strategy when no balance for specific strategy", async () => {
        await specificGroupStrategyContract.blockStrategy(groupAddresses[4]);
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
      let specificGroupStrategyAddress: string;

      describe("Block strategy - group other than active", () => {
        beforeEach(async () => {
          for (let i = 0; i < 2; i++) {
            const [head] = await defaultStrategyContract.getGroupsHead();
            await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            await account.setCeloForGroup(groupAddresses[i], 100);
          }
          specificGroupStrategyAddress = groupAddresses[2];

          await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
          await manager.changeStrategy(specificGroupStrategyAddress);
          await manager.deposit({ value: depositedValue });
          await account.setCeloForGroup(specificGroupStrategyAddress, depositedValue);
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategyAddress);
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
            await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            await account.setCeloForGroup(groupAddresses[i], 100);
            await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(
              groupAddresses[i],
              100
            );
          }
          specificGroupStrategyAddress = groupAddresses[0];

          await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
          await manager.changeStrategy(specificGroupStrategyAddress);
          await manager.deposit({ value: depositedValue });
          await account.setCeloForGroup(specificGroupStrategyAddress, depositedValue);
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategyAddress);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }
      });

      describe("When voted for specific validator group which is not in active groups", () => {
        beforeEach(async () => {
          await specificGroupStrategyContract.allowStrategy(groupAddresses[2]);
          await manager.connect(depositor).changeStrategy(groupAddresses[2]);
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should add group to allowed strategies", async () => {
          const activeGroups = await getDefaultGroupsSafe(defaultStrategyContract);
          const allowedStrategies = await specificGroupStrategyContract
            .connect(depositor)
            .getSpecificGroupStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(allowedStrategies).to.deep.eq([groupAddresses[2]]);
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
          await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
          await manager.connect(depositor).changeStrategy(specificGroupStrategyAddress);
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should add group to allowed strategies", async () => {
          const activeGroups = await getDefaultGroupsSafe(defaultStrategyContract);
          const allowedStrategies = await specificGroupStrategyContract
            .connect(depositor)
            .getSpecificGroupStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(allowedStrategies).to.deep.eq([specificGroupStrategyAddress]);
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
  });

  describe("#withdraw()", () => {
    it("reverts when there are no active or deprecated groups", async () => {
      await expect(manager.connect(depositor).withdraw(100)).revertedWith("NoActiveGroups()");
    });

    describe("when groups are activated", () => {
      let originalHead: string;

      beforeEach(async () => {
        let nextGroup = ADDRESS_ZERO;
        for (let i = 0; i < 3; i++) {
          const [tail] = await defaultStrategyContract.getGroupsTail();
          await defaultStrategyContract.activateGroup(groupAddresses[i], nextGroup, tail);
          nextGroup = groupAddresses[i];
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
            await defaultStrategyContract.totalStCeloInDefaultStrategy()
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
              await defaultStrategyContract.totalStCeloInDefaultStrategy()
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
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], 100);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(groupAddresses[i], 100);
        }
        await manager.connect(depositor).deposit({ value: 100 });
        // await stakedCelo.mint(depositor.address, 100);
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
          // await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic()

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
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
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

    describe("When there are other active groups besides specific validator group - allowed is different from active", () => {
      const withdrawals = [40, 50];
      const specificGroupStrategyWithdrawal = 100;
      let specificGroupStrategy: SignerWithAddress;

      beforeEach(async () => {
        specificGroupStrategy = groups[2];
        let nextGroup = ADDRESS_ZERO;
        for (let i = 0; i < 2; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
          nextGroup = groupAddresses[i];
          await manager.connect(depositor2).deposit({ value: withdrawals[i] });
        }

        await account.setCeloForGroup(
          specificGroupStrategy.address,
          specificGroupStrategyWithdrawal
        );

        await specificGroupStrategyContract.allowStrategy(specificGroupStrategy.address);
        await manager.connect(depositor).changeStrategy(specificGroupStrategy.address);
        await manager.connect(depositor).deposit({ value: specificGroupStrategyWithdrawal });
      });

      it("added group to allowed strategies", async () => {
        const activeGroups = await getDefaultGroupsSafe(defaultStrategyContract);
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect(activeGroups).to.have.deep.members([groupAddresses[0], groupAddresses[1]]);
        expect(allowedStrategies).to.deep.eq([specificGroupStrategy.address]);
      });

      it("should withdraw less than originally deposited from specific group strategy", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([specificGroupStrategy.address]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect(allowedStrategies).to.deep.eq([specificGroupStrategy.address]);
      });

      it("should withdraw same amount as originally deposited from specific group strategy", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect([specificGroupStrategy.address]).to.deep.equal(withdrawnGroups);
        expect([BigNumber.from("100")]).to.deep.equal(withdrawals);
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect([specificGroupStrategy.address]).to.deep.eq(allowedStrategies);
      });

      it("should withdraw same amount as originally deposited from active groups after strategy is disallowed", async () => {
        await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
        const [, , , lastTransferToVotes] = await account.getLastTransferValues();

        const [groupHead] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(
          groupHead,
          lastTransferToVotes[0]
        );

        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, groupWithdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([groupHead]);
        expect(groupWithdrawals).to.deep.equal([BigNumber.from("100")]);
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect(allowedStrategies).to.deep.eq([]);
      });

      it("should revert when withdraw more amount than originally deposited from specific group strategy", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `CantWithdrawAccordingToStrategy("${specificGroupStrategy.address}")`
        );
      });

      describe("When strategy blocked", () => {
        beforeEach(async () => {
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
        });

        it('should withdraw correctly after "rebalance"', async () => {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await manager.connect(depositor).withdraw(specificGroupStrategyWithdrawal);

          const [withdrawnGroups, groupWithdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([head]);
          expect(groupWithdrawals).to.deep.equal([BigNumber.from(specificGroupStrategyWithdrawal)]);
        });
      });
    });

    describe("When there are other active groups besides specific validator group - allowed is one of the active groups", () => {
      const withdrawals = [40, 50];
      const specificGroupStrategyWithdrawal = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
        await account.setCeloForGroup(
          groupAddresses[1],
          withdrawals[1] + specificGroupStrategyWithdrawal
        );

        await specificGroupStrategyContract.allowStrategy(groupAddresses[1]);
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
        // For more info about these numbers check comment above
        const votes = [parseUnits("95824"), parseUnits("143697"), parseUnits("95664")];

        for (let i = 2; i >= 0; i--) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);

          await lockedGold.lock().sendAndWaitForReceipt({
            from: voter.address,
            value: votes[i].toString(),
          });
        }

        for (let i = 0; i < 3; i++) {
          const voteTx = await election.vote(
            groupAddresses[i],
            new BigNumberJs(votes[i].toString())
          );
          await voteTx.sendAndWaitForReceipt({ from: voter.address });
        }

        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor).deposit({ value: depositAmount });
        await account.setCeloForGroup(groupAddresses[0], firstGroupCapacity);
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await rebalanceDefaultGroups(defaultStrategyContract as any);
        [originalDefaultHead] = await defaultStrategyContract.getGroupsHead();
        [previousOfHead] = await defaultStrategyContract.getGroupPreviousAndNext(
          originalDefaultHead
        );
        originalOverflow = await specificGroupStrategyContract.totalStCeloOverflow();
      });

      describe("When withdrawing amount only from overflow", () => {
        const toWithdraw = parseUnits("5");

        beforeEach(async () => {
          await manager.connect(depositor).withdraw(toWithdraw);
        });

        it("should overflow to default strategy", async () => {
          const [stCeloInStrategy, overflowAmount] =
            await specificGroupStrategyContract.getStCeloInStrategy(groupAddresses[0]);
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
            await defaultStrategyContract.totalStCeloInDefaultStrategy();
          const [, overflow] = await specificGroupStrategyContract.getStCeloInStrategy(
            groupAddresses[0]
          );
          expect(currentDefaultStrategyStCeloBalance).to.deep.eq(overflow);
        });
      });

      describe("When withdrawing amount over overflow", () => {
        const toWithdraw = parseUnits("20");

        beforeEach(async () => {
          await manager.connect(depositor).withdraw(toWithdraw);
        });

        it("should overflow to default strategy", async () => {
          const [stCeloInStrategy, overflowAmount] =
            await specificGroupStrategyContract.getStCeloInStrategy(groupAddresses[0]);
          expect(stCeloInStrategy).to.eq(depositAmount.sub(toWithdraw));
          expect(overflowAmount).to.eq(0);
        });

        it("should schedule withdraw from default specific strategy", async () => {
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
            await defaultStrategyContract.totalStCeloInDefaultStrategy();
          const [, overflow] = await specificGroupStrategyContract.getStCeloInStrategy(
            groupAddresses[0]
          );
          expect(currentDefaultStrategyStCeloBalance).to.deep.eq(overflow);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(
            groupAddresses[i],
            withdrawals[i]
          );
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

      it("should schedule transfers if default strategy => specific strategy", async () => {
        const specificGroupStrategyDeposit = 10;
        const specificGroupStrategyAddress = groupAddresses[2];

        await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
        await manager.connect(depositor2).changeStrategy(specificGroupStrategyAddress);
        await manager.connect(depositor2).deposit({ value: specificGroupStrategyDeposit });

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

    describe("When depositor voted for specific strategy", () => {
      const withdrawals = [40, 50];
      let specificGroupStrategyAddress: string;
      let specificGroupStrategyDeposit: BigNumber;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(
            groupAddresses[i],
            withdrawals[i]
          );
        }

        specificGroupStrategyAddress = groupAddresses[2];
        specificGroupStrategyDeposit = BigNumber.from(100);
        await account.setCeloForGroup(specificGroupStrategyAddress, specificGroupStrategyDeposit);

        await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
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
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
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

      it("should schedule transfers to default if different specific strategy was disallowed", async () => {
        const differentSpecificGroupStrategyDeposit = BigNumber.from(100);
        const differentSpecificGroupStrategyAddress = groupAddresses[0];
        await specificGroupStrategyContract.blockStrategy(specificGroupStrategyAddress);
        await specificGroupStrategyContract.allowStrategy(differentSpecificGroupStrategyAddress);
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
        await specificGroupStrategyContract.allowStrategy(differentSpecificGroupStrategyAddress);
        await manager.connect(depositor2).changeStrategy(differentSpecificGroupStrategyAddress);
        await manager.connect(depositor2).deposit({ value: differentSpecificGroupStrategyDeposit });
        await account.setCeloForGroup(
          differentSpecificGroupStrategyAddress,
          differentSpecificGroupStrategyDeposit.add(withdrawals[0])
        );
        await specificGroupStrategyContract.blockStrategy(differentSpecificGroupStrategyAddress);
        await account.setCeloForGroup(
          differentSpecificGroupStrategyAddress,
          differentSpecificGroupStrategyDeposit
        );

        const [head] = await defaultStrategyContract.getGroupsHead();

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
  });

  describe("#changeStrategy()", () => {
    const withdrawals = [40, 50];
    let specificGroupStrategyAddress: string;

    beforeEach(async () => {
      specificGroupStrategyAddress = groupAddresses[2];
      for (let i = 0; i < 2; i++) {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
        await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
      }
    });

    it("should revert when not valid group", async () => {
      const slashedGroup = groups[0];
      await specificGroupStrategyContract.allowStrategy(slashedGroup.address);
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

    it("should revert when not specific group strategy", async () => {
      await expect(manager.changeStrategy(groupAddresses[0])).revertedWith(
        `GroupNotEligible("${groupAddresses[0]}")`
      );
    });

    describe("When changing with no previous stCelo", () => {
      beforeEach(async () => {
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
      });

      it("should add group to allowed strategies", async () => {
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect([groupAddresses[0]]).to.deep.eq(allowedStrategies);
      });

      it("should change account strategy ", async () => {
        const strategy = await manager.connect(depositor).getAddressStrategy(depositor.address);
        expect(groupAddresses[0]).to.eq(strategy);
      });
    });

    describe("When depositor voted for specific strategy", () => {
      let specificGroupStrategyDeposit: BigNumber;

      beforeEach(async () => {
        specificGroupStrategyDeposit = parseUnits("2");
        await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
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

        await specificGroupStrategyContract.allowStrategy(differentSpecificGroupStrategy);
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

      it("should schedule transfers when changing to specific strategy", async () => {
        const [head] = await defaultStrategyContract.getGroupsHead();
        await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        await specificGroupStrategyContract.allowStrategy(groupAddresses[2]);
        await manager.changeStrategy(groupAddresses[2]);
        await manager.deposit({ value: depositedValue });
        await account.setCeloForGroup(groupAddresses[2], depositedValue);
        await specificGroupStrategyContract.blockStrategy(groupAddresses[2]);
      });

      it("should return correct amount for real and expected", async () => {
        const [expected, real] = await manager.getExpectedAndActualCeloForGroup(groupAddresses[2]);
        expect(expected).to.eq(0);
        expect(real).to.eq(depositedValue);
      });
    });

    describe("When group is deprecated", () => {
      const withdrawals = [50, 50];
      const depositedValue = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }

        await manager.deposit({ value: depositedValue });
        await defaultStrategyContract.deprecateGroup(groupAddresses[0]);
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
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
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

      describe("When group is in both active and allowed", () => {
        const defaultDepositedValue = 100;
        const specificGroupStrategyDepositedValue = 100;

        beforeEach(async () => {
          await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
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
      });
    });

    describe("when groups are close to their voting limit", () => {
      const thirdGroupCapacity = parseUnits("200.166666666666666666");

      beforeEach(async () => {
        // For more info about these numbers check comment above
        const votes = [parseUnits("95824"), parseUnits("143697"), parseUnits("95664")];

        // activating first 2 groups, third is used as specific group
        for (let i = 2; i >= 0; i--) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          if (i < 2) {
            await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
          } else {
            await specificGroupStrategyContract.allowStrategy(groupAddresses[i]);
          }

          await lockedGold.lock().sendAndWaitForReceipt({
            from: voter.address,
            value: votes[i].toString(),
          });
        }

        for (let i = 0; i < 3; i++) {
          const voteTx = await election.vote(
            groupAddresses[i],
            new BigNumberJs(votes[i].toString())
          );
          await voteTx.sendAndWaitForReceipt({ from: voter.address });
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
          const stCeloInDefaultStrategy =
            await defaultStrategyContract.totalStCeloInDefaultStrategy();
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
      await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
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
      await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });

      await specificGroupStrategyContract.allowStrategy(groupAddresses[1]);
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
      await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
      await manager.changeStrategy(groupAddresses[0]);
      await manager.deposit({ value: fromGroupDepositedValue });

      await specificGroupStrategyContract.allowStrategy(groupAddresses[1]);
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
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
        await manager.changeStrategy(groupAddresses[0]);
        await manager.deposit({ value: fromGroupDepositedValue });
        await account.setCeloForGroup(groupAddresses[0], fromGroupDepositedValue + 1);
      });

      it("should revert when toGroup has more Celo than it should", async () => {
        await specificGroupStrategyContract.allowStrategy(groupAddresses[1]);
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
        await specificGroupStrategyContract.allowStrategy(groupAddresses[1]);
        await manager.connect(depositor2).changeStrategy(groupAddresses[1]);
        await manager.connect(depositor2).deposit({ value: toGroupDepositedValue });
        await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue);

        await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
          `RebalanceEnoughCelo("${groupAddresses[1]}", ${toGroupDepositedValue}, ${toGroupDepositedValue})`
        );
      });

      describe("When toGroup has valid properties", () => {
        beforeEach(async () => {
          await specificGroupStrategyContract.allowStrategy(groupAddresses[1]);
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
              const [head] = await defaultStrategyContract.getGroupsHead();
              await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            }
            await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue);

            await specificGroupStrategyContract.blockStrategy(groupAddresses[0]);
            await specificGroupStrategyContract.blockStrategy(groupAddresses[1]);
          });

          it("should schedule transfer from deprecated group", async () => {
            await defaultStrategyContract.deprecateGroup(groupAddresses[0]);
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

          it("should revert when rebalance to deprecated group", async () => {
            await defaultStrategyContract.deprecateGroup(groupAddresses[1]);
            await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
              `InvalidToGroup("${groupAddresses[1]}")`
            );
          });
        });

        describe("When having different active groups", () => {
          beforeEach(async () => {
            for (let i = 2; i < 4; i++) {
              const [head] = await defaultStrategyContract.getGroupsHead();
              await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);
            }
          });

          it("should schedule transfer from disspecific strategy", async () => {
            await specificGroupStrategyContract.blockStrategy(groupAddresses[0]);
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
            await specificGroupStrategyContract.blockStrategy(groupAddresses[1]);
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

  describe("#transferBetweenStrategies()", () => {
    it("should revert when not called by strategy", async () => {
      await expect(
        manager.connect(depositor).transferBetweenStrategies(ADDRESS_ZERO, ADDRESS_ZERO, 0)
      ).revertedWith(`CallerNotStrategy("${depositor.address}")`);
    });

    describe("When active groups", () => {
      let specificGroupAddress: string;
      let currentHead: string;
      let currentTail: string;
      beforeEach(async () => {
        let nextGroup = ADDRESS_ZERO;
        for (let i = 0; i < 3; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, nextGroup);
          nextGroup = groupAddresses[i];
        }

        await manager.deposit({ value: 100 });
        specificGroupAddress = groupAddresses[7];
        [currentHead] = await defaultStrategyContract.getGroupsHead();
        [currentTail] = await defaultStrategyContract.getGroupsTail();
      });

      it("should schedule votes from default -> specific", async () => {
        const strategyAddress = await manager.defaultStrategy();
        await depositor.sendTransaction({ to: strategyAddress, value: parseUnits("10") });
        const strategySigner = await getImpersonatedSigner(strategyAddress);
        await manager
          .connect(strategySigner)
          .transferBetweenStrategies(ADDRESS_ZERO, specificGroupAddress, 100);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.have.deep.members([currentHead]);
        expect(lastTransferFromVotes).to.deep.eq([BigNumber.from(100)]);

        expect(lastTransferToGroups).to.have.deep.members([specificGroupAddress]);
        expect(lastTransferToVotes).to.deep.eq([BigNumber.from(100)]);
      });

      it("should schedule votes from specific -> default", async () => {
        const strategyAddress = await manager.defaultStrategy();
        await depositor.sendTransaction({ to: strategyAddress, value: parseUnits("10") });
        const strategySigner = await getImpersonatedSigner(strategyAddress);

        await specificGroupStrategyContract.allowStrategy(specificGroupAddress);
        await manager.connect(depositor).changeStrategy(specificGroupAddress);
        await manager.connect(depositor).deposit({ value: 100 });

        await manager
          .connect(strategySigner)
          .transferBetweenStrategies(specificGroupAddress, ADDRESS_ZERO, 100);

        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.have.deep.members([specificGroupAddress]);
        expect(lastTransferFromVotes).to.deep.eq([BigNumber.from(100)]);

        expect(lastTransferToGroups).to.have.deep.members([currentTail]);
        expect(lastTransferToVotes).to.deep.eq([BigNumber.from(100)]);
      });
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
        // For more info about these numbers check comment above
        const votes = [parseUnits("95824"), parseUnits("143697"), parseUnits("95664")];

        for (let i = 2; i >= 0; i--) {
          const [head] = await defaultStrategyContract.getGroupsHead();
          await defaultStrategyContract.activateGroup(groupAddresses[i], ADDRESS_ZERO, head);

          await lockedGold.lock().sendAndWaitForReceipt({
            from: voter.address,
            value: votes[i].toString(),
          });
        }

        for (let i = 0; i < 3; i++) {
          const voteTx = await election.vote(
            groupAddresses[i],
            new BigNumberJs(votes[i].toString())
          );
          await voteTx.sendAndWaitForReceipt({ from: voter.address });
        }
      });

      it("should return correct amount of receivable votes", async () => {
        const receivableAmount = await manager.getReceivableVotesForGroup(groupAddresses[0]);
        expect(receivableAmount).to.eq(firstGroupCapacity);
      });

      describe("When having some votes scheduled", () => {
        let scheduledVotes: BigNumber;
        beforeEach(async () => {
          scheduledVotes = parseUnits("2");
          await account.setScheduledVotes(groupAddresses[0], scheduledVotes);
        });

        it("should return correct amount", async () => {
          const receivableAmount = await manager.getReceivableVotesForGroup(groupAddresses[0]);
          expect(receivableAmount).to.eq(firstGroupCapacity.sub(scheduledVotes));
        });
      });
    });
  });
});
