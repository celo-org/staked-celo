import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { Manager } from "../typechain-types/Manager";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import { ADDRESS_ZERO, getImpersonatedSigner, randomSigner, resetNetwork } from "./utils";

after(() => {
  hre.kit.stop();
});

describe("SpecificGroupStrategy", () => {
  let manager: Manager;
  let nonVote: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;
  let nonManager: SignerWithAddress;
  let specificGroupStrategyContract: SpecificGroupStrategy;

  let nonOwner: SignerWithAddress;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  before(async function () {
    try {
      this.timeout(100000);
      await resetNetwork();

      await hre.deployments.fixture("FullTestManager");
      manager = await hre.ethers.getContract("Manager");
      specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");

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
          .setDependencies(ADDRESS_ZERO, nonVote.address)
      ).revertedWith("Account null");
    });

    it("reverts with zero groupHealth address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, ADDRESS_ZERO)
      ).revertedWith("GroupHealth null");
    });

    it("sets the vote contract", async () => {
      await specificGroupStrategyContract
        .connect(ownerSigner)
        .setDependencies(nonAccount.address, nonStakedCelo.address);
      const account = await specificGroupStrategyContract.account();
      expect(account).to.eq(nonAccount.address);

      const groupHealth = await specificGroupStrategyContract.groupHealth();
      expect(groupHealth).to.eq(nonStakedCelo.address);
    });

    it("cannot be called by a non-Owner account", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(nonOwner)
          .setDependencies(nonStakedCelo.address, nonAccount.address)
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

  describe("#addToSpecificGroupStrategyTotalStCeloVotes", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(nonManager)
          .addToSpecificGroupStrategyTotalStCeloVotes(nonVote.address, 10)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#subtractFromSpecificGroupStrategyTotalStCeloVotes", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        specificGroupStrategyContract
          .connect(nonManager)
          .subtractFromSpecificGroupStrategyTotalStCeloVotes(nonVote.address, 10)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#allowStrategy", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        specificGroupStrategyContract.connect(nonManager).allowStrategy(nonVote.address)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });

  describe("#blockStrategy", () => {
    it("cannot be called by a non-Manager address", async () => {
      await expect(
        specificGroupStrategyContract.connect(nonManager).blockStrategy(nonVote.address)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });
  });
});
