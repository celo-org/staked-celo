import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { PausableTest } from "../typechain-types/PausableTest";
import { ADDRESS_ZERO, randomSigner } from "./utils";

after(() => {
  hre.kit.stop();
});

describe("Pausable", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  let pausableTest: PausableTest;
  let pauser: SignerWithAddress;
  let nonPauser: SignerWithAddress;

  before(async () => {
    await hre.deployments.fixture("TestPausable");
    pausableTest = await hre.ethers.getContract("PausableTest");
    [pauser] = await randomSigner(parseUnits("100"));
    [nonPauser] = await randomSigner(parseUnits("100"));
    await pausableTest.setPauser(pauser.address);
  });

  beforeEach(async () => {
    snapshotId = await hre.ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await hre.ethers.provider.send("evm_revert", [snapshotId]);
  });

  describe("#pause", () => {
    it("sets the contract to paused", async () => {
      await pausableTest.connect(pauser).pause();
      const paused = await pausableTest.isPaused();
      expect(paused).to.be.true;
    });

    it("emits a ContractPaused event", async () => {
      await expect(pausableTest.connect(pauser).pause()).to.emit(pausableTest, "ContractPaused()");
    });

    it("cannot be called by a non-pauser", async () => {
      await expect(pausableTest.connect(nonPauser).pause()).revertedWith("OnlyPauser()");
      const paused = await pausableTest.isPaused();
      expect(paused).to.be.false;
    });

    describe("when paused", () => {
      beforeEach(async () => {
        await pausableTest.connect(pauser).pause();
      });

      it("should not allow the pausable function to be called", async () => {
        await expect(pausableTest.callPausable()).revertedWith("Paused()");
      });

      it("should still allow the non-pausable function to be called", async () => {
        const numberBefore = await pausableTest.numberCalls();
        expect(numberBefore).to.equal(0);
        await pausableTest.callAlways();
        const numberAfter = await pausableTest.numberCalls();
        expect(numberAfter).to.equal(1);
      });
    });
  });

  describe("#unpause", () => {
    describe("when paused", () => {
      beforeEach(async () => {
        await pausableTest.connect(pauser).pause();
      });

      it("sets the contract to unpaused", async () => {
        await pausableTest.connect(pauser).unpause();
        const paused = await pausableTest.isPaused();
        expect(paused).to.be.false;
      });

      it("emits a ContractUnpaused event", async () => {
        await expect(pausableTest.connect(pauser).unpause()).to.emit(
          pausableTest,
          "ContractUnpaused"
        );
      });

      it("cannot be called by a non-pauser", async () => {
        await expect(pausableTest.connect(nonPauser).unpause()).revertedWith("OnlyPauser()");
        const paused = await pausableTest.isPaused();
        expect(paused).to.be.true;
      });

      describe("once unpaused", () => {
        beforeEach(async () => {
          await pausableTest.connect(pauser).unpause();
        });

        it("should allow the pausable function to be called", async () => {
          const numberBefore = await pausableTest.numberCalls();
          expect(numberBefore).to.equal(0);
          await pausableTest.callPausable();
          const numberAfter = await pausableTest.numberCalls();
          expect(numberAfter).to.equal(1);
        });

        it("should still allow the non-pausable function to be called", async () => {
          const numberBefore = await pausableTest.numberCalls();
          expect(numberBefore).to.equal(0);
          await pausableTest.callAlways();
          const numberAfter = await pausableTest.numberCalls();
          expect(numberAfter).to.equal(1);
        });
      });
    });
  });

  describe("#_setPauser", () => {
    it("sets the pauser", async () => {
      await pausableTest.setPauser(nonPauser.address);
      const currentPauser = await pausableTest.pauser();
      expect(currentPauser).to.equal(nonPauser.address);
    });

    it("doesn't allow address 0", async () => {
      await expect(pausableTest.setPauser(ADDRESS_ZERO)).revertedWith("AddressZeroNotAllowed()");
    });

    it("emits a PauserSet event", async () => {
      await expect(pausableTest.setPauser(nonPauser.address))
        .to.emit(pausableTest, "PauserSet")
        .withArgs(nonPauser.address);
    });

    describe("when the pauser is changed", () => {
      beforeEach(async () => {
        await pausableTest.setPauser(nonPauser.address);
      });

      it("allows the new pauser to pause", async () => {
        await pausableTest.connect(nonPauser).pause();
        const paused = await pausableTest.isPaused();
        expect(paused).to.be.true;
      });

      it("does not allow the old pauser to pause", async () => {
        await expect(pausableTest.connect(pauser).pause()).revertedWith("OnlyPauser()");
        const paused = await pausableTest.isPaused();
        expect(paused).to.be.false;
      });
    });
  });
});
