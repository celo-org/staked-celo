import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { PausableTest } from "../typechain-types/PausableTest";
import { Pauser } from "../typechain-types/Pauser";
import { randomSigner } from "./utils";

describe("Pauser", () => {
  let pauser: Pauser;
  let pausableTest: PausableTest;
  let owner: SignerWithAddress;
  let nonOwner: SignerWithAddress;

  beforeEach(async () => {
    await hre.deployments.fixture("TestPauser");
    pauser = await hre.ethers.getContract("Pauser");
    await hre.deployments.fixture("TestPausable");
    pausableTest = await hre.ethers.getContract("PausableTest");
    owner = await hre.ethers.getNamedSigner("owner");
    [nonOwner] = await randomSigner(parseUnits("100"));
  });

  describe("initialize", () => {
    it("should set the owner", async () => {
      const ownerSet = await pauser.owner();
      expect(ownerSet).to.equal(owner);
    });
  });

  describe("pause", () => {
    it("should pause the given contract", async () => {
      await pauser.connect(owner).pause(pausableTest.address);
      const isPaused = await pausableTest.isPaused();
      expect(isPaused).to.be.true;
    });

    it("should revert if called by a non-owner", async () => {
      await expect(pauser.connect(nonOwner).pause(pausableTest.address)).revertedWith(
        "Ownable: caller is not the owner"
      );
    });
  });

  describe("unpause", () => {
    beforeEach(async () => {
      await pausableTest.pause();
    });

    it("should unpause a previously paused contract", async () => {
      await pauser.connect(owner).unpause(pausableTest.address);
      const isPaused = await pausableTest.isPaused();
      expect(isPaused).to.be.false;
    });

    it("should revert if called by a non-owner", async () => {
      await expect(pauser.connect(nonOwner).unpause(pausableTest.address)).revertedWith(
        "Ownable: caller is not the owner"
      );
    });
  });
});
