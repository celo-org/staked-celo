import { BigNumberish, ContractTransaction, Signer } from "ethers";
import hre from "hardhat";
import { ProposalConfirmedEvent } from "../typechain-types/MultiSig";
import { timeTravel } from "./utils";

export async function submitAndExecuteMultiSigProposal(
  destinations: string[],
  values: BigNumberish[],
  payloads: string[],
  signer: Signer
): Promise<ContractTransaction> {
  const multiSig = await hre.ethers.getContract("MultiSig");
  const tx = await multiSig.connect(signer).submitProposal(destinations, values, payloads);
  const receipt = await tx.wait();
  const event = receipt.events?.find(
    (event: ProposalConfirmedEvent) => event.event === "ProposalConfirmed"
  );
  // @ts-ignore - proposalId not a compiled member of event.args
  const proposalId = event?.args.proposalId;
  await timeTravel((await multiSig.delay()).toNumber());
  return multiSig.connect(signer).executeProposal(proposalId);
}
