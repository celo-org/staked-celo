import hre from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { StakedCelo } from "../typechain-types/StakedCelo";

import { ADDRESS_ZERO, impersonateAccount, randomSigner, resetNetwork, timeTravel } from "./utils";
import { MockManager } from "../typechain-types/MockManager";

describe("StakedCelo", () => {
  let stakedCelo: StakedCelo;
  let managerContract: MockManager;

  let owner: SignerWithAddress;
  let manager: SignerWithAddress;
  let nonManager: SignerWithAddress;

  let anAccount: SignerWithAddress;

  before(async () => {
    await resetNetwork();
    owner = await hre.ethers.getNamedSigner("owner");
    [nonManager] = await randomSigner(parseUnits("100"));
    [anAccount] = await randomSigner(parseUnits("100"));
  });

  beforeEach(async () => {
    await hre.deployments.fixture("TestStakedCelo");
    stakedCelo = await hre.ethers.getContract("StakedCelo");
    managerContract = await hre.ethers.getContract("MockManager");
    await stakedCelo.connect(owner).setManager(managerContract.address);

    await impersonateAccount(managerContract.address);
    manager = await hre.ethers.getSigner(managerContract.address);

    const [randomSignerToFundManager] = await randomSigner(parseUnits("101"));
    await hre.kit.sendTransaction({
      from: randomSignerToFundManager.address,
      to: manager.address,
      value: parseUnits("100").toString(),
    });
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
    it("should revert if called by non manager", async () => {
      await expect(
        stakedCelo.connect(nonManager).lockBalance(anAccount.address, balanceToLock)
      ).to.revertedWith(`CallerNotManager("${nonManager.address}")`);
    });

    it("should revert if account doesn't have enough stCelo", async () => {
      await expect(
        stakedCelo.connect(manager).lockBalance(anAccount.address, balanceToLock)
      ).to.revertedWith("Not enough locked stCelo");
    });

    describe("When Account has stCelo", () => {
      const stCeloOwned = 100;
      beforeEach(async () => {
        await stakedCelo.connect(manager).mint(anAccount.address, stCeloOwned);
      });
      it("Emits locked Event", async () => {
        await expect(stakedCelo.connect(manager).lockBalance(anAccount.address, stCeloOwned))
          .to.emit(stakedCelo, "Locked")
          .withArgs(anAccount.address, stCeloOwned);
      });

      it("Locks max amount", async () => {
        const balancesToLock = [10, 20, 5];

        await stakedCelo.connect(manager).lockBalance(anAccount.address, balancesToLock[0]);
        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(balancesToLock[0]);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(
          stCeloOwned - balancesToLock[0]
        );

        await stakedCelo.connect(manager).lockBalance(anAccount.address, balancesToLock[1]);
        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(balancesToLock[1]);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(
          stCeloOwned - balancesToLock[1]
        );

        await stakedCelo.connect(manager).lockBalance(anAccount.address, balancesToLock[2]);
        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(balancesToLock[1]);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(
          stCeloOwned - balancesToLock[1]
        );
      });

      describe("When account has 50% balance locked", () => {
        beforeEach(async () => {
          await stakedCelo.connect(manager).lockBalance(anAccount.address, stCeloOwned / 2);
        });

        it("should fail to transfer unlocked + locked balance", async () => {
          await expect(
            stakedCelo.connect(anAccount).transfer(managerContract.address, stCeloOwned)
          ).revertedWith(`ERC20: transfer amount exceeds balance`);
        });

        it("should allow to transfer unlocked balance", async () => {
          expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);
          expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);

          await stakedCelo.connect(anAccount).transfer(managerContract.address, stCeloOwned / 2);

          expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(0);
          expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);
        });
      });
    });
  });

  describe("#unlockBalance", () => {
    it("should revert when no locked stCelo", async () => {
      await expect(stakedCelo.unlockBalance(anAccount.address)).revertedWith("No locked stCelo");
    });

    describe("When locked balance", () => {
      const stCeloOwned = 100;
      beforeEach(async () => {
        await stakedCelo.connect(manager).mint(anAccount.address, stCeloOwned);
        stakedCelo.connect(manager).lockBalance(anAccount.address, stCeloOwned);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(0);
        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(stCeloOwned);
        expect(await stakedCelo.totalSupply()).to.eq(stCeloOwned);
      });

      it("should not unlock if manager contract return full locked amount", async () => {
        await managerContract.setLockedStCelo(stCeloOwned);

        await expect(stakedCelo.connect(manager).unlockBalance(anAccount.address)).revertedWith(
          `Nothing to unlock`
        );
      });

      it("should not unlock if manager contract return half locked amount", async () => {
        await managerContract.setLockedStCelo(stCeloOwned / 2);
        await stakedCelo.connect(manager).unlockBalance(anAccount.address);

        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);
        expect(await stakedCelo.totalSupply()).to.eq(stCeloOwned);
      });

      it("it should unlock if manager contract return 0 locked amount", async () => {
        await managerContract.setLockedStCelo(0);
        await stakedCelo.connect(manager).unlockBalance(anAccount.address);

        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(0);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(stCeloOwned);
        expect(await stakedCelo.totalSupply()).to.eq(stCeloOwned);
      });
    });
  });

  describe("#overrideLockBalance", () => {
    const stCeloOwned = 100;

    beforeEach(async () => {
      await stakedCelo.connect(manager).mint(anAccount.address, stCeloOwned);
    });

    it("should revert when not an manager", async () => {
      await expect(
        stakedCelo.connect(nonManager).overrideLockBalance(anAccount.address, 100)
      ).revertedWith(`CallerNotManager("${nonManager.address}")`);
    });

    it("should revert if there was no previous locked balance", async () => {
      const balanceToOverrideTo = 99;
      await expect(
        stakedCelo.connect(manager).overrideLockBalance(anAccount.address, balanceToOverrideTo)
      ).revertedWith("Not enough locked stCelo");
    });

    describe("When stCelo locked", () => {
      beforeEach(async () => {
        await stakedCelo.connect(manager).lockBalance(anAccount.address, stCeloOwned);
      });

      it("should change locked balance correctly", async () => {
        const balanceToOverrideTo = 99;
        await stakedCelo
          .connect(manager)
          .overrideLockBalance(anAccount.address, balanceToOverrideTo);

        expect(await stakedCelo.lockedBalanceOf(anAccount.address)).to.be.eq(balanceToOverrideTo);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(
          stCeloOwned - balanceToOverrideTo
        );
        expect(await stakedCelo.totalSupply()).to.eq(stCeloOwned);
      });
    });
  });
});
