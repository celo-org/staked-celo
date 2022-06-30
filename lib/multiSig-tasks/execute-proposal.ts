import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_EXECUTE_PROPOSAL } from "../tasksNames";
import { getSigner, parseEvents } from "../helpers/interfaceHelper";

task(MULTISIG_EXECUTE_PROPOSAL, "Execute a proposal")
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
      const signer = await getSigner(hre, account, useLedger);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract.connect(signer).executeProposal(proposalId, { type: 0 });
      const receipt = await tx.wait();
      parseEvents(receipt, "TransactionExecuted");
    } catch (error) {
      console.log(chalk.red("Error executing proposal:"), error);
    }
  });
