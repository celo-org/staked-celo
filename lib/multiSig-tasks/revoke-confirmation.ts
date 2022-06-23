import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_REVOKE_CONFIRMATION } from "../tasksNames";

import { getSigner, parseEvents } from "../helpers/interfaceHelper";

task(MULTISIG_REVOKE_CONFIRMATION, "Revoke a proposal confirmation")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("namedAccount", "Named account of multiSig owner", undefined, types.string)
  .addFlag("useLedger", "Use ledger hardware wallet")
  .setAction(async ({ proposalId, namedAccount, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, namedAccount, useLedger);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract.connect(signer).revokeConfirmation(proposalId);
      const receipt = await tx.wait();
      parseEvents(receipt, "ConfirmationRevoked");
    } catch (error) {
      console.log(chalk.red("Error revoking proposal confirmation:"), error);
    }
  });
