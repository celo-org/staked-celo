import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
// @ts-ignore -- not sure why i'm getting error here when compiling, but not in the test files.
import { MultiSig } from "../../typechain-types/MultiSig";

import { BigNumber, Contract, ContractReceipt } from "ethers";

import { HardhatRuntimeEnvironment } from "hardhat/types";

/// Get signer (should be compatible with testnet)
// TODO: test using ledger HW
export async function getSigner(
  hre: HardhatRuntimeEnvironment,
  signerName: string
): Promise<SignerWithAddress> {
  return await hre.ethers.getNamedSigner(signerName);
}

// Get multiSig contract
// deployment files are needed.
export async function getContract(hre: HardhatRuntimeEnvironment): Promise<Contract> {
  return await hre.ethers.getContract("MultiSig");
}

/// Get owners
export async function getOwners(multiSig: MultiSig): Promise<string[]> {
  return await multiSig.getOwners();
}

/// Submit proposal
export async function submitProposal(
  multiSig: MultiSig,
  destinations: [],
  values: [],
  payloads: [],
  signer: SignerWithAddress
): Promise<ContractReceipt> {
  const tx = await multiSig.connect(signer).submitProposal(destinations, values, payloads);
  return await tx.wait();
}

/// Confirm proposal
export async function confirmProposal(
  multiSig: MultiSig,
  proposalId: number,
  signer: SignerWithAddress
): Promise<ContractReceipt> {
  const tx = await multiSig.connect(signer).confirmProposal(proposalId);
  return await tx.wait();
}

/// Revoke confirmation
export async function revokeConfirmation(
  multiSig: MultiSig,
  proposalId: number,
  signer: SignerWithAddress
) {
  const tx = await multiSig.connect(signer).revokeConfirmation(proposalId);
  return await tx.wait();
}

/// Schedule proposal
export async function scheduleProposal(
  multiSig: MultiSig,
  proposalId: number,
  signer: SignerWithAddress
) {
  const tx = await multiSig.connect(signer).scheduleProposal(proposalId);
  return await tx.wait();
}

/// Execute proposal
export async function executeProposal(
  multiSig: MultiSig,
  proposalId: number,
  signer: SignerWithAddress
) {
  const tx = await multiSig.connect(signer).executeProposal(proposalId);
  return await tx.wait();
}

/// Get proposal
export async function getProposal(
  multiSig: MultiSig,
  proposalId: number
): Promise<
  [string[], BigNumber[], string[]] & {
    destinations: string[];
    values: BigNumber[];
    payloads: string[];
  }
> {
  return await multiSig.getProposal(proposalId);
}

/// Get confirmations
export async function getConfirmations(multiSig: MultiSig, proposalId: number): Promise<string[]> {
  return await multiSig.getConfirmations(proposalId);
}

/// Is proposal fully confirmed?
export async function isFullyConfirmed(multiSig: MultiSig, proposalId: number): Promise<boolean> {
  return await multiSig.isFullyConfirmed(proposalId);
}

/// Is proposal scheduled?
export async function isScheduled(multiSig: MultiSig, proposalId: number): Promise<boolean> {
  return await multiSig.isScheduled(proposalId);
}

/// Get timestamp
export async function getTimestamp(multiSig: MultiSig, proposalId: number): Promise<BigNumber> {
  return await multiSig.getTimestamp(proposalId);
}

/// Is proposal time-lock reached?
export async function isProposalTimelockReached(
  multiSig: MultiSig,
  proposalId: number
): Promise<boolean> {
  return await multiSig.isProposalTimelockReached(proposalId);
}

/// Is given address an owner of multisig contract?
export async function isOwner(multiSig: MultiSig, address: string): Promise<boolean> {
  return await multiSig.isOwner(address);
}

/// Is proposal confirmed by address?
export async function isConfirmedBy(
  multiSig: MultiSig,
  proposalId: number,
  address: string
): Promise<boolean> {
  return await multiSig.isConfirmedBy(proposalId, address);
}

/// Parse events emitted by contract functions
export function parseEvents(receipt: ContractReceipt, eventName: string) {
  const event = receipt.events?.find((event) => event.event === eventName);
  console.log("new event emitted:", event?.event, `(${event?.args})`);
}

/// temp function to gen payload
//TODO: remove this.
export async function encodeData(
  multiSig: MultiSig,
  hre: HardhatRuntimeEnvironment
): Promise<string> {
  const nonOwners: SignerWithAddress[] = await hre.ethers.getUnnamedSigners();
  return multiSig.interface.encodeFunctionData("addOwner", [nonOwners[0].address]);
}
