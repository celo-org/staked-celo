import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { MultiSig } from "../../typechain-types/MultiSig";

import { BigNumber, ContractReceipt } from "ethers";

import { HardhatRuntimeEnvironment } from "hardhat/types";

let multiSig: MultiSig;

/// Get signer (should be compatible with testnet)
// TODO: test using ledger HW
export async function getSigner(
  hre: HardhatRuntimeEnvironment,
  signerName: string
): Promise<SignerWithAddress> {
  const owner: SignerWithAddress = await hre.ethers.getNamedSigner(signerName);
  return owner;
}

// Get multiSig contract
// deployment files are needed.
export async function getContract(
  hre: HardhatRuntimeEnvironment,
  contractName: string
): Promise<string> {
  multiSig = await hre.ethers.getContract(contractName);
  return multiSig.address;
}

/// Get owners
export async function getOwners(): Promise<string[]> {
  const ownerList = await multiSig.getOwners();
  return ownerList;
}

/// Submit proposal
export async function submitProposal(
  destinations: [],
  values: [],
  payloads: [],
  signer: SignerWithAddress
): Promise<ContractReceipt> {
  const tx = await multiSig.connect(signer).submitProposal(destinations, values, payloads);
  const receipt = await tx.wait();
  return receipt;
}

/// Confirm proposal
export async function confirmProposal(
  proposalId: number,
  signer: SignerWithAddress
): Promise<ContractReceipt> {
  const tx = await multiSig.connect(signer).confirmProposal(proposalId);
  const receipt = await tx.wait();
  return receipt;
}

/// Revoke confirmation
export async function revokeConfirmation(proposalId: number, signer: SignerWithAddress) {
  await multiSig.connect(signer).revokeConfirmation(proposalId);
}

/// Schedule proposal
export async function scheduleProposal(proposalId: number, signer: SignerWithAddress) {
  await multiSig.connect(signer).scheduleProposal(proposalId);
}

/// Execute proposal
export async function executeProposal(proposalId: number, signer: SignerWithAddress) {
  await multiSig.connect(signer).executeProposal(proposalId);
}

/// Get proposal
export async function getProposal(
  proposalId: number
): Promise<
  [string[], BigNumber[], string[]] & {
    destinations: string[];
    values: BigNumber[];
    payloads: string[];
  }
> {
  const proposalInfo = await multiSig.getProposal(proposalId);
  return proposalInfo;
}

/// Get confirmations
export async function getConfirmations(proposalId: number): Promise<string[]> {
  const confList = await multiSig.getConfirmations(proposalId);
  return confList;
}

/// Is proposal fully confirmed?
export async function isFullyConfirmed(proposalId: number): Promise<boolean> {
  const result = await multiSig.isFullyConfirmed(proposalId);
  return result;
}

/// Is proposal scheduled?
export async function isScheduled(proposalId: number): Promise<boolean> {
  const result = await multiSig.isScheduled(proposalId);
  return result;
}

/// Get timestamp
export async function getTimestamp(proposalId: number): Promise<BigNumber> {
  const timestamp = await multiSig.getTimestamp(proposalId);
  return timestamp;
}

/// Is proposal time-lock reached?
export async function isProposalTimelockReached(proposalId: number): Promise<boolean> {
  const result = await multiSig.isProposalTimelockReached(proposalId);
  return result;
}

/// Is given address an owner of multisig contract?
export async function isOwner(address: string): Promise<boolean> {
  const result = await multiSig.isOwner(address);
  return result;
}

/// Is proposal confirmed by address?
export async function isConfirmedBy(proposalId: number, address: string): Promise<boolean> {
  const result = await multiSig.isConfirmedBy(proposalId, address);
  return result;
}

/// temp function to gen payload
//TODO: remove this.
export async function encodeData(hre: HardhatRuntimeEnvironment): Promise<string> {
  const nonOwners: SignerWithAddress[] = await hre.ethers.getUnnamedSigners();
  const txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwners[0].address]);
  return txData;
}
