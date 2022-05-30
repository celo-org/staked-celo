import hre from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

hre.config.external = {
  deployments: {
    hardhat: ["chainData/deployments/local"],
  },
};

hre.config.networks.hardhat.forking!.blockNumber = 445;
hre.config.networks.hardhat.accounts = {
  mnemonic: "concert load couple harbor equip island argue ramp clarify fence smart topic",
  path: "m/44'/60'/0'/0",
  initialIndex: 0,
  count: 20,
  accountsBalance: "10000000000000000000000",
};

describe("Deployment check", () => {
  let multiSig: any;
  let account: any;
  let manager: any;
  let stCELO: any;
  let rstCELO: any;

  let multisigOwner0: SignerWithAddress;
  let multisigOwner1: SignerWithAddress;
  let multisigOwner2: SignerWithAddress;

  beforeEach(async () => {
    multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
    multisigOwner1 = await hre.ethers.getNamedSigner("multisigOwner1");
    multisigOwner2 = await hre.ethers.getNamedSigner("multisigOwner2");

    multiSig = await hre.ethers.getContract("MultiSig");
    account = await hre.ethers.getContract("Account");
    manager = await hre.ethers.getContract("Manager");
    stCELO = await hre.ethers.getContract("StakedCelo");
    rstCELO = await hre.ethers.getContract("RebasedStakedCelo");
  });

  it("multisig should be owned by 3 addresses", async () => {
    const ownerList = await multiSig.getOwners();
    expect(ownerList.length).to.eq(3);
    expect(ownerList[0]).to.eq(multisigOwner0.address);
    expect(ownerList[1]).to.eq(multisigOwner1.address);
    expect(ownerList[2]).to.eq(multisigOwner2.address);
  });

  it("multisig first be owned by 3 addresses", async () => {
    const ownerList = await multiSig.getOwners();
    expect(ownerList[1]).to.eq(multisigOwner1.address);
  });

  it("Manager should be owned by multisig", async () => {
    const currentManager = await account.manager();
    expect(currentManager).to.eq(manager.address);
  });

  it("Account should have manager contract address as manager", async () => {
    const currentManager = await account.manager();
    expect(currentManager).to.eq(manager.address);
  });

  it("StakedCelo should have manager contract address as manager", async () => {
    const currentManager = await stCELO.manager();
    expect(currentManager).to.eq(manager.address);
  });

  it("rstCELO should have zero supply", async () => {
    const currentsupply = await rstCELO.totalSupply();
    expect(currentsupply).to.eq(0);
  });
});
