import hre from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Account } from "../../typechain-types/Account";
import { Manager } from "../../typechain-types/Manager";
import { MultiSig } from "../../typechain-types/MultiSig";
import { StakedCelo } from "../../typechain-types/StakedCelo";
import { RebasedStakedCelo } from "../../typechain-types/RebasedStakedCelo";

hre.config.external = {
  deployments: {
    hardhat: ["chainData/deployments/local"],
  },
};
// Set `blockNumber` to the last block that Staked CELO contracts were deployed to.
hre.config.networks.hardhat.forking!.blockNumber = 785;
hre.config.networks.hardhat.accounts = {
  mnemonic: "concert load couple harbor equip island argue ramp clarify fence smart topic",
  path: "m/44'/60'/0'/0",
  initialIndex: 0,
  count: 20,
  accountsBalance: "10000000000000000000000",
};

describe("Deployment check", () => {
  let multiSig: MultiSig;
  let account: Account;
  let manager: Manager;
  let stCELO: StakedCelo;
  let rstCELO: RebasedStakedCelo;

  let multiSigOwner0: SignerWithAddress;
  let multiSigOwner1: SignerWithAddress;
  let multiSigOwner2: SignerWithAddress;

  beforeEach(async () => {
    multiSigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
    multiSigOwner1 = await hre.ethers.getNamedSigner("multisigOwner1");
    multiSigOwner2 = await hre.ethers.getNamedSigner("multisigOwner2");

    multiSig = await hre.ethers.getContract("MultiSig");
    account = await hre.ethers.getContract("Account");
    manager = await hre.ethers.getContract("Manager");
    stCELO = await hre.ethers.getContract("StakedCelo");
    rstCELO = await hre.ethers.getContract("RebasedStakedCelo");
  });

  it("MultiSig contract should be owned by the 3 multiSigOwners addresses", async () => {
    const ownerList = await multiSig.getOwners();
    expect(ownerList.length).to.eq(3);
    expect(ownerList[0]).to.eq(multiSigOwner0.address);
    expect(ownerList[1]).to.eq(multiSigOwner1.address);
    expect(ownerList[2]).to.eq(multiSigOwner2.address);
  });

  it("Manager should be owned by MultiSig", async () => {
    const currentManager = await account.manager();
    expect(currentManager).to.eq(manager.address);
  });

  it("Account should have Manager contract address as manager", async () => {
    const currentManager = await account.manager();
    expect(currentManager).to.eq(manager.address);
  });

  it("StakedCelo should have Manager contract address as manager", async () => {
    const currentManager = await stCELO.manager();
    expect(currentManager).to.eq(manager.address);
  });

  it("rstCELO should have zero supply", async () => {
    const currentsupply = await rstCELO.totalSupply();
    expect(currentsupply).to.eq(0);
  });
});
