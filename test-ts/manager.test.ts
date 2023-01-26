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
import { MockDefaultStrategyFull } from "../typechain-types/MockDefaultStrategyFull";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { MockLockedGold } from "../typechain-types/MockLockedGold";
import { MockRegistry } from "../typechain-types/MockRegistry";
import { MockStakedCelo } from "../typechain-types/MockStakedCelo";
import { MockValidators } from "../typechain-types/MockValidators";
import { MockVote } from "../typechain-types/MockVote";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import electionContractData from "./code/abi/electionAbi.json";
import {
  ADDRESS_ZERO,
  deregisterValidatorGroup,
  electGroup,
  electMockValidatorGroupsAndUpdate,
  getImpersonatedSigner,
  impersonateAccount,
  mineToNextEpoch,
  randomSigner,
  registerValidatorAndAddToGroupMembers,
  registerValidatorAndOnlyAffiliateToGroup,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
  removeMembersFromGroup,
  resetNetwork,
  revokeElectionOnMockValidatorGroupsAndUpdate,
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
  let defaultStrategyContract: MockDefaultStrategyFull;
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
      defaultStrategyContract = await hre.ethers.getContract("MockDefaultStrategyFull");

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

      await manager.setDependencies(
        stakedCelo.address,
        account.address,
        voteContract.address,
        groupHealthContract.address,
        specificGroupStrategyContract.address,
        defaultStrategyContract.address
      );
      await groupHealthContract.setDependencies(
        stakedCelo.address,
        account.address,
        specificGroupStrategyContract.address,
        defaultStrategyContract.address,
        manager.address
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

  describe("#activateGroup()", () => {
    it("adds a group", async () => {
      await defaultStrategyContract.activateGroup(groupAddresses[0]);
      const activeGroups = await defaultStrategyContract.getGroups();
      const activeGroupsLength = await defaultStrategyContract.getGroupsLength();
      const firstActiveGroup = await defaultStrategyContract.getGroup(0);
      expect(activeGroups).to.deep.eq([groupAddresses[0]]);
      expect(activeGroupsLength).to.eq(1);
      expect(firstActiveGroup).to.eq(groupAddresses[0]);
    });

    it("emits a GroupActivated event", async () => {
      await expect(defaultStrategyContract.activateGroup(groupAddresses[0]))
        .to.emit(defaultStrategyContract, "GroupActivated")
        .withArgs(groupAddresses[0]);
    });

    it("cannot be called by a non owner", async () => {
      await expect(
        defaultStrategyContract.connect(nonOwner).activateGroup(groupAddresses[0])
      ).revertedWith("Ownable: caller is not the owner");
    });

    describe("when group is not registered", () => {
      it("reverts when trying to add an unregistered group", async () => {
        const [unregisteredGroup] = await randomSigner(parseUnits("100"));
        await expect(defaultStrategyContract.activateGroup(unregisteredGroup.address)).revertedWith(
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
        await expect(defaultStrategyContract.activateGroup(noMemberedGroup.address)).revertedWith(
          `GroupNotEligible("${noMemberedGroup.address}")`
        );
      });
    });

    describe("when group is not elected", () => {
      it("reverts when trying to add non elected group", async () => {
        const nonElectedGroup = groups[10];
        await mineToNextEpoch(hre.web3);
        await revokeElectionOnMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          nonElectedGroup.address,
        ]);
        await expect(defaultStrategyContract.activateGroup(nonElectedGroup.address)).revertedWith(
          `GroupNotEligible("${nonElectedGroup.address}")`
        );
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
        await groupHealthContract.updateGroupHealth(validatorGroupWithThreeValidators.address, [
          Number.MAX_SAFE_INTEGER.toString(),
          Number.MAX_SAFE_INTEGER.toString(),
          electedValidatorIndex,
        ]);
      });

      it("emits a GroupActivated event", async () => {
        await expect(
          defaultStrategyContract.activateGroup(validatorGroupWithThreeValidators.address)
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
        await expect(defaultStrategyContract.activateGroup(slashedGroup.address)).revertedWith(
          `GroupNotEligible("${slashedGroup.address}")`
        );
      });
    });

    describe("when some groups are already added", () => {
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
        }
      });

      it("adds another group", async () => {
        await defaultStrategyContract.activateGroup(groupAddresses[3]);
        const activeGroups = await defaultStrategyContract.getGroups();
        expect(activeGroups).to.deep.eq(groupAddresses.slice(0, 4));
      });

      it("emits a GroupActivated event", async () => {
        await expect(defaultStrategyContract.activateGroup(groupAddresses[3]))
          .to.emit(defaultStrategyContract, "GroupActivated")
          .withArgs(groupAddresses[3]);
      });

      it("reverts when trying to add an existing group", async () => {
        await expect(defaultStrategyContract.activateGroup(groupAddresses[1])).revertedWith(
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
          await defaultStrategyContract.activateGroup(groups[i].address);
        }
      });

      it("cannot add another group", async () => {
        await expect(defaultStrategyContract.activateGroup(additionalGroup.address)).revertedWith(
          "MaxGroupsVotedForReached()"
        );
      });

      it("can add another group when enabled in Election contract", async () => {
        const accountAddress = account.address;
        const sendFundsTx = await nonOwner.sendTransaction({
          value: parseUnits("1"),
          to: accountAddress,
        });
        await sendFundsTx.wait();
        await impersonateAccount(accountAddress);

        const accountsContract = await hre.kit.contracts.getAccounts();
        const createAccountTxObject = accountsContract.createAccount();
        await createAccountTxObject.send({
          from: accountAddress,
        });
        // TODO: once contractkit updated - use just election contract from contractkit
        const electionContract = new hre.kit.web3.eth.Contract(
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          electionContractData.abi as any,
          election.address
        );
        const setAllowedToVoteOverMaxNumberOfGroupsTxObject =
          electionContract.methods.setAllowedToVoteOverMaxNumberOfGroups(true);
        await setAllowedToVoteOverMaxNumberOfGroupsTxObject.send({
          from: accountAddress,
        });

        await expect(defaultStrategyContract.activateGroup(additionalGroup.address))
          .to.emit(defaultStrategyContract, "GroupActivated")
          .withArgs(additionalGroup.address);
      });

      describe("when some of the groups are currently deprecated", () => {
        beforeEach(async () => {
          // await account.setCeloForGroup(groupAddresses[2], 100);
          await manager.deposit({ value: 1000 });
          // await account.setCeloForGroup(groupAddresses[7], 100);
          await defaultStrategyContract.deprecateGroup(groupAddresses[2]);
          await defaultStrategyContract.deprecateGroup(groupAddresses[7]);
        });

        it("cannot add another group", async () => {
          await expect(defaultStrategyContract.activateGroup(additionalGroup.address)).revertedWith(
            "MaxGroupsVotedForReached()"
          );
        });

        it("reactivates a deprecated group", async () => {
          await defaultStrategyContract.activateGroup(groupAddresses[2]);
          const activeGroups = await defaultStrategyContract.getGroups();
          expect(activeGroups[8]).to.equal(groupAddresses[2]);
        });

        it("emits a GroupActivated event", async () => {
          await expect(defaultStrategyContract.activateGroup(groupAddresses[2]))
            .to.emit(defaultStrategyContract, "GroupActivated")
            .withArgs(groupAddresses[2]);
        });

        it("removes the group from deprecated", async () => {
          await defaultStrategyContract.activateGroup(groupAddresses[2]);
          const deprecatedGroups = await defaultStrategyContract.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.equal([groupAddresses[7]]);
        });
      });
    });
  });

  describe("#allowStrategy()", () => {
    it("adds a strategy", async () => {
      await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
      const specificGroupStrategy =
        await specificGroupStrategyContract.getSpecificGroupStrategies();
      const specificGroupStrategyLength =
        await specificGroupStrategyContract.getSpecificGroupStrategiesLength();
      const firstSpecificGroupStrategy =
        await specificGroupStrategyContract.getSpecificGroupStrategy(0);
      expect(specificGroupStrategy).to.deep.eq([groupAddresses[0]]);
      expect(specificGroupStrategyLength).to.eq(1);
      expect(firstSpecificGroupStrategy).to.eq(groupAddresses[0]);
    });

    it("emits a StrategyAllowed event", async () => {
      await expect(specificGroupStrategyContract.allowStrategy(groupAddresses[0]))
        .to.emit(specificGroupStrategyContract, "StrategyAllowed")
        .withArgs(groupAddresses[0]);
    });

    it("cannot be called by a non owner", async () => {
      await expect(
        specificGroupStrategyContract.connect(nonOwner).allowStrategy(groupAddresses[0])
      ).revertedWith("Ownable: caller is not the owner");
    });

    describe("when strategy is not registered", () => {
      it("reverts when trying to add an unregistered group", async () => {
        const [unregisteredGroup] = await randomSigner(parseUnits("100"));

        await expect(
          specificGroupStrategyContract.allowStrategy(unregisteredGroup.address)
        ).revertedWith(`StrategyNotEligible("${unregisteredGroup.address}")`);
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

      it("reverts when trying to add a strategy with no members", async () => {
        await expect(
          specificGroupStrategyContract.allowStrategy(noMemberedGroup.address)
        ).revertedWith(`StrategyNotEligible("${noMemberedGroup.address}")`);
      });
    });

    describe("when group is not elected", () => {
      it("reverts when trying to add non elected group", async () => {
        const nonElectedGroup = groups[10];
        await mineToNextEpoch(hre.web3);
        await revokeElectionOnMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          groups[10].address,
        ]);
        await expect(
          specificGroupStrategyContract.allowStrategy(nonElectedGroup.address)
        ).revertedWith(`StrategyNotEligible("${nonElectedGroup.address}")`);
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
        await groupHealthContract.updateGroupHealth(validatorGroupWithThreeValidators.address, [
          Number.MAX_SAFE_INTEGER.toString(),
          Number.MAX_SAFE_INTEGER.toString(),
          electedValidatorIndex,
        ]);
        await defaultStrategyContract.activateGroup(validatorGroupWithThreeValidators.address);
      });

      it("emits a StrategyAllowed event", async () => {
        await expect(
          specificGroupStrategyContract.allowStrategy(validatorGroupWithThreeValidators.address)
        )
          .to.emit(specificGroupStrategyContract, "StrategyAllowed")
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
          specificGroupStrategyContract.allowStrategy(slashedGroup.address)
        ).revertedWith(`StrategyNotEligible("${slashedGroup.address}")`);
      });
    });
    describe("when maxNumGroupsVotedFor have been voted for", async () => {
      let additionalGroup: SignerWithAddress;

      beforeEach(async () => {
        additionalGroup = groups[10];
        await electGroup(additionalGroup.address, someone);

        for (let i = 0; i < 10; i++) {
          await defaultStrategyContract.activateGroup(groups[i].address);
        }
      });
    });
  });

  describe("#deprecateGroup()", () => {
    let deprecatedGroup: SignerWithAddress;

    describe("When 3 active groups", () => {
      beforeEach(async () => {
        deprecatedGroup = groups[1];
        for (let i = 0; i < 3; i++) {
          await defaultStrategyContract.activateGroup(groups[i].address);
        }
      });

      describe("when the group is voted for", () => {
        beforeEach(async () => {
          await manager.deposit({ value: 100 });
        });

        it("removes the group from the groups array", async () => {
          await defaultStrategyContract.deprecateGroup(deprecatedGroup.address);
          const activeGroups = await defaultStrategyContract.getGroups();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[2]]);
        });

        it("adds the group to the deprecated array", async () => {
          await defaultStrategyContract.deprecateGroup(deprecatedGroup.address);
          const deprecatedGroups = await defaultStrategyContract.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([groupAddresses[1]]);
        });

        it("emits a GroupDeprecated event", async () => {
          await expect(defaultStrategyContract.deprecateGroup(deprecatedGroup.address))
            .to.emit(defaultStrategyContract, "GroupDeprecated")
            .withArgs(deprecatedGroup.address);
        });

        it("reverts when deprecating a non active group", async () => {
          await expect(defaultStrategyContract.deprecateGroup(groupAddresses[3])).revertedWith(
            `GroupNotActive("${groupAddresses[3]}")`
          );
        });

        it("cannot be called by a non owner", async () => {
          await expect(
            defaultStrategyContract.connect(nonOwner).deprecateGroup(deprecatedGroup.address)
          ).revertedWith("Ownable: caller is not the owner");
        });
      });

      describe("when the group is not voted for", () => {
        it("removes the group from the groups array", async () => {
          await defaultStrategyContract.deprecateGroup(deprecatedGroup.address);
          const activeGroups = await defaultStrategyContract.getGroups();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[2]]);
        });

        it("does not add the group to the deprecated array", async () => {
          await defaultStrategyContract.deprecateGroup(deprecatedGroup.address);
          const deprecatedGroups = await defaultStrategyContract.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([]);
        });

        it("emits a GroupDeprecated event", async () => {
          await expect(defaultStrategyContract.deprecateGroup(deprecatedGroup.address))
            .to.emit(defaultStrategyContract, "GroupDeprecated")
            .withArgs(deprecatedGroup.address);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(defaultStrategyContract.deprecateGroup(deprecatedGroup.address))
            .to.emit(defaultStrategyContract, "GroupRemoved")
            .withArgs(deprecatedGroup.address);
        });

        it("reverts when deprecating a non active group", async () => {
          await expect(defaultStrategyContract.deprecateGroup(groupAddresses[3])).revertedWith(
            `GroupNotActive("${groupAddresses[3]}")`
          );
        });

        it("cannot be called by a non owner", async () => {
          await expect(
            defaultStrategyContract.connect(nonOwner).deprecateGroup(deprecatedGroup.address)
          ).revertedWith("Ownable: caller is not the owner");
        });
      });
    });
  });

  describe("#blockStrategy()", () => {
    it("reverts when no active groups", async () => {
      await specificGroupStrategyContract.allowStrategy(groupAddresses[3]);
      await expect(specificGroupStrategyContract.blockStrategy(groupAddresses[3])).revertedWith(
        `NoActiveGroups()`
      );
    });

    describe("When 2 active groups", () => {
      let specificGroupStrategy: SignerWithAddress;
      beforeEach(async () => {
        specificGroupStrategy = groups[2];
        for (let i = 0; i < 2; i++) {
          await defaultStrategyContract.activateGroup(groups[i].address);
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
          await specificGroupStrategyContract.allowStrategy(specificGroupStrategy.address);
          await manager.connect(depositor).changeStrategy(specificGroupStrategy.address);
          await manager.connect(depositor).deposit({ value: specificGroupStrategyDeposit });
        });

        it("added group to allowed strategies", async () => {
          const activeGroups = await defaultStrategyContract.connect(depositor).getGroups();
          const deprecatedGroups = await defaultStrategyContract
            .connect(depositor)
            .getDeprecatedGroups();
          const allowedStrategies = await specificGroupStrategyContract
            .connect(depositor)
            .getSpecificGroupStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(deprecatedGroups).to.deep.eq([]);
          expect(allowedStrategies).to.deep.eq([specificGroupStrategy.address]);
        });

        it("removes the group from the groups array", async () => {
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
          const activeGroups = await defaultStrategyContract.connect(depositor).getGroups();
          const deprecatedGroups = await defaultStrategyContract
            .connect(depositor)
            .getDeprecatedGroups();
          const allowedStrategies = await specificGroupStrategyContract
            .connect(depositor)
            .getSpecificGroupStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(deprecatedGroups).to.deep.eq([]);
          expect(allowedStrategies).to.deep.eq([]);
        });

        it("emits a StrategyBlocked event", async () => {
          await expect(specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address))
            .to.emit(specificGroupStrategyContract, "StrategyBlocked")
            .withArgs(specificGroupStrategy.address);
        });

        it("reverts when blocking already blocked strategy", async () => {
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
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
          const [
            lastTransferFromGroups,
            lastTransferFromVotes,
            lastTransferToGroups,
            lastTransferToVotes,
          ] = await account.getLastTransferValues();

          expect(lastTransferFromGroups).to.deep.eq([specificGroupStrategy.address]);
          expect(lastTransferFromVotes).to.deep.eq([specificGroupStrategyDeposit]);

          expect(lastTransferToGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(lastTransferToVotes.length).to.eq(2);
          expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).to.deep.eq(
            specificGroupStrategyDeposit
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
        await defaultStrategyContract.activateGroup(groups[i].address);
      }
    });

    it("should revert when group is healthy", async () => {
      await expect(defaultStrategyContract.deprecateUnhealthyGroup(groupAddresses[1])).revertedWith(
        `HealthyGroup("${groupAddresses[1]}")`
      );
    });

    describe("when the group is not elected", () => {
      beforeEach(async () => {
        await mineToNextEpoch(hre.web3);
        await revokeElectionOnMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          groupAddresses[1],
        ]);
      });

      it("should deprecate group", async () => {
        await expect(await defaultStrategyContract.deprecateUnhealthyGroup(groupAddresses[1]))
          .to.emit(defaultStrategyContract, "GroupDeprecated")
          .withArgs(groupAddresses[1]);
      });
    });

    describe("when the group is not registered", () => {
      beforeEach(async () => {
        await deregisterValidatorGroup(deprecatedGroup);
        await mineToNextEpoch(hre.web3);
        await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          deprecatedGroup.address,
        ]);
      });

      it("should deprecate group", async () => {
        await expect(await defaultStrategyContract.deprecateUnhealthyGroup(deprecatedGroup.address))
          .to.emit(defaultStrategyContract, "GroupDeprecated")
          .withArgs(deprecatedGroup.address);
      });
    });

    describe("when the group has no members", () => {
      // if voting for a group that has no members, i get no rewards.
      beforeEach(async () => {
        await removeMembersFromGroup(deprecatedGroup);
        await mineToNextEpoch(hre.web3);
        await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          deprecatedGroup.address,
        ]);
      });

      it("should deprecate group", async () => {
        await expect(await defaultStrategyContract.deprecateUnhealthyGroup(deprecatedGroup.address))
          .to.emit(defaultStrategyContract, "GroupDeprecated")
          .withArgs(deprecatedGroup.address);
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
        await groupHealthContract.updateGroupHealth(validatorGroupWithThreeValidators.address, [
          Number.MAX_SAFE_INTEGER.toString(),
          Number.MAX_SAFE_INTEGER.toString(),
          electedValidatorIndex,
        ]);
        await defaultStrategyContract.activateGroup(validatorGroupWithThreeValidators.address);
      });

      it("should revert with Healthy group message", async () => {
        await expect(
          defaultStrategyContract.deprecateUnhealthyGroup(validatorGroupWithThreeValidators.address)
        ).revertedWith(`HealthyGroup("${validatorGroupWithThreeValidators.address}")`);
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
        await mineToNextEpoch(hre.web3);
        await electMockValidatorGroupsAndUpdate(validators, groupHealthContract, [
          deprecatedGroup.address,
        ]);
      });

      it("should deprecate group", async () => {
        await expect(await defaultStrategyContract.deprecateUnhealthyGroup(deprecatedGroup.address))
          .to.emit(defaultStrategyContract, "GroupDeprecated")
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
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
          await defaultStrategyContract.deprecateGroup(groupAddresses[1]);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], votes[i]);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(
            groupAddresses[i],
            votes[i]
          );
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
          await defaultStrategyContract.deprecateGroup(groupAddresses[0]);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);

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
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor).deposit({ value: 100 });
      });

      it("should add group to allowed strategies", async () => {
        const activeGroups = await defaultStrategyContract.connect(depositor).getGroups();
        const deprecatedGroups = await defaultStrategyContract
          .connect(depositor)
          .getDeprecatedGroups();
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
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

        await manager.connect(depositor).deposit({ value: 100 });
      });

      it("should not add group to allowed strategies", async () => {
        const activeGroups = await defaultStrategyContract.connect(depositor).getGroups();
        const deprecatedGroups = await defaultStrategyContract
          .connect(depositor)
          .getDeprecatedGroups();
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
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
            await defaultStrategyContract.activateGroup(groupAddresses[i]);
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
          await manager.deposit({ value: secondDepositedValue });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect([groupAddresses[0], groupAddresses[1]]).to.deep.eq(votedGroups);
          expect(2).to.eq(votes.length);
          expect(secondDepositedValue).to.eq(votes[0].add(votes[1]));
        });
      });

      describe("Block strategy - group one of active", () => {
        beforeEach(async () => {
          for (let i = 0; i < 3; i++) {
            await defaultStrategyContract.activateGroup(groupAddresses[i]);
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
          await manager.deposit({ value: secondDepositedValue });
          const [votedGroups, votes] = await account.getLastScheduledVotes();
          expect([groupAddresses[1], groupAddresses[2], groupAddresses[0]]).to.deep.eq(votedGroups);
          expect(3).to.eq(votes.length);
          expect(secondDepositedValue).to.eq(votes[0].add(votes[1]).add(votes[2]));
        });
      });
    });

    describe("When we have 2 active validator groups", () => {
      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
        }
      });

      describe("When voted for allowed validator group which is not in active groups", () => {
        beforeEach(async () => {
          await specificGroupStrategyContract.allowStrategy(groupAddresses[2]);
          await manager.connect(depositor).changeStrategy(groupAddresses[2]);
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should add group to allowed strategies", async () => {
          const activeGroups = await defaultStrategyContract.connect(depositor).getGroups();
          const deprecatedGroups = await defaultStrategyContract
            .connect(depositor)
            .getDeprecatedGroups();
          const allowedStrategies = await specificGroupStrategyContract
            .connect(depositor)
            .getSpecificGroupStrategies();
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
        let specificGroupStrategyAddress: string;
        beforeEach(async () => {
          specificGroupStrategyAddress = groupAddresses[0];
          await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
          await manager.connect(depositor).changeStrategy(specificGroupStrategyAddress);
          await manager.connect(depositor).deposit({ value: 100 });
        });

        it("should add group to allowed strategies", async () => {
          const activeGroups = await defaultStrategyContract.connect(depositor).getGroups();
          const deprecatedGroups = await defaultStrategyContract
            .connect(depositor)
            .getDeprecatedGroups();
          const allowedStrategies = await specificGroupStrategyContract
            .connect(depositor)
            .getSpecificGroupStrategies();
          expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
          expect(deprecatedGroups).to.deep.eq([]);
          expect(allowedStrategies).to.deep.eq([specificGroupStrategyAddress]);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(groupAddresses[i], 100);
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
          await defaultStrategyContract.deprecateGroup(groupAddresses[1]);
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
          const deprecatedGroups = await defaultStrategyContract.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([]);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(manager.connect(depositor).withdraw(120))
            .to.emit(defaultStrategyContract, "GroupRemoved")
            .withArgs(groupAddresses[1]);
        });
      });
    });

    describe("when all groups have equal votes and one of the groups was voted for as for allowed group", () => {
      let specificGroupStrategy: SignerWithAddress;
      beforeEach(async () => {
        specificGroupStrategy = groups[0];
        const specificGroupStrategyWithdrawal = 100;
        for (let i = 0; i < 3; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(groupAddresses[i], 100);
        }

        await account.setCeloForGroup(
          specificGroupStrategy.address,
          100 + specificGroupStrategyWithdrawal
        );

        await specificGroupStrategyContract.allowStrategy(specificGroupStrategy.address);
        await manager.connect(depositor2).changeStrategy(specificGroupStrategy.address);
        await manager.connect(depositor2).deposit({ value: specificGroupStrategyWithdrawal });

        await stakedCelo.mint(depositor.address, 300);
        await account.setTotalCelo(300 + specificGroupStrategyWithdrawal);
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
          await defaultStrategyContract.deprecateGroup(groupAddresses[1]);
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
          const deprecatedGroups = await defaultStrategyContract.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([]);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(manager.connect(depositor).withdraw(120))
            .to.emit(defaultStrategyContract, "GroupRemoved")
            .withArgs(groupAddresses[1]);
        });
      });

      describe("when active group is deprecated", () => {
        beforeEach(async () => {
          await defaultStrategyContract.deprecateGroup(groups[0].address);
        });

        it("withdraws a small withdrawal from the deprecated group only", async () => {
          await manager.connect(depositor).withdraw(30);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([specificGroupStrategy.address]);
          expect(withdrawals).to.deep.equal([BigNumber.from("30")]);
        });

        it("withdraws a larger withdrawal from the deprecated group first, then the remaining groups", async () => {
          await manager.connect(depositor).withdraw(220);
          const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal([
            specificGroupStrategy.address,
            groupAddresses[2],
            groupAddresses[1],
          ]);
          expect(withdrawals).to.deep.equal([
            BigNumber.from("100"),
            BigNumber.from("60"),
            BigNumber.from("60"),
          ]);
        });

        it("removes the deprecated group if it is no longer voted for", async () => {
          await manager.connect(depositor).withdraw(220);
          const deprecatedGroups = await defaultStrategyContract.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([]);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(manager.connect(depositor).withdraw(220))
            .to.emit(defaultStrategyContract, "GroupRemoved")
            .withArgs(specificGroupStrategy.address);
        });
      });
    });

    describe("when groups have unequal votes", () => {
      const withdrawals = [40, 100, 30];
      beforeEach(async () => {
        for (let i = 0; i < 3; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(
            groupAddresses[i],
            withdrawals[i]
          );
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
          await defaultStrategyContract.deprecateGroup(groupAddresses[0]);
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
          const deprecatedGroups = await defaultStrategyContract.getDeprecatedGroups();
          expect(deprecatedGroups).to.deep.eq([]);
        });

        it("emits a GroupRemoved event", async () => {
          await expect(manager.connect(depositor).withdraw(40))
            .to.emit(defaultStrategyContract, "GroupRemoved")
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], 100);
          await defaultStrategyContract.addToStrategyTotalStCeloVotesPublic(groupAddresses[i], 100);
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
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
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
          `GroupNotBalancedOrNotEnoughStCelo("${groupAddresses[0]}", 110, 100)`
        );
      });
    });

    describe("When there are other active groups besides allowed validator group - allowed is different from active", () => {
      const withdrawals = [40, 50];
      const specificGroupStrategyWithdrawal = 100;
      let specificGroupStrategy: SignerWithAddress;

      beforeEach(async () => {
        specificGroupStrategy = groups[2];
        for (let i = 0; i < 2; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
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
        const activeGroups = await defaultStrategyContract.connect(depositor).getGroups();
        const deprecatedGroups = await defaultStrategyContract
          .connect(depositor)
          .getDeprecatedGroups();
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect(activeGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(deprecatedGroups).to.deep.eq([]);
        expect(allowedStrategies).to.deep.eq([specificGroupStrategy.address]);
      });

      it("should withdraw less than originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(60);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect(withdrawnGroups).to.deep.equal([specificGroupStrategy.address]);
        expect(withdrawals).to.deep.equal([BigNumber.from("60")]);
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect(allowedStrategies).to.deep.eq([specificGroupStrategy.address]);
      });

      it("should withdraw same amount as originally deposited from allowed group", async () => {
        await manager.connect(depositor).withdraw(100);
        const [withdrawnGroups, withdrawals] = await account.getLastScheduledWithdrawals();
        expect([specificGroupStrategy.address]).to.deep.equal(withdrawnGroups);
        expect([BigNumber.from("100")]).to.deep.equal(withdrawals);
        const deprecatedGroups = await defaultStrategyContract
          .connect(depositor)
          .getDeprecatedGroups();
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect([specificGroupStrategy.address]).to.deep.eq(allowedStrategies);
        expect([]).to.deep.eq(deprecatedGroups);
      });

      it("should withdraw same amount as originally deposited from active groups after strategy is disallowed", async () => {
        await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
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
        const allowedStrategies = await specificGroupStrategyContract
          .connect(depositor)
          .getSpecificGroupStrategies();
        expect(allowedStrategies).to.deep.eq([]);
      });

      it("should revert when withdraw more amount than originally deposited from allowed group", async () => {
        await expect(manager.connect(depositor).withdraw(110)).revertedWith(
          `GroupNotBalancedOrNotEnoughStCelo("${specificGroupStrategy.address}", 110, 100)`
        );
      });

      describe("When strategy blocked", () => {
        beforeEach(async () => {
          await specificGroupStrategyContract.blockStrategy(specificGroupStrategy.address);
        });

        it("should revert since groups are not rebalanced", async () => {
          await expect(
            manager.connect(depositor).withdraw(specificGroupStrategyWithdrawal)
          ).revertedWith(`CantWithdrawAccordingToStrategy("${ADDRESS_ZERO}")`);
        });

        it('should withdraw correctly after "rebalance"', async () => {
          await account.setCeloForGroup(
            groupAddresses[0],
            withdrawals[0] + specificGroupStrategyWithdrawal / 2
          );
          await account.setCeloForGroup(
            groupAddresses[1],
            withdrawals[1] + specificGroupStrategyWithdrawal / 2
          );
          await manager.connect(depositor).withdraw(specificGroupStrategyWithdrawal);

          const [withdrawnGroups, groupWithdrawals] = await account.getLastScheduledWithdrawals();
          expect(withdrawnGroups).to.deep.equal(groupAddresses.slice(0, 2));
          expect(groupWithdrawals.length).to.eq(2);
          expect(groupWithdrawals[0].add(groupWithdrawals[1])).to.eq(
            specificGroupStrategyWithdrawal
          );
        });
      });
    });

    describe("When there are other active groups besides allowed validator group - allowed is one of the active groups", () => {
      const withdrawals = [40, 50];
      const specificGroupStrategyWithdrawal = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
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
          .setDependencies(
            ADDRESS_ZERO,
            nonAccount.address,
            nonVote.address,
            nonVote.address,
            nonVote.address,
            nonVote.address
          )
      ).revertedWith("AddressZeroNotAllowed()");
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
      ).revertedWith("AddressZeroNotAllowed()");
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
      ).revertedWith("AddressZeroNotAllowed()");
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
      ).revertedWith("AddressZeroNotAllowed()");
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
      ).revertedWith("AddressZeroNotAllowed()");
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
      ).revertedWith("AddressZeroNotAllowed()");
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
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

        await account.setCeloForGroup(groupAddresses[0], defaultGroupDeposit.div(2));

        await account.setCeloForGroup(groupAddresses[1], defaultGroupDeposit.div(2));

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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
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

      it("should not schedule any transfers if second account also voted for same allowed group", async () => {
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

        expect(lastTransferToGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(lastTransferToVotes.length).to.eq(2);
        expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).to.eq(
          specificGroupStrategyDeposit
        );
      });

      it("should schedule transfers if specific strategy => different specific strategy", async () => {
        const differentSpecificGroupStrategyDeposit = parseUnits("1");
        await account.setCeloForGroup(groupAddresses[0], differentSpecificGroupStrategyDeposit);
        await specificGroupStrategyContract.allowStrategy(groupAddresses[0]);
        await manager.connect(depositor2).changeStrategy(groupAddresses[0]);
        await manager.connect(depositor2).deposit({ value: differentSpecificGroupStrategyDeposit });

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

        expect(lastTransferToGroups).to.deep.eq([groupAddresses[1], groupAddresses[0]]);
        expect(lastTransferToVotes.length).to.eq(2);
        expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).to.eq(
          specificGroupStrategyDeposit
        );
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

        await account.setCeloForGroup(
          groupAddresses[0],
          differentSpecificGroupStrategyDeposit.div(2)
        );

        await account.setCeloForGroup(
          groupAddresses[1],
          differentSpecificGroupStrategyDeposit.div(2)
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

        expect(lastTransferFromGroups).to.have.deep.members([groupAddresses[1], groupAddresses[0]]);
        expect(lastTransferFromVotes.length).to.eq(2);
        expect(lastTransferFromVotes[0].add(lastTransferFromVotes[1])).to.deep.eq(
          differentSpecificGroupStrategyDeposit
        );

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
        await defaultStrategyContract.activateGroup(groupAddresses[i]);
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

    it("should revert when not allowed group", async () => {
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
        await manager.changeStrategy(ADDRESS_ZERO);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([specificGroupStrategyAddress]);
        expect(lastTransferFromVotes).to.deep.eq([specificGroupStrategyDeposit]);

        expect(lastTransferToGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(lastTransferToVotes.length).to.eq(2);
        expect(lastTransferToVotes[0].add(lastTransferToVotes[1])).eq(specificGroupStrategyDeposit);
      });
    });

    describe("When depositor voted for default strategy", () => {
      let defaultGroupDeposit: BigNumber;

      beforeEach(async () => {
        defaultGroupDeposit = parseUnits("2");
        await manager.deposit({ value: defaultGroupDeposit });
        await account.setCeloForGroup(groupAddresses[0], defaultGroupDeposit.div(2));
        await account.setCeloForGroup(groupAddresses[1], defaultGroupDeposit.div(2));
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
        await specificGroupStrategyContract.allowStrategy(specificGroupStrategyAddress);
        await manager.changeStrategy(specificGroupStrategyAddress);
        const [
          lastTransferFromGroups,
          lastTransferFromVotes,
          lastTransferToGroups,
          lastTransferToVotes,
        ] = await account.getLastTransferValues();

        expect(lastTransferFromGroups).to.deep.eq([groupAddresses[0], groupAddresses[1]]);
        expect(lastTransferFromVotes.length).to.eq(2);
        expect(lastTransferFromVotes[0].add(lastTransferFromVotes[1])).eq(defaultGroupDeposit);

        expect(lastTransferToGroups).to.deep.eq([specificGroupStrategyAddress]);
        expect(lastTransferToVotes).to.deep.eq([defaultGroupDeposit]);
      });
    });
  });

  describe("#getExpectedAndActualCeloForGroup()", () => {
    describe("When strategy is disallowed", () => {
      const withdrawals = [50, 50];
      const depositedValue = 100;

      beforeEach(async () => {
        for (let i = 0; i < 2; i++) {
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
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

    describe("When group is only in allowed", () => {
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
          await defaultStrategyContract.activateGroup(groupAddresses[i]);
          await account.setCeloForGroup(groupAddresses[i], withdrawals[i]);
        }
      });

      describe("When group is only in active", () => {
        const depositedValue = 100;
        beforeEach(async () => {
          await manager.deposit({ value: depositedValue });
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
              await defaultStrategyContract.activateGroup(groupAddresses[i]);
            }
            await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue);

            await specificGroupStrategyContract.blockStrategy(groupAddresses[0]);
            await specificGroupStrategyContract.blockStrategy(groupAddresses[1]);
          });

          it("should schedule transfer from deprecated group", async () => {
            const exRe0 = await manager.getExpectedAndActualCeloForGroup(groupAddresses[0]);
            await defaultStrategyContract.deprecateGroup(groupAddresses[0]);
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
              await defaultStrategyContract.activateGroup(groupAddresses[i]);
            }
          });

          it("should schedule transfer from default strategy", async () => {
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

          it("should revert when rebalance to default strategy", async () => {
            await account.setCeloForGroup(groupAddresses[1], toGroupDepositedValue);
            await specificGroupStrategyContract.blockStrategy(groupAddresses[1]);
            await expect(manager.rebalance(groupAddresses[0], groupAddresses[1])).revertedWith(
              `InvalidToGroup("${groupAddresses[1]}")`
            );
          });
        });
      });
    });
  });
});
