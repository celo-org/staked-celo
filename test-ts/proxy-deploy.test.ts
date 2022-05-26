import { expect } from "chai";
import hre from "hardhat";
import { StakedCelo__factory } from "../typechain-types/factories/StakedCelo__factory";
import { StakedCelo } from "../typechain-types/StakedCelo";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { randomAddress, randomSigner } from "./utils";
import { parseUnits } from "ethers/lib/utils";

describe("Contract deployed via proxy", () => {
  let StakedCelo: StakedCelo__factory;
  let owner: SignerWithAddress;

  before(async () => {
    owner = await hre.ethers.getNamedSigner("owner");
  });

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
        await expect(stakedCelo.connect(newOwner).transferOwnership(newOwner.address)).revertedWith(
          "Ownable: caller is not the owner"
        );
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
