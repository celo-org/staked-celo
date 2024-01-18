import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { MockManager } from "../typechain-types/MockManager";
import { StakedCelo } from "../typechain-types/StakedCelo";
import { ADDRESS_ZERO, impersonateAccount, randomSigner, resetNetwork } from "./utils";

describe("StakedCelo", () => {
  let stakedCelo: StakedCelo;
  let managerContract: MockManager;

  let owner: SignerWithAddress;
  let pauser: SignerWithAddress;
  let manager: SignerWithAddress;
  let nonManager: SignerWithAddress;

  let anAccount: SignerWithAddress;

  before(async () => {
    await resetNetwork();
    owner = await hre.ethers.getNamedSigner("owner");
    [pauser] = await randomSigner(parseUnits("100"));
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

    await stakedCelo.connect(owner).setPauser(pauser.address);
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

  describe("#lockVoteBalance", () => {
    const balanceToLock = 100;
    it("should revert if called by non manager", async () => {
      await expect(
        stakedCelo.connect(nonManager).lockVoteBalance(anAccount.address, balanceToLock)
      ).to.revertedWith(`CallerNotManager("${nonManager.address}")`);
    });

    it("should revert if account doesn't have enough stCelo", async () => {
      await expect(
        stakedCelo.connect(manager).lockVoteBalance(anAccount.address, balanceToLock)
      ).to.revertedWith(`NotEnoughStCeloToLock("${anAccount.address}")`);
    });

    describe("When Account has stCelo", () => {
      const stCeloOwned = 100;
      beforeEach(async () => {
        await stakedCelo.connect(manager).mint(anAccount.address, stCeloOwned);
      });
      it("Emits LockedStCelo Event", async () => {
        await expect(stakedCelo.connect(manager).lockVoteBalance(anAccount.address, stCeloOwned))
          .to.emit(stakedCelo, "LockedStCelo")
          .withArgs(anAccount.address, stCeloOwned);
      });

      it("Locks max amount", async () => {
        const balancesToLock = [10, 20, 5];

        await stakedCelo.connect(manager).lockVoteBalance(anAccount.address, balancesToLock[0]);
        expect(await stakedCelo.lockedVoteBalanceOf(anAccount.address)).to.be.eq(balancesToLock[0]);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(
          stCeloOwned - balancesToLock[0]
        );

        await stakedCelo.connect(manager).lockVoteBalance(anAccount.address, balancesToLock[1]);
        expect(await stakedCelo.lockedVoteBalanceOf(anAccount.address)).to.be.eq(balancesToLock[1]);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(
          stCeloOwned - balancesToLock[1]
        );

        await stakedCelo.connect(manager).lockVoteBalance(anAccount.address, balancesToLock[2]);
        expect(await stakedCelo.lockedVoteBalanceOf(anAccount.address)).to.be.eq(balancesToLock[1]);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(
          stCeloOwned - balancesToLock[1]
        );
      });

      describe("When account has 50% balance locked", () => {
        beforeEach(async () => {
          await stakedCelo.connect(manager).lockVoteBalance(anAccount.address, stCeloOwned / 2);
        });

        it("should fail to transfer unlocked + locked balance", async () => {
          await expect(
            stakedCelo.connect(anAccount).transfer(managerContract.address, stCeloOwned)
          ).revertedWith(`ERC20: transfer amount exceeds balance`);
        });

        it("should allow to transfer unlocked balance", async () => {
          expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);
          expect(await stakedCelo.lockedVoteBalanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);

          await stakedCelo.connect(anAccount).transfer(managerContract.address, stCeloOwned / 2);

          expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(0);
          expect(await stakedCelo.lockedVoteBalanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);
        });
      });
    });
  });

  describe("#unlockVoteBalance", () => {
    it("should revert when no locked stCelo", async () => {
      await expect(stakedCelo.unlockVoteBalance(anAccount.address)).revertedWith(
        `NoLockedStakedCelo("${anAccount.address}")`
      );
    });

    describe("When locked balance", () => {
      const stCeloOwned = 100;
      beforeEach(async () => {
        await stakedCelo.connect(manager).mint(anAccount.address, stCeloOwned);
        stakedCelo.connect(manager).lockVoteBalance(anAccount.address, stCeloOwned);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(0);
        expect(await stakedCelo.lockedVoteBalanceOf(anAccount.address)).to.be.eq(stCeloOwned);
        expect(await stakedCelo.totalSupply()).to.eq(stCeloOwned);
      });

      it("should not unlock if manager contract return full locked amount", async () => {
        await managerContract.setLockedStCelo(stCeloOwned);

        await expect(stakedCelo.connect(manager).unlockVoteBalance(anAccount.address)).revertedWith(
          `NothingToUnlock("${anAccount.address}")`
        );
      });

      it("should not unlock if manager contract return half locked amount", async () => {
        await managerContract.setLockedStCelo(stCeloOwned / 2);
        await stakedCelo.connect(manager).unlockVoteBalance(anAccount.address);

        expect(await stakedCelo.lockedVoteBalanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(stCeloOwned / 2);
        expect(await stakedCelo.totalSupply()).to.eq(stCeloOwned);
      });

      it("it should unlock if manager contract return 0 locked amount", async () => {
        await managerContract.setLockedStCelo(0);
        await stakedCelo.connect(manager).unlockVoteBalance(anAccount.address);

        expect(await stakedCelo.lockedVoteBalanceOf(anAccount.address)).to.be.eq(0);
        expect(await stakedCelo.balanceOf(anAccount.address)).to.be.eq(stCeloOwned);
        expect(await stakedCelo.totalSupply()).to.eq(stCeloOwned);
      });
    });
  });

  describe("#transfer()", () => {
    beforeEach(async () => {
      await stakedCelo.connect(manager).mint(anAccount.address, 100);
    });

    it("should call Manager transfer", async () => {
      await stakedCelo.connect(anAccount).transfer(managerContract.address, 1);
      const transfer = await managerContract.getTransfer(0);
      expect(transfer[0]).to.eq(anAccount.address);
      expect(transfer[1]).to.eq(managerContract.address);
      expect(transfer[2]).to.eq(1);
    });
  });

  describe("#setPauser", () => {
    it("sets the pauser address", async () => {
      await stakedCelo.connect(owner).setPauser(nonManager.address);
      const newPauser = await stakedCelo.pauser();
      expect(newPauser).to.eq(nonManager.address);
    });

    it("emits a PauserSet event", async () => {
      await expect(stakedCelo.connect(owner).setPauser(nonManager.address))
        .to.emit(stakedCelo, "PauserSet")
        .withArgs(nonManager.address);
    });

    it("cannot be called by a non-owner", async () => {
      await expect(stakedCelo.connect(nonManager).setPauser(nonManager.address)).revertedWith(
        "Ownable: caller is not the owner"
      );
    });
  });

  describe("#pause", () => {
    it("can be called by the pauser", async () => {
      await stakedCelo.connect(pauser).pause();
      const isPaused = await stakedCelo.isPaused();
      expect(isPaused).to.be.true;
    });

    it("emits a ContractPaused event", async () => {
      await expect(stakedCelo.connect(pauser).pause()).to.emit(stakedCelo, "ContractPaused");
    });

    it("cannot be called by the owner", async () => {
      await expect(stakedCelo.connect(owner).pause()).revertedWith("OnlyPauser()");
      const isPaused = await stakedCelo.isPaused();
      expect(isPaused).to.be.false;
    });

    it("cannot be called by a random account", async () => {
      await expect(stakedCelo.connect(nonManager).pause()).revertedWith("OnlyPauser()");
      const isPaused = await stakedCelo.isPaused();
      expect(isPaused).to.be.false;
    });
  });

  describe("#unpause", () => {
    beforeEach(async () => {
      await stakedCelo.connect(pauser).pause();
    });

    it("can be called by the pauser", async () => {
      await stakedCelo.connect(pauser).unpause();
      const isPaused = await stakedCelo.isPaused();
      expect(isPaused).to.be.false;
    });

    it("emits a ContractUnpaused event", async () => {
      await expect(stakedCelo.connect(pauser).unpause()).to.emit(stakedCelo, "ContractUnpaused");
    });

    it("cannot be called by the owner", async () => {
      await expect(stakedCelo.connect(owner).pause()).revertedWith("OnlyPauser()");
      const isPaused = await stakedCelo.isPaused();
      expect(isPaused).to.be.true;
    });

    it("cannot be called by a random account", async () => {
      await expect(stakedCelo.connect(nonManager).unpause()).revertedWith("OnlyPauser()");
      const isPaused = await stakedCelo.isPaused();
      expect(isPaused).to.be.true;
    });
  });

  describe("when paused", () => {
    beforeEach(async () => {
      await stakedCelo.connect(anAccount).approve(nonManager.address, 1);
      await stakedCelo.connect(pauser).pause();
    });

    it("can't call unlockVoteBalance", async () => {
      await expect(stakedCelo.connect(anAccount).unlockVoteBalance(anAccount.address)).revertedWith(
        "Paused()"
      );
    });

    it("can't call transfer", async () => {
      await expect(stakedCelo.connect(nonManager).transfer(anAccount.address, 1)).revertedWith(
        "Paused()"
      );
    });

    it("can't call approve", async () => {
      await expect(stakedCelo.connect(nonManager).approve(anAccount.address, 1)).revertedWith(
        "Paused()"
      );
    });

    it("can't call transferFrom", async () => {
      await expect(
        stakedCelo.connect(nonManager).transferFrom(anAccount.address, nonManager.address, 1)
      ).revertedWith("Paused()");
    });

    it("can't call increaseAllowance", async () => {
      await expect(
        stakedCelo.connect(nonManager).increaseAllowance(nonManager.address, 1)
      ).revertedWith("Paused()");
    });

    it("can't call decreaseAllowance", async () => {
      await expect(
        stakedCelo.connect(anAccount).decreaseAllowance(nonManager.address, 1)
      ).revertedWith("Paused()");
    });
  });
});
