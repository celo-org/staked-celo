// import hre, { ethers } from "hardhat";
// import { task } from "hardhat/config";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { MultiSig } from "../typechain-types/MultiSig";
// import { expect } from "chai";
// import { ADDRESS_ZERO, randomSigner, timeTravel, DAY } from "./utils";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { JsonRpcProvider } from "@ethersproject/providers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

let multiSig: MultiSig;
let owner: SignerWithAddress;
let nonOwners: SignerWithAddress[];

// get signer (should be compatible with testnet)

async function getSigner(hre: HardhatRuntimeEnvironment, signerName: string) {
  owner = await hre.ethers.getNamedSigner(signerName);
  nonOwners = await hre.ethers.getUnnamedSigners();
}

// get multiSig contract
// deployment files are needed.
export async function getMultisigContract(hre: HardhatRuntimeEnvironment, namedAccount: string) {
  multiSig = await hre.ethers.getContract("MultiSig");
  const newSigner = await getSigner(hre, namedAccount);
  console.log(newSigner);
}

export async function confirmProposal(hre: HardhatRuntimeEnvironment, proposalId: number) {
  try {
    const tx = await multiSig.connect(owner).confirmProposal(proposalId);
    const receipt = await tx.wait();
    const event = receipt.events?.find((event) => event.event === "ProposalConfirmed");
    console.log(event?.event);
    // check tx was successful
    // if not, throw
  } catch (error) {
    console.log("error", error);
  }
}
export async function executeProposal(proposalId: number) {
  await multiSig.executeProposal(proposalId);
}

export async function scheduleProposal(proposalId: number) {
  await multiSig.scheduleProposal(proposalId);
}
export async function getOwners(hre: HardhatRuntimeEnvironment) {
  const ownerList = await multiSig.getOwners();
  console.log(ownerList);
}

export async function getConfirmations(proposalId: number) {
  const confList = await multiSig.getConfirmations(proposalId);
  console.log(confList);
}

export async function getProposal(proposalId: number) {
  const [dest, val, pay] = await multiSig.getProposal(proposalId);
  console.log(dest, val, pay);
}

export async function createProposal() {
  const txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwners[0].address]);

  const tx = await multiSig.connect(owner).submitProposal([multiSig.address], [0], [txData]);
  const receipt = await tx.wait();
  const event = receipt.events?.find((event) => event.event === "ProposalConfirmed");
  // await getProposal(proposalId);
  // console.log(event);
}
