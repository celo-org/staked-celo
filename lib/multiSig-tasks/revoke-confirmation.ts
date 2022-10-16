import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_REVOKE_CONFIRMATION } from "../tasksNames";

import {
  getSignerAndSetDeploymentPath,
  parseEvents,
  TransactionArguments,
} from "../helpers/interfaceHelper";
import {
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
  USE_LEDGER_DESCRIPTION,
  USE_LEDGER,
  USE_NODE_ACCOUNT_DESCRIPTION,
  USE_NODE_ACCOUNT,
} from "../helpers/staticVariables";

task(MULTISIG_REVOKE_CONFIRMATION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      const signer = await getSignerAndSetDeploymentPath(hre, args);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract
        .connect(signer)
        .revokeConfirmation(args.proposalId!, { type: 0 });
      const receipt = await tx.wait();
      parseEvents(receipt, "ConfirmationRevoked");
    } catch (error) {
      console.log(chalk.red("Error revoking proposal confirmation:"), error);
    }
  });
