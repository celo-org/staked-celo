import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_CONFIRM_PROPOSAL } from "../tasksNames";
import { getSigner, parseEvents, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";
import {
  USE_NODE_ACCOUNT_DESCRIPTION,
  USE_NODE_ACCOUNT_PARAM_NAME,
} from "../helpers/staticVariables";

task(MULTISIG_CONFIRM_PROPOSAL, "Confirm a multiSig proposal")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam(
    "account",
    "Named account or address of multiSig owner",
    undefined,
    types.string
  )
  .addFlag("useLedger", "Use ledger hardware wallet")
  .addFlag(USE_NODE_ACCOUNT_PARAM_NAME, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async ({ proposalId, account, useLedger, useNodeAccount }, hre) => {
    try {
      const signer = await getSigner(hre, account, useLedger, useNodeAccount);
      await setLocalNodeDeploymentPath(hre);

      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract.connect(signer).confirmProposal(proposalId, { type: 0 });
      const receipt = await tx.wait();
      parseEvents(receipt, "ProposalConfirmed");
    } catch (error) {
      console.log(chalk.red("Error confirming proposal:"), error);
    }
  });
