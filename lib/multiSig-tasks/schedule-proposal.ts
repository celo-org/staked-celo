import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_SCHEDULE_PROPOSAL } from "../tasksNames";

import { getSigner, parseEvents, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";

task(MULTISIG_SCHEDULE_PROPOSAL, "Schedule a proposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam(
    "account",
    "Named account or address of multiSig owner",
    undefined,
    types.string
  )
  .addFlag("useLedger", "Use ledger hardware wallet")
  .setAction(async ({ proposalId, account, useLedger }, hre) => {
    try {
      await setLocalNodeDeploymentPath(hre);
      const signer = await getSigner(hre, account, useLedger);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract.connect(signer).scheduleProposal(proposalId, { type: 0 });
      const receipt = await tx.wait();
      parseEvents(receipt, "ProposalScheduled");
    } catch (error) {
      console.log(chalk.red("Error scheduling proposal:"), error);
    }
  });
