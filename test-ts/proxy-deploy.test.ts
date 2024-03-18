import { Deployment } from "@celo/staked-celo-hardhat-deploy/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract, ContractFactory } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { randomAddress, randomSigner } from "./utils";
import { submitAndExecuteMultiSigProposal } from "./utils-multisig";

interface ProxyDeployTestData {
  contractName: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  initializeArgs: any[];
}

const tests: ProxyDeployTestData[] = [
  {
    contractName: "StakedCelo",
    initializeArgs: [randomAddress(), randomAddress()],
  },
  {
    contractName: "Account",
    initializeArgs: [randomAddress(), randomAddress(), randomAddress()],
  },
  {
    contractName: "Manager",
    initializeArgs: [randomAddress(), randomAddress()],
  },
  {
    contractName: "RebasedStakedCelo",
    initializeArgs: [randomAddress(), randomAddress(), randomAddress()],
  },
  {
    contractName: "Vote",
    initializeArgs: [randomAddress(), randomAddress(), randomAddress()],
  },
  {
    contractName: "DefaultStrategy",
    initializeArgs: [randomAddress(), randomAddress()],
  },
  {
    contractName: "SpecificGroupStrategy",
    initializeArgs: [randomAddress(), randomAddress()],
  },
  {
    contractName: "GroupHealth",
    initializeArgs: [randomAddress(), randomAddress()],
  },
];

describe("Contract deployed via proxy", () => {
  let multisigOwner0: SignerWithAddress;

  tests.forEach((test) => {
    describe(test.contractName, () => {
      let contractFactory: ContractFactory;
      let multiSig: Deployment;
      beforeEach(async () => {
        process.env = {
          ...process.env,
          TIME_LOCK_MIN_DELAY: "1",
          TIME_LOCK_DELAY: "1",
          MULTISIG_REQUIRED_CONFIRMATIONS: "1",
        };

        await hre.deployments.fixture("core");

        const implementation = await hre.deployments.getOrNull(
          test.contractName + "_Implementation"
        );

        multiSig = await hre.deployments.get("MultiSig");
        multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
        contractFactory = await hre.ethers.getContractFactory(test.contractName, {
          libraries: implementation?.libraries,
        });
      });

      it("the implementation can not be initialized", async () => {
        const contract = await hre.ethers.getContract(test.contractName);
        const contractDeployment = await hre.deployments.get(test.contractName);

        expect(contractDeployment.implementation).to.exist;
        expect(contract.address).not.to.eq(contractDeployment.implementation);

        const implementation = contractFactory.attach(contractDeployment.implementation as string);
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
          expect(await contract.owner()).to.eq(multiSig.address);
        });

        describe("when called by the owner", () => {
          it("can transfer ownership", async () => {
            await submitAndExecuteMultiSigProposal(
              [contract.address],
              ["0"],
              [contract.interface.encodeFunctionData("transferOwnership", [newOwner.address])],
              multisigOwner0
            );

            expect(await contract.owner()).to.eq(newOwner.address);
          });

          it("can update the implementation", async () => {
            const newImplementation = (await contractFactory.deploy()).address;
            const theProxy = await hre.ethers.getContract(`${test.contractName}_Proxy`);

            await expect(
              submitAndExecuteMultiSigProposal(
                [contract.address],
                ["0"],
                [contract.interface.encodeFunctionData("upgradeTo", [newImplementation])],
                multisigOwner0
              )
            ).to.emit(theProxy, "Upgraded");
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
