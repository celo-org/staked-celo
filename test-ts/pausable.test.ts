import { expect } from "chai";
import hre from "hardhat";
import { PausableTest } from "../typechain-types/PausableTest";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { randomSigner } from "./utils";
import { parseUnits } from "ethers/lib/utils";

describe("Pausable", () => {
  let pausableTest: PausableTest;
  let pauser: SignerWithAddress;

  beforeEach(async () => {
    await hre.deployments.fixture("TestPausable");
    pausableTest = await hre.ethers.getContract("PausableTest");
    [pauser] = await randomSigner(parseUnits("100"));
    await pausableTest.setPauser(pauser.address);
  });

  describe("When not paused", () => {
    it("should allow the pausable function to be called", async () => {
      const numberBefore = await pausableTest.numberCalls();
      expect(numberBefore).to.equal(0);
      await pausableTest.callPausable();
      const numberAfter = await pausableTest.numberCalls();
      expect(numberAfter).to.equal(1);
    });

    it("reports as not paused", async () => {
      const paused = await pausableTest.isPaused();
      expect(paused).to.be.false;
    });
  });

  describe("When paused", () => {
    beforeEach(async () => {
      await pausableTest.connect(pauser).pause();
    });

    it("should not allow the pausable function to be called", async () => {
      const numberBefore = await pausableTest.numberCalls();
      expect(numberBefore).to.equal(0);
      await expect(pausableTest.callPausable()).revertedWith("Paused()");
    });

    it("should still allow the non-pausable function to be called", async () => {
      const numberBefore = await pausableTest.numberCalls();
      expect(numberBefore).to.equal(0);
      await pausableTest.callAlways();
      const numberAfter = await pausableTest.numberCalls();
      expect(numberAfter).to.equal(1);
    });

    it("reports as paused", async () => {
      const paused = await pausableTest.isPaused();
      expect(paused).to.be.true;
    });
  });
});
