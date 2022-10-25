import hre, { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { StakedCelo } from "../typechain-types/StakedCelo";
import { StakedCelo__factory } from "../typechain-types/factories/StakedCelo__factory";

import { ADDRESS_ZERO, randomSigner, resetNetwork } from "./utils";

describe("StakedCelo", () => {
  let stakedCelo: StakedCelo;

  let owner: SignerWithAddress;
  let manager: SignerWithAddress;
  let nonManager: SignerWithAddress;

  let anAccount: SignerWithAddress;

  before(async () => {
    await resetNetwork();
    owner = await hre.ethers.getNamedSigner("owner");
    [manager] = await randomSigner(parseUnits("100"));
    [nonManager] = await randomSigner(parseUnits("100"));
    [anAccount] = await randomSigner(parseUnits("100"));
  });

  beforeEach(async () => {
    await hre.deployments.fixture("TestStakedCelo");
    stakedCelo = await hre.ethers.getContract("StakedCelo");
    await stakedCelo.connect(owner).setManager(manager.address);
  });

  describe("#mint()", () => {
    it("mints the specified amount of stCELO to an address", async () => {
      await stakedCelo.connect(manager).mint(anAccount.address, 100);
      const balance = await stakedCelo.balanceOf(anAccount.address);
      expect(balance).to.eq(100);
    });

    it("increments the total supply", async () => {
      await stakedCelo.connect(manager).mint(anAccount.address, 100);
      const supply = await stakedCelo.totalSupply();
      expect(supply).to.eq(100);
    });

    it("cannot be called by a non-Manager account", async () => {
      await expect(stakedCelo.connect(nonManager).mint(anAccount.address, 100)).revertedWith(
        `CallerNotManager("${nonManager.address}")`
      );
    });

    it("emits a Transfer event", async () => {
      await expect(stakedCelo.connect(manager).mint(anAccount.address, 100))
        .to.emit(stakedCelo, "Transfer")
        .withArgs(ADDRESS_ZERO, anAccount.address, 100);
    });
  });

  describe("#burn()", () => {
    beforeEach(async () => {
      await stakedCelo.connect(manager).mint(anAccount.address, 100);
    });

    it("burns the specified amount of stCELO from an address", async () => {
      await stakedCelo.connect(manager).burn(anAccount.address, 50);
      const balance = await stakedCelo.balanceOf(anAccount.address);
      expect(balance).to.eq(50);
    });

    it("decrements the total supply", async () => {
      await stakedCelo.connect(manager).burn(anAccount.address, 50);
      const supply = await stakedCelo.totalSupply();
      expect(supply).to.eq(50);
    });

    it("cannot be called by a non-Manager account", async () => {
      await expect(stakedCelo.connect(nonManager).burn(anAccount.address, 50)).revertedWith(
        `CallerNotManager("${nonManager.address}")`
      );
    });

    it("cannot burn more than the account balance", async () => {
      await expect(stakedCelo.connect(manager).burn(anAccount.address, 101)).revertedWith(
        "ERC20: burn amount exceeds balance"
      );
    });

    it("emits a Transfer event", async () => {
      await expect(stakedCelo.connect(manager).burn(anAccount.address, 50))
        .to.emit(stakedCelo, "Transfer")
        .withArgs(anAccount.address, ADDRESS_ZERO, 50);
    });
  });

  describe("#setManager()", () => {
    it("sets the manager", async () => {
      await stakedCelo.connect(owner).setManager(nonManager.address);
      const newManager = await stakedCelo.manager();
      expect(newManager).to.eq(nonManager.address);
    });

    it("emits a ManagerSet event", async () => {
      await expect(stakedCelo.connect(owner).setManager(nonManager.address))
        .to.emit(stakedCelo, "ManagerSet")
        .withArgs(nonManager.address);
    });

    it("cannot be called by a non-Owner account", async () => {
      await expect(stakedCelo.connect(manager).setManager(nonManager.address)).revertedWith(
        "Ownable: caller is not the owner"
      );
    });
  });

  describe("#lockBalance", () => {
    const balanceToLock = 100;
    it("should revert if called by non vote", async () => {
      await expect(
        stakedCelo.connect(nonManager).lockBalance(anAccount.address, balanceToLock)
      ).to.revertedWith(`CallerNotVoteContract("${nonManager.address}")`);
    });

    it("should revert if account doesn't have enough stCelo", async () => {
      await expect(
        stakedCelo.connect(manager).lockBalance(anAccount.address, balanceToLock)
      ).to.revertedWith("Not enough stCelo to lock");
    });

    describe("When Account has stCelo", () => {
      const stCeloOwned = 100;
      beforeEach(async () => {
        await stakedCelo.connect(manager).mint(anAccount.address, stCeloOwned);
      });
      describe("Emits locked Event", async () => {
        await expect(stakedCelo.connect(manager).lockBalance(anAccount.address, stCeloOwned))
          .to.emit(stakedCelo, "Locked")
          .withArgs(anAccount.address, stCeloOwned);
      });

      it("Locks max amount", async () => {
        const balancesToLock = [10, 20, 5];

        await stakedCelo.connect(manager).lockBalance(anAccount.address, balancesToLock[0]);
        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(balancesToLock[0]);

        await stakedCelo.connect(manager).lockBalance(anAccount.address, balancesToLock[1]);
        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(balancesToLock[1]);

        await stakedCelo.connect(manager).lockBalance(anAccount.address, balancesToLock[2]);
        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(balancesToLock[1]);
      });
    });
  });
});
