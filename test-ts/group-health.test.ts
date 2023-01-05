import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { ADDRESS_ZERO, getImpersonatedSigner, randomSigner, resetNetwork } from "./utils";

after(() => {
  hre.kit.stop();
});

describe("GroupHealth", () => {
  let manager: Manager;
  let groupHealthContract: GroupHealth;
  let nonVote: SignerWithAddress;
  let nonStakedCelo: SignerWithAddress;
  let nonAccount: SignerWithAddress;
  let nonManager: SignerWithAddress;

  let nonOwner: SignerWithAddress;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  before(async function () {
    try {
      this.timeout(100000);
      await resetNetwork();

      await hre.deployments.fixture("FullTestManager");
      manager = await hre.ethers.getContract("Manager");
      groupHealthContract = await hre.ethers.getContract("GroupHealth");

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

    it("reverts with zero StakedCelo address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(ADDRESS_ZERO, nonVote.address, nonVote.address, nonVote.address)
      ).revertedWith("StakedCelo null");
    });

    it("reverts with zero Account address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, ADDRESS_ZERO, nonVote.address, nonVote.address)
      ).revertedWith("Account null");
    });

    it("reverts with zero specific group strategy address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, nonVote.address, ADDRESS_ZERO, nonVote.address)
      ).revertedWith("SpecificGroupStrategy null");
    });

    it("reverts with zero Manager address", async () => {
      await expect(
        groupHealthContract
          .connect(ownerSigner)
          .setDependencies(nonVote.address, nonVote.address, nonVote.address, ADDRESS_ZERO)
      ).revertedWith("Manager null");
    });

    it("sets the vote contract", async () => {
      await groupHealthContract
        .connect(ownerSigner)
        .setDependencies(
          nonStakedCelo.address,
          nonAccount.address,
          nonVote.address,
          nonManager.address
        );

      const stakedCelo = await groupHealthContract.stakedCelo();
      expect(stakedCelo).to.eq(nonStakedCelo.address);

      const account = await groupHealthContract.account();
      expect(account).to.eq(nonAccount.address);

      const specificGroupStrategy = await groupHealthContract.specificGroupStrategy();
      expect(specificGroupStrategy).to.eq(nonVote.address);

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
            nonVote.address
          )
      ).revertedWith("Ownable: caller is not the owner");
    });
  });
});
