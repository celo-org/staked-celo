import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { MockAccount__factory } from "../typechain-types/factories/MockAccount__factory";
import { Manager } from "../typechain-types/Manager";
import { MockAccount } from "../typechain-types/MockAccount";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import { ADDRESS_ZERO, getImpersonatedSigner, randomSigner, resetNetwork } from "./utils";

after(() => {
  hre.kit.stop();
});

describe("DefaultStrategy", () => {
  let account: MockAccount;

  let manager: Manager;
  let groupHealthContract: MockGroupHealth;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategyContract: DefaultStrategy;
  let nonVote: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;
  let nonManager: SignerWithAddress;

  let owner: SignerWithAddress;
  let nonOwner: SignerWithAddress;

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
      defaultStrategyContract = await hre.ethers.getContract("MockDefaultStrategyFull");

      [owner] = await randomSigner(parseUnits("100"));
      [nonOwner] = await randomSigner(parseUnits("100"));
      [nonVote] = await randomSigner(parseUnits("100000"));
      [nonStakedCelo] = await randomSigner(parseUnits("100"));
      [nonAccount] = await randomSigner(parseUnits("100"));
      [nonManager] = await randomSigner(parseUnits("100"));

      const accountFactory: MockAccount__factory = (
        await hre.ethers.getContractFactory("MockAccount")
      ).connect(owner) as MockAccount__factory;
      account = await accountFactory.deploy();

      await defaultStrategyContract.setDependencies(
        account.address,
        groupHealthContract.address,
        specificGroupStrategyContract.address
      );
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
      ).revertedWith("Account null");
    });

    it("reverts with zero groupHealth address", async () => {
      await expect(
        defaultStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, ADDRESS_ZERO, nonVote.address)
      ).revertedWith("GroupHealth null");
    });

    it("reverts with zero specific group strategy address", async () => {
      await expect(
        defaultStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, nonVote.address, ADDRESS_ZERO)
      ).revertedWith("SpecificGroupStrategy null");
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

  describe("#generateGroupVotesToDistributeTo", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        defaultStrategyContract.connect(nonManager).generateGroupVotesToDistributeTo(10, 20)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#calculateAndUpdateForWithdrawal", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        defaultStrategyContract.connect(nonManager).calculateAndUpdateForWithdrawal(10)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#activateGroup", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        defaultStrategyContract.connect(nonManager).activateGroup(nonVote.address)
      ).revertedWith(`Ownable: caller is not the owner`);
    });
  });
});
