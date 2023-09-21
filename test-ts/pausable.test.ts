import { expect } from "chai";
import hre from "hardhat";
import { PausableTest } from "../typechain-types/PausableTest";

describe("Pausable", () => {
  let pausableTest: PausableTest;
  beforeEach(async () => {
    await hre.deployments.fixture("TestPausable");
    pausableTest = await hre.ethers.getContract("PausableTest");
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
      await pausableTest.pause();
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
