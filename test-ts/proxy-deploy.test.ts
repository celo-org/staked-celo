import { expect } from "chai";
import hre from "hardhat";
import { StakedCelo__factory } from "../typechain-types/factories/StakedCelo__factory";
import { StakedCelo } from "../typechain-types/StakedCelo";
import { Account } from "../typechain-types/Account";
import { RebasedStakedCelo } from "../typechain-types/RebasedStakedCelo";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { randomAddress, randomSigner } from "./utils";
import { parseUnits } from "ethers/lib/utils";
import { Account__factory } from "../typechain-types/factories/Account__factory";
import { Manager__factory } from "../typechain-types/factories/Manager__factory";
import { RebasedStakedCelo__factory } from "../typechain-types/factories/RebasedStakedCelo__factory";
import { Manager } from "../typechain-types/Manager";

describe("Contract deployed via proxy", () => {
  let owner: SignerWithAddress;
  let deployer: SignerWithAddress;

  beforeEach(async () => {
    owner = await hre.ethers.getNamedSigner("owner");
    deployer = await hre.ethers.getNamedSigner("deployer");
    console.error("Test owner ", owner.address);
  });

  describe("StakedCelo", () => {
    let StakedCelo: StakedCelo__factory;
    beforeEach(async () => {
      await hre.deployments.fixture("TestStakedCelo");
      StakedCelo = await hre.ethers.getContractFactory("StakedCelo");
    });

    it("the implementation can not be initialized", async () => {
      const stakedCelo = await hre.ethers.getContract("StakedCelo");
      const stakedCeloDeployment = await hre.deployments.get("StakedCelo");

      expect(stakedCeloDeployment.implementation).to.exist;
      // Helping typescript out
      if (stakedCeloDeployment.implementation === undefined) return;

      expect(stakedCelo.address).not.to.eq(stakedCeloDeployment.implementation);

      const implementation = StakedCelo.attach(stakedCeloDeployment.implementation);
      await expect(implementation.initialize(randomAddress(), randomAddress())).revertedWith(
        "Initializable: contract is already initialized"
      );
    });

    describe("the contract", () => {
      let stakedCelo: StakedCelo;
      let newOwner: SignerWithAddress;

      beforeEach(async () => {
        stakedCelo = await hre.ethers.getContract("StakedCelo");
        [newOwner] = await randomSigner(parseUnits("100"));
      });

      it("is owned by the multisig", async () => {
        expect(await stakedCelo.owner()).to.eq(owner.address);
      });

      describe("when called by the owner", () => {
        it("can transfer ownership", async () => {
          await expect(stakedCelo.connect(owner).transferOwnership(newOwner.address)).not.reverted;
          expect(await stakedCelo.owner()).to.eq(newOwner.address);
        });

        it("can update the implementation", async () => {
          const newImplementation = (await StakedCelo.deploy()).address;

          await expect(stakedCelo.connect(owner).upgradeTo(newImplementation))
            .emit(stakedCelo, "Upgraded")
            .withArgs(newImplementation);
        });
      });

      describe("when called by somebody else", () => {
        it("fails when trying to transfer ownership", async () => {
          await expect(
            stakedCelo.connect(newOwner).transferOwnership(newOwner.address)
          ).revertedWith("Ownable: caller is not the owner");
        });

        it("fails when trying to upgrade", async () => {
          const newImplementation = (await StakedCelo.deploy()).address;
          await expect(stakedCelo.connect(newOwner).upgradeTo(newImplementation)).revertedWith(
            "Ownable: caller is not the owner"
          );
        });
      });
    });
  });

  describe("Account", () => {
    let Account: Account__factory;

    beforeEach(async () => {
      await hre.deployments.fixture("TestAccount");
      Account = await hre.ethers.getContractFactory("Account");
    });

    it("the implementation can not be initialized", async () => {
      const account = await hre.ethers.getContract("Account");
      const accountDeployment = await hre.deployments.get("Account");

      expect(accountDeployment.implementation).to.exist;
      // Helping typescript out
      if (accountDeployment.implementation === undefined) return;

      expect(account.address).not.to.eq(accountDeployment.implementation);

      const implementation = Account.attach(accountDeployment.implementation);
      await expect(
        implementation.initialize(randomAddress(), randomAddress(), randomAddress())
      ).revertedWith("Initializable: contract is already initialized");
    });

    describe("the contract", () => {
      let account: Account;
      let newOwner: SignerWithAddress;

      beforeEach(async () => {
        account = await hre.ethers.getContract("Account");
        [newOwner] = await randomSigner(parseUnits("100"));
      });

      it("is owned by the multisig", async () => {
        expect(await account.owner()).to.eq(owner.address);
      });

      describe("when called by the owner", () => {
        it("can transfer ownership", async () => {
          await expect(account.connect(owner).transferOwnership(newOwner.address)).not.reverted;
          expect(await account.owner()).to.eq(newOwner.address);
        });

        it("can update the implementation", async () => {
          const newImplementation = (await Account.deploy()).address;

          await expect(account.connect(owner).upgradeTo(newImplementation))
            .emit(account, "Upgraded")
            .withArgs(newImplementation);
        });
      });

      describe("when called by somebody else", () => {
        it("fails when trying to transfer ownership", async () => {
          await expect(account.connect(newOwner).transferOwnership(newOwner.address)).revertedWith(
            "Ownable: caller is not the owner"
          );
        });

        it("fails when trying to upgrade", async () => {
          const newImplementation = (await Account.deploy()).address;
          await expect(account.connect(newOwner).upgradeTo(newImplementation)).revertedWith(
            "Ownable: caller is not the owner"
          );
        });
      });
    });
  });

  describe("Manager", () => {
    let Manager: Manager__factory;

    beforeEach(async () => {
      await hre.deployments.fixture("TestManager");
      Manager = await hre.ethers.getContractFactory("Manager");
    });

    it("the implementation can not be initialized", async () => {
      const manager = await hre.ethers.getContract("Manager");
      const managerDeployment = await hre.deployments.get("Manager");

      expect(managerDeployment.implementation).to.exist;
      // Helping typescript out
      if (managerDeployment.implementation === undefined) return;

      expect(manager.address).not.to.eq(managerDeployment.implementation);

      const implementation = Manager.attach(managerDeployment.implementation);
      await expect(implementation.initialize(randomAddress(), randomAddress())).revertedWith(
        "Initializable: contract is already initialized"
      );
    });

    describe("the contract", () => {
      let manager: Manager;
      let newOwner: SignerWithAddress;

      beforeEach(async () => {
        manager = await hre.ethers.getContract("Manager");
        [newOwner] = await randomSigner(parseUnits("100"));
      });

      it("is owned by the multisig", async () => {
        expect(await manager.owner()).to.eq(deployer.address);
      });

      describe("when called by the owner", () => {
        it("can transfer ownership", async () => {
          await expect(manager.connect(deployer).transferOwnership(newOwner.address)).not.reverted;
          expect(await manager.owner()).to.eq(newOwner.address);
        });

        it("can update the implementation", async () => {
          const newImplementation = (await Manager.deploy()).address;

          await expect(manager.connect(deployer).upgradeTo(newImplementation))
            .emit(manager, "Upgraded")
            .withArgs(newImplementation);
        });
      });

      describe("when called by somebody else", () => {
        it("fails when trying to transfer ownership", async () => {
          await expect(manager.connect(newOwner).transferOwnership(newOwner.address)).revertedWith(
            "Ownable: caller is not the owner"
          );
        });

        it("fails when trying to upgrade", async () => {
          const newImplementation = (await Manager.deploy()).address;
          await expect(manager.connect(newOwner).upgradeTo(newImplementation)).revertedWith(
            "Ownable: caller is not the owner"
          );
        });
      });
    });
  });

  describe("RebasedStakedCelo", () => {
    let RebasedStakedCelo: RebasedStakedCelo__factory;

    beforeEach(async () => {
      await hre.deployments.fixture("TestRebasedStakedCelo");
      RebasedStakedCelo = await hre.ethers.getContractFactory("RebasedStakedCelo");
    });

    it("the implementation can not be initialized", async () => {
      const rebasedStakedCelo = await hre.ethers.getContract("RebasedStakedCelo");
      const rebasedStakedCeloDeployment = await hre.deployments.get("RebasedStakedCelo");

      expect(rebasedStakedCeloDeployment.implementation).to.exist;
      // Helping typescript out
      if (rebasedStakedCeloDeployment.implementation === undefined) return;

      expect(rebasedStakedCelo.address).not.to.eq(rebasedStakedCeloDeployment.implementation);

      const implementation = RebasedStakedCelo.attach(rebasedStakedCeloDeployment.implementation);
      await expect(
        implementation.initialize(randomAddress(), randomAddress(), randomAddress())
      ).revertedWith("Initializable: contract is already initialized");
    });

    describe("the contract", () => {
      let rebasedStakedCelo: RebasedStakedCelo;
      let newOwner: SignerWithAddress;

      beforeEach(async () => {
        rebasedStakedCelo = await hre.ethers.getContract("RebasedStakedCelo");
        [newOwner] = await randomSigner(parseUnits("100"));
      });

      it("is owned by the multisig", async () => {
        expect(await rebasedStakedCelo.owner()).to.eq(owner.address);
      });

      describe("when called by the owner", () => {
        it("can transfer ownership", async () => {
          await expect(rebasedStakedCelo.connect(owner).transferOwnership(newOwner.address)).not
            .reverted;
          expect(await rebasedStakedCelo.owner()).to.eq(newOwner.address);
        });

        it("can update the implementation", async () => {
          const newImplementation = (await RebasedStakedCelo.deploy()).address;

          await expect(rebasedStakedCelo.connect(owner).upgradeTo(newImplementation))
            .emit(rebasedStakedCelo, "Upgraded")
            .withArgs(newImplementation);
        });
      });

      describe("when called by somebody else", () => {
        it("fails when trying to transfer ownership", async () => {
          await expect(
            rebasedStakedCelo.connect(newOwner).transferOwnership(newOwner.address)
          ).revertedWith("Ownable: caller is not the owner");
        });

        it("fails when trying to upgrade", async () => {
          const newImplementation = (await RebasedStakedCelo.deploy()).address;
          await expect(
            rebasedStakedCelo.connect(newOwner).upgradeTo(newImplementation)
          ).revertedWith("Ownable: caller is not the owner");
        });
      });
    });
  });
});
