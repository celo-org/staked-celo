import { expect } from "chai";
import hre from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { randomAddress, randomSigner } from "./utils";
import { parseUnits } from "ethers/lib/utils";
import { Contract, ContractFactory } from "ethers";

interface ProxyDeployTestData {
  contractName: string;
  fixtureName: string;
  initializeArgs: any[];
  ownerIsDeployer?: boolean;
}

const tests: ProxyDeployTestData[] = [
  {
    contractName: "StakedCelo",
    fixtureName: "TestStakedCelo",
    initializeArgs: [randomAddress(), randomAddress()],
  },
  {
    contractName: "Account",
    fixtureName: "TestAccount",
    initializeArgs: [randomAddress(), randomAddress(), randomAddress()],
  },
  {
    contractName: "Manager",
    fixtureName: "TestManager",
    initializeArgs: [randomAddress(), randomAddress()],
    ownerIsDeployer: true,
  },
  {
    contractName: "RebasedStakedCelo",
    fixtureName: "TestRebasedStakedCelo",
    initializeArgs: [randomAddress(), randomAddress(), randomAddress()],
  },
];

describe("Contract deployed via proxy", () => {
  let owner: SignerWithAddress;
  let deployer: SignerWithAddress;

  beforeEach(async () => {
    owner = await hre.ethers.getNamedSigner("owner");
    deployer = await hre.ethers.getNamedSigner("deployer");
  });

  tests.forEach((test) => {
    describe(test.contractName, () => {
      let contractFactory: ContractFactory;
      beforeEach(async () => {
        await hre.deployments.fixture(test.fixtureName);
        contractFactory = await hre.ethers.getContractFactory(test.contractName);
      });

      it("the implementation can not be initialized", async () => {
        const contract = await hre.ethers.getContract(test.contractName);
        const contractDeployment = await hre.deployments.get(test.contractName);

        expect(contractDeployment.implementation).to.exist;
        // Helping typescript out
        if (contractDeployment.implementation === undefined) return;

        expect(contract.address).not.to.eq(contractDeployment.implementation);

        const implementation = contractFactory.attach(contractDeployment.implementation);
        await expect(implementation.initialize(...test.initializeArgs)).revertedWith(
          "Initializable: contract is already initialized"
        );
      });

      describe("the contract", () => {
        let contract: Contract;
        let newOwner: SignerWithAddress;

        beforeEach(async () => {
          contract = await hre.ethers.getContract(test.contractName);
          [newOwner] = await randomSigner(parseUnits("100"));
        });

        it("is owned by the multisig", async () => {
          expect(await contract.owner()).to.eq(
            test.ownerIsDeployer ? deployer.address : owner.address
          );
        });

        describe("when called by the owner", () => {
          it("can transfer ownership", async () => {
            await expect(
              contract
                .connect(test.ownerIsDeployer ? deployer : owner)
                .transferOwnership(newOwner.address)
            ).not.reverted;
            expect(await contract.owner()).to.eq(newOwner.address);
          });

          it("can update the implementation", async () => {
            const newImplementation = (await contractFactory.deploy()).address;

            await expect(
              contract.connect(test.ownerIsDeployer ? deployer : owner).upgradeTo(newImplementation)
            )
              .emit(contract, "Upgraded")
              .withArgs(newImplementation);
          });
        });

        describe("when called by somebody else", () => {
          it("fails when trying to transfer ownership", async () => {
            await expect(
              contract.connect(newOwner).transferOwnership(newOwner.address)
            ).revertedWith("Ownable: caller is not the owner");
          });

          it("fails when trying to upgrade", async () => {
            const newImplementation = (await contractFactory.deploy()).address;
            await expect(contract.connect(newOwner).upgradeTo(newImplementation)).revertedWith(
              "Ownable: caller is not the owner"
            );
          });
        });
      });
    });
  });
});
