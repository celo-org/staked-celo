import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { MockAccount } from "../typechain-types/MockAccount";
import { MockStakedCelo } from "../typechain-types/MockStakedCelo";
import { RebasedStakedCelo } from "../typechain-types/RebasedStakedCelo";
import { ADDRESS_ZERO, randomSigner, resetNetwork } from "./utils";

describe("RebasedStakedCelo", () => {
  let rebasedStakedCelo: RebasedStakedCelo;
  let stakedCelo: MockStakedCelo;
  let account: MockAccount;

  let owner: SignerWithAddress;
  let pauser: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let someone: SignerWithAddress;

  before(async () => {
    await resetNetwork();
  });

  beforeEach(async () => {
    await hre.deployments.fixture("TestRebasedStakedCelo");
    rebasedStakedCelo = await hre.ethers.getContract("RebasedStakedCelo");
    stakedCelo = await hre.ethers.getContract("MockStakedCelo");
    account = await hre.ethers.getContract("MockAccount");

    owner = await hre.ethers.getNamedSigner("owner");
    pauser = owner;
    [alice] = await randomSigner(parseUnits("100"));
    [bob] = await randomSigner(parseUnits("100"));
    [someone] = await randomSigner(parseUnits("1000"));

    await rebasedStakedCelo.connect(owner).setPauser();
  });

  describe("#initialize()", () => {
    it("should be named 'Rebased Staked CELO'", async () => {
      const tokenName = await rebasedStakedCelo.name();
      expect(tokenName).to.eq("Rebased Staked CELO");
    });

    it("should have rstCELO as symbol", async () => {
      const tokenSymbol = await rebasedStakedCelo.symbol();
      expect(tokenSymbol).to.eq("rstCELO");
    });

    it("should have an owner address set", async () => {
      const actualOwnerAddress = await rebasedStakedCelo.owner();
      expect(actualOwnerAddress).to.eq(owner.address);
    });
  });

  describe("#deposit()", () => {
    let initialSupply: BigNumber;

    beforeEach("set initial token supply and distribute accordingly", async () => {
      await account.setTotalCelo(200);
      await stakedCelo.mint(someone.address, 200);
      await stakedCelo.connect(someone).approve(rebasedStakedCelo.address, 100);
      initialSupply = await rebasedStakedCelo.totalSupply();
    });

    it("should revert when the Rebase Staked CELO contract's allowance is too low", async () => {
      await expect(rebasedStakedCelo.connect(someone).deposit(150)).to.be.revertedWith(
        "ERC20: transfer amount exceeds allowance"
      );
    });

    it("should revert when user tries to deposit nothing", async () => {
      await expect(rebasedStakedCelo.connect(someone).deposit(0)).to.be.revertedWith(
        "ZeroAmount()"
      );
    });

    it("should increase total stCELO deposits", async () => {
      await rebasedStakedCelo.connect(someone).deposit(100);
      const totalDeposit = await rebasedStakedCelo.totalDeposit();

      expect(totalDeposit).to.eq(100);
    });

    it("should update accounting of each user deposit", async () => {
      await rebasedStakedCelo.connect(someone).deposit(100);
      const someoneDepositedStakedCELO = await rebasedStakedCelo.stakedCeloBalance(someone.address);

      expect(someoneDepositedStakedCELO).to.eq(100);
    });

    it("should emit a deposited event", async () => {
      const depositTx = await rebasedStakedCelo.connect(someone).deposit(100);

      await expect(depositTx)
        .to.emit(rebasedStakedCelo, "StakedCeloDeposited")
        .withArgs(someone.address, 100);
    });

    it("should increase the total supply of rstCELO", async () => {
      await rebasedStakedCelo.connect(someone).deposit(100);

      expect(await rebasedStakedCelo.totalSupply()).to.gt(initialSupply);
    });

    context("when there is less CELO than stCELO in the system", () => {
      beforeEach("set initial token supply and distribute accordingly", async () => {
        await account.setTotalCelo(200);
        await stakedCelo.mint(alice.address, 100);
        await stakedCelo.mint(bob.address, 100);

        await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
        await stakedCelo.connect(bob).approve(rebasedStakedCelo.address, 100);
      });

      it("should compute less rstCELO than there is deposited stCELO", async () => {
        await rebasedStakedCelo.connect(alice).deposit(100);
        await rebasedStakedCelo.connect(bob).deposit(100);
        const aliceRebasedCeloBalance = await rebasedStakedCelo.balanceOf(alice.address);
        const bobRebasedCeloBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(aliceRebasedCeloBalance).to.eq(50);
        expect(bobRebasedCeloBalance).to.eq(50);
      });
    });

    context("when there is equal amount of CELO and stCELO in the system", () => {
      beforeEach("set initial token supply and distribute accordingly", async () => {
        await account.setTotalCelo(400);
        await stakedCelo.mint(alice.address, 100);
        await stakedCelo.mint(bob.address, 100);

        await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
        await stakedCelo.connect(bob).approve(rebasedStakedCelo.address, 100);
      });

      it("should compute rstCELO 1:1 with stCELO for each depositor", async () => {
        await rebasedStakedCelo.connect(alice).deposit(100);
        await rebasedStakedCelo.connect(bob).deposit(100);
        const aliceRebasedCeloBalance = await rebasedStakedCelo.balanceOf(alice.address);
        const bobRebasedCeloBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(aliceRebasedCeloBalance).to.eq(100);
        expect(bobRebasedCeloBalance).to.eq(100);
      });
    });

    context("when there is more CELO than stCELO in the system", () => {
      beforeEach("set initial token supply and distribute accordingly", async () => {
        await account.setTotalCelo(800);
        await stakedCelo.mint(alice.address, 100);
        await stakedCelo.mint(bob.address, 100);

        await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
        await stakedCelo.connect(bob).approve(rebasedStakedCelo.address, 100);
      });

      it("should compute more rstCELO than there is deposited stCELO", async () => {
        await rebasedStakedCelo.connect(alice).deposit(100);
        await rebasedStakedCelo.connect(bob).deposit(100);
        const aliceRebasedCeloBalance = await rebasedStakedCelo.balanceOf(alice.address);
        const bobRebasedCeloBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(aliceRebasedCeloBalance).to.eq(200);
        expect(bobRebasedCeloBalance).to.eq(200);
      });
    });
  });

  describe("#withdraw()", () => {
    let initialSupply: BigNumber;

    beforeEach("deposit stCELO", async () => {
      await account.setTotalCelo(400);
      await stakedCelo.mint(alice.address, 100);
      await stakedCelo.mint(bob.address, 100);
      await stakedCelo.mint(someone.address, 200);

      await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
      await stakedCelo.connect(bob).approve(rebasedStakedCelo.address, 100);
      await rebasedStakedCelo.connect(alice).deposit(100);
      await rebasedStakedCelo.connect(bob).deposit(100);

      initialSupply = await rebasedStakedCelo.totalSupply();
    });

    it("should not allow to withdraw more than the user's available balance", async () => {
      await expect(rebasedStakedCelo.connect(bob).withdraw(200)).revertedWith(
        "InsufficientBalance(200)"
      );
    });

    it("should emit a withdrawn event", async () => {
      await expect(rebasedStakedCelo.connect(alice).withdraw(50))
        .to.emit(rebasedStakedCelo, "StakedCeloWithdrawn")
        .withArgs(alice.address, 50);
    });

    it("should decrease the total deposited stCELO appropriately", async () => {
      await rebasedStakedCelo.connect(alice).withdraw(50);

      expect(await rebasedStakedCelo.totalDeposit()).to.eq(150);
    });

    it("should decrease user rstCELO balance", async () => {
      await rebasedStakedCelo.connect(alice).withdraw(50);

      expect(await rebasedStakedCelo.balanceOf(alice.address)).to.eq(50);
    });

    it("should decrease the total supply of rstCELO", async () => {
      await rebasedStakedCelo.connect(alice).withdraw(50);

      expect(await rebasedStakedCelo.totalSupply()).to.lt(initialSupply);
    });

    it("should transfer withdrawn stCELO to alice", async () => {
      const initialBalance = await stakedCelo.balanceOf(alice.address);
      await rebasedStakedCelo.connect(alice).withdraw(50);

      expect(await stakedCelo.balanceOf(alice.address)).to.eq(initialBalance.add(50));
    });

    context("when there is less CELO than stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(200);
      });

      it("should rebase left-over balance", async () => {
        await rebasedStakedCelo.connect(bob).withdraw(50);
        const bobStakedCeloBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(bobStakedCeloBalance).to.eq(25);
      });

      it("should transfer exact withdrawn stCELO to bob", async () => {
        const initialBalance = await stakedCelo.balanceOf(bob.address);
        await rebasedStakedCelo.connect(bob).withdraw(50);

        expect(await stakedCelo.balanceOf(bob.address)).to.eq(initialBalance.add(50));
      });
    });

    context("when there is equal amount of CELO and stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(400);
      });

      it("should burn rstCELO at 1:1 with stCELO", async () => {
        await rebasedStakedCelo.connect(bob).withdraw(50);
        const bobBalance = await stakedCelo.balanceOf(bob.address);

        expect(bobBalance).to.eq(50);
      });
    });

    context("when there is more CELO than stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(800);
      });

      it("should burn more rstCELO than the withdrawn stCELO amount", async () => {
        await rebasedStakedCelo.connect(bob).withdraw(50);
        const bobBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(bobBalance).to.eq(100);
      });

      it("should transfer exact withdrawn stCELO to bob", async () => {
        const initialBalance = await stakedCelo.balanceOf(bob.address);
        await rebasedStakedCelo.connect(bob).withdraw(50);

        expect(await stakedCelo.balanceOf(bob.address)).to.eq(initialBalance.add(50));
      });
    });
  });

  describe("#transfer()", () => {
    let initialSupply: BigNumber;
    let initialDeposits: BigNumber;

    beforeEach("set initial token supply and distribute accordingly", async () => {
      await account.setTotalCelo(400);
      await stakedCelo.mint(alice.address, 100);
      await stakedCelo.mint(bob.address, 100);
      await stakedCelo.mint(someone.address, 200);

      await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
      await stakedCelo.connect(bob).approve(rebasedStakedCelo.address, 100);
      await rebasedStakedCelo.connect(alice).deposit(100);
      await rebasedStakedCelo.connect(bob).deposit(100);

      initialSupply = await rebasedStakedCelo.totalSupply();
      initialDeposits = await rebasedStakedCelo.totalDeposit();
    });

    it("should not allow transfer when balance is too low", async () => {
      await expect(rebasedStakedCelo.connect(alice).transfer(bob.address, 150)).to.be.revertedWith(
        "InsufficientBalance(150)"
      );
    });

    it("should emit a transfer event", async () => {
      const transferTx = await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);

      expect(transferTx)
        .to.emit(rebasedStakedCelo, "Transfer")
        .withArgs(alice.address, bob.address, 50);
    });

    context("when there is equal amount of CELO and stCELO in the system", () => {
      it("should decrease the sender's stCELO deposited amount", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const aliceStakedCeloBalance = await rebasedStakedCelo.stakedCeloBalance(alice.address);

        expect(aliceStakedCeloBalance).to.eq(50);
      });

      it("should decrease the sender's rstCELO balance", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const aliceRebasedCeloBalance = await rebasedStakedCelo.balanceOf(alice.address);

        expect(aliceRebasedCeloBalance).to.eq(50);
      });

      it("should increase the receiver's stCELO deposited amount", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const bobStakedCeloBalance = await rebasedStakedCelo.stakedCeloBalance(bob.address);

        expect(bobStakedCeloBalance).to.eq(150);
      });

      it("should increase the receiver's rstCELO balance", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const bobStakedCeloBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(bobStakedCeloBalance).to.eq(150);
      });

      it("should not change the total supply", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const currentSupply = await rebasedStakedCelo.totalSupply();

        expect(currentSupply).to.eq(initialSupply);
      });

      it("should not increase the total deposited stCELO", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const currentTotalDeposits = await rebasedStakedCelo.totalDeposit();

        expect(currentTotalDeposits).to.eq(initialDeposits);
      });
    });

    context("when there is less CELO than stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(200);
      });

      it("should decrease the sender's stCELO deposited amount", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const aliceStakedCeloBalance = await rebasedStakedCelo.stakedCeloBalance(alice.address);

        expect(aliceStakedCeloBalance).to.eq(0);
      });

      it("should decrease the sender's rstCELO balance", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const aliceRebasedCeloBalance = await rebasedStakedCelo.balanceOf(alice.address);

        expect(aliceRebasedCeloBalance).to.eq(0);
      });

      it("should increase the receiver's stCELO deposited amount", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const bobStakedCeloBalance = await rebasedStakedCelo.stakedCeloBalance(bob.address);

        expect(bobStakedCeloBalance).to.eq(200);
      });

      it("should increase the receiver's rstCELO balance", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const bobStakedCeloBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(bobStakedCeloBalance).to.eq(100);
      });

      it("should not increase the total deposited stCELO", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const currentTotalDeposits = await rebasedStakedCelo.totalDeposit();

        expect(currentTotalDeposits).to.eq(initialDeposits);
      });
    });

    context("when there is more CELO than stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(800);
      });

      it("should decrease the sender's stCELO deposited amount", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const aliceStakedCeloBalance = await rebasedStakedCelo.stakedCeloBalance(alice.address);

        expect(aliceStakedCeloBalance).to.eq(75);
      });

      it("should decrease the sender's rstCELO balance", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const aliceRebasedCeloBalance = await rebasedStakedCelo.balanceOf(alice.address);

        expect(aliceRebasedCeloBalance).to.eq(150);
      });

      it("should increase the receiver's stCELO deposited amount", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const bobStakedCeloBalance = await rebasedStakedCelo.stakedCeloBalance(bob.address);

        expect(bobStakedCeloBalance).to.eq(125);
      });

      it("should increase the receiver's rstCELO balance", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const bobStakedCeloBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(bobStakedCeloBalance).to.eq(250);
      });

      it("should not increase the total deposited stCELO", async () => {
        await rebasedStakedCelo.connect(alice).transfer(bob.address, 50);
        const currentTotalDeposits = await rebasedStakedCelo.totalDeposit();

        expect(currentTotalDeposits).to.eq(initialDeposits);
      });
    });
  });

  describe("#transferFrom()", () => {
    beforeEach("set initial token supply and initiate transferFrom sequence", async () => {
      await account.setTotalCelo(400);
      await stakedCelo.mint(alice.address, 100);
      await stakedCelo.mint(bob.address, 100);
      await stakedCelo.mint(someone.address, 200);

      await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
      await stakedCelo.connect(bob).approve(rebasedStakedCelo.address, 100);
      await rebasedStakedCelo.connect(alice).deposit(100);
      await rebasedStakedCelo.connect(bob).deposit(100);

      await rebasedStakedCelo.connect(alice).approve(bob.address, 50);
    });

    it("should prevent transfers to zero address", async () => {
      await rebasedStakedCelo.connect(bob).transferFrom(alice.address, someone.address, 50);
      await rebasedStakedCelo.connect(alice).increaseAllowance(bob.address, 100);

      await expect(
        rebasedStakedCelo.connect(bob).transferFrom(alice.address, ADDRESS_ZERO, 50)
      ).to.be.revertedWith(`AddressZeroNotAllowed()`);
    });

    it("should increase the receiver's rstCELO balance", async () => {
      await rebasedStakedCelo.connect(bob).transferFrom(alice.address, someone.address, 50);
      const someoneBalance = await rebasedStakedCelo.balanceOf(someone.address);

      expect(someoneBalance).to.eq(50);
    });

    it("should decrease the sender's rstCELO balance", async () => {
      await rebasedStakedCelo.connect(bob).transferFrom(alice.address, someone.address, 50);
      const aliceBalance = await rebasedStakedCelo.balanceOf(alice.address);

      expect(aliceBalance).to.eq(50);
    });

    it("should not change the authorized signer stCELO deposited amount", async () => {
      await rebasedStakedCelo.connect(bob).transferFrom(alice.address, someone.address, 50);
      const bobDepositBalance = await rebasedStakedCelo.stakedCeloBalance(bob.address);

      expect(bobDepositBalance).to.eq(100);
    });

    it("should increase the receiver's stCELO deposited amount", async () => {
      await rebasedStakedCelo.connect(bob).transferFrom(alice.address, someone.address, 50);
      const someoneDepositBalance = await rebasedStakedCelo.stakedCeloBalance(someone.address);

      expect(someoneDepositBalance).to.eq(50);
    });

    it("should decrease the sender stCELO deposited amount", async () => {
      await rebasedStakedCelo.connect(bob).transferFrom(alice.address, someone.address, 50);
      const aliceDepositBalance = await rebasedStakedCelo.stakedCeloBalance(someone.address);

      expect(aliceDepositBalance).to.eq(50);
    });

    it("should prevent transfers when sender's balance is too low", async () => {
      await rebasedStakedCelo.connect(alice).increaseAllowance(bob.address, 100);

      await expect(
        rebasedStakedCelo.connect(bob).transferFrom(alice.address, someone.address, 150)
      ).to.revertedWith("InsufficientBalance(150)");
    });

    it("should decrease approved signers allowance after transferring from an account", async () => {
      await rebasedStakedCelo.connect(bob).transferFrom(alice.address, someone.address, 50);

      expect(await rebasedStakedCelo.allowance(alice.address, bob.address)).to.eq(0);
    });

    it("should prevent transfer from an unapproved address", async () => {
      await expect(
        rebasedStakedCelo.connect(someone).transferFrom(alice.address, someone.address, 100)
      ).to.be.revertedWith("ERC20: insufficient allowance");
    });

    it("should emit a transfer event", async () => {
      const transferFromTx = await rebasedStakedCelo
        .connect(bob)
        .transferFrom(alice.address, someone.address, 50);

      expect(transferFromTx)
        .to.emit(rebasedStakedCelo, "Transfer")
        .withArgs(alice.address, someone.address, 50);
    });
  });

  describe("#totalSupply()", () => {
    let initialSupply: BigNumberish;

    beforeEach("set initial token supply and distribute accordingly", async () => {
      await account.setTotalCelo(400);
      await stakedCelo.mint(alice.address, 100);
      await stakedCelo.mint(bob.address, 100);
      await stakedCelo.mint(someone.address, 200);

      await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
      await stakedCelo.connect(bob).approve(rebasedStakedCelo.address, 100);
      await rebasedStakedCelo.connect(alice).deposit(100);
      await rebasedStakedCelo.connect(bob).deposit(100);

      initialSupply = await rebasedStakedCelo.totalSupply();
    });

    context("when there is less CELO than stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(200);
      });

      it("should decrease the total rstCELO supply", async () => {
        const currentSupply = await rebasedStakedCelo.totalSupply();

        expect(currentSupply).to.lt(initialSupply);
      });
    });

    context("when there is equal amount of CELO and stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(400);
      });

      it("should not change the total rstCELO supply", async () => {
        const currentSupply = await rebasedStakedCelo.totalSupply();

        expect(currentSupply).to.eq(initialSupply);
      });
    });

    context("when there is more CELO than stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(800);
      });

      it("should increase the total rstCELO supply", async () => {
        const currentSupply = await rebasedStakedCelo.totalSupply();

        expect(currentSupply).to.gt(initialSupply);
      });
    });
  });

  describe("#balanceOf()", () => {
    let initialBalance: BigNumberish;

    beforeEach("set initial token supply and distribute accordingly", async () => {
      await account.setTotalCelo(400);
      await stakedCelo.mint(alice.address, 100);
      await stakedCelo.mint(bob.address, 100);
      await stakedCelo.mint(someone.address, 200);

      await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
      await stakedCelo.connect(bob).approve(rebasedStakedCelo.address, 100);
      await rebasedStakedCelo.connect(alice).deposit(100);
      await rebasedStakedCelo.connect(bob).deposit(100);

      initialBalance = await rebasedStakedCelo.balanceOf(bob.address);
    });

    context("when there is less CELO than stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(200);
      });

      it("should decrease rstCELO balance", async () => {
        const bobBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(bobBalance).to.lt(initialBalance);
      });
    });

    context("when there is equal amount of CELO and stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(400);
      });

      it("should not change rstCELO balance", async () => {
        const bobBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(bobBalance).to.eq(initialBalance);
      });
    });

    context("when there is more CELO than stCELO in the system", () => {
      beforeEach("set total supplies", async () => {
        await account.setTotalCelo(800);
      });

      it("should increase rstCELO balance", async () => {
        const bobBalance = await rebasedStakedCelo.balanceOf(bob.address);

        expect(bobBalance).to.gt(initialBalance);
      });
    });
  });

  describe("#setPauser", () => {
    it("sets the pauser address to the owner of the contract", async () => {
      await rebasedStakedCelo.connect(owner).setPauser();
      const newPauser = await rebasedStakedCelo.pauser();
      expect(newPauser).to.eq(owner.address);
    });

    it("emits a PauserSet event", async () => {
      await expect(rebasedStakedCelo.connect(owner).setPauser())
        .to.emit(rebasedStakedCelo, "PauserSet")
        .withArgs(owner.address);
    });

    it("cannot be called by a non-owner", async () => {
      await expect(rebasedStakedCelo.connect(someone).setPauser()).revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    describe("when the owner is changed", async () => {
      beforeEach(async () => {
        await rebasedStakedCelo.connect(owner).transferOwnership(someone.address)
      });

      it("sets the pauser to the new owner", async () => {
        await rebasedStakedCelo.connect(someone).setPauser();
        const newPauser = await rebasedStakedCelo.pauser();
        expect(newPauser).to.eq(someone.address);
      });
    });
  });

  describe("#pause", () => {
    it("can be called by the pauser", async () => {
      await rebasedStakedCelo.connect(pauser).pause();
      const isPaused = await rebasedStakedCelo.isPaused();
      expect(isPaused).to.be.true;
    });

    it("emits a ContractPaused event", async () => {
      await expect(rebasedStakedCelo.connect(pauser).pause()).to.emit(
        rebasedStakedCelo,
        "ContractPaused"
      );
    });

    it("cannot be called by a random account", async () => {
      await expect(rebasedStakedCelo.connect(someone).pause()).revertedWith("OnlyPauser()");
      const isPaused = await rebasedStakedCelo.isPaused();
      expect(isPaused).to.be.false;
    });
  });

  describe("#unpause", () => {
    beforeEach(async () => {
      await rebasedStakedCelo.connect(pauser).pause();
    });

    it("can be called by the pauser", async () => {
      await rebasedStakedCelo.connect(pauser).unpause();
      const isPaused = await rebasedStakedCelo.isPaused();
      expect(isPaused).to.be.false;
    });

    it("emits a ContractUnpaused event", async () => {
      await expect(rebasedStakedCelo.connect(pauser).unpause()).to.emit(
        rebasedStakedCelo,
        "ContractUnpaused"
      );
    });

    it("cannot be called by a random account", async () => {
      await expect(rebasedStakedCelo.connect(someone).unpause()).revertedWith("OnlyPauser()");
      const isPaused = await rebasedStakedCelo.isPaused();
      expect(isPaused).to.be.true;
    });
  });

  describe("when paused", () => {
    beforeEach(async () => {
      await stakedCelo.mint(alice.address, 100);
      await stakedCelo.connect(alice).approve(rebasedStakedCelo.address, 100);
      await rebasedStakedCelo.connect(alice).deposit(100);
      await rebasedStakedCelo.connect(alice).approve(bob.address, 1);

      await rebasedStakedCelo.connect(pauser).pause();
    });

    it("can't call deposit", async () => {
      await expect(rebasedStakedCelo.connect(alice).deposit(100)).revertedWith("Paused()");
    });

    it("can't call withdraw", async () => {
      await expect(rebasedStakedCelo.connect(alice).withdraw(100)).revertedWith("Paused()");
    });

    it("can't call transfer", async () => {
      await expect(rebasedStakedCelo.connect(alice).transfer(bob.address, 1)).revertedWith(
        "Paused()"
      );
    });

    it("can't call approve", async () => {
      await expect(rebasedStakedCelo.connect(alice).approve(bob.address, 1)).revertedWith(
        "Paused()"
      );
    });

    it("can't call transferFrom", async () => {
      await expect(
        rebasedStakedCelo.connect(bob).transferFrom(alice.address, bob.address, 1)
      ).revertedWith("Paused()");
    });

    it("can't call increaseAllowance", async () => {
      await expect(rebasedStakedCelo.connect(alice).increaseAllowance(bob.address, 1)).revertedWith(
        "Paused()"
      );
    });

    it("can't call decreaseAllowance", async () => {
      await expect(rebasedStakedCelo.connect(alice).decreaseAllowance(bob.address, 1)).revertedWith(
        "Paused()"
      );
    });
  });
});
