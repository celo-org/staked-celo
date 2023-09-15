import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre, { ethers } from "hardhat";
import { ADDRESS_ZERO, DAY, randomSigner, timeTravel } from "./utils";
import { PausableTest } from "../typechain-types/PausableTest";

describe("Pausable", () => {
  let pausableTest: PausableTest
  beforeEach(async () => {
    await hre.deployments.fixture("TestPausable");
    pausableTest = await hre.ethers.getContract("PausableTest");
  });

  describe("When not paused", () => {
    it("should allow the pausable function to be called", async () => {
      const numberBefore = await pausableTest.numberCalls()
      expect(numberBefore).to.equal(0)
      await pausableTest.callPausable()
      const numberAfter = await pausableTest.numberCalls()
      expect(numberAfter).to.equal(1)
    });
  });

  describe("When paused", () => {
    beforeEach(async () => {
      pausableTest.pause()
    })

    it("should not allow the pausable function to be called", async () => {
      const numberBefore = await pausableTest.numberCalls()
      expect(numberBefore).to.equal(0)
      await expect(pausableTest.callPausable()).revertedWith("Paused()")
    });

    it("should still allow the non-pausable function to be called", async () => {
      const numberBefore = await pausableTest.numberCalls()
      expect(numberBefore).to.equal(0)
      await pausableTest.callAlways()
      const numberAfter = await pausableTest.numberCalls()
      expect(numberAfter).to.equal(1)
    })
  });
});
