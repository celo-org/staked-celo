import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_REVOKE_CONFIRMATION } from "../tasksNames";

import { getSigner, parseEvents, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";
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
  .setAction(async (args, hre) => {
    try {
      const signer = await getSigner(hre, args[ACCOUNT], args[USE_LEDGER], args[USE_NODE_ACCOUNT]);
      await setLocalNodeDeploymentPath(hre);
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract
        .connect(signer)
        .revokeConfirmation(args[PROPOSAL_ID], { type: 0 });
      const receipt = await tx.wait();
      parseEvents(receipt, "ConfirmationRevoked");
    } catch (error) {
      console.log(chalk.red("Error revoking proposal confirmation:"), error);
    }
  });
