import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_CONFIRM_PROPOSAL } from "../tasksNames";
import {
  getSignerAndSetDeploymentPath,
  parseEvents,
  TransactionArguments,
} from "../helpers/interfaceHelper";
import {
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  MULTISIG_CONFIRM_PROPOSAL_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
  USE_LEDGER_DESCRIPTION,
  USE_LEDGER,
  USE_NODE_ACCOUNT_DESCRIPTION,
  USE_NODE_ACCOUNT,
} from "../helpers/staticVariables";

task(MULTISIG_CONFIRM_PROPOSAL, MULTISIG_CONFIRM_PROPOSAL_TASK_DESCRIPTION)
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
        .confirmProposal(args.proposalId!, { type: 0 });
      const receipt = await tx.wait();
      parseEvents(receipt, "ProposalConfirmed");
    } catch (error) {
      console.log(chalk.red("Error confirming proposal:"), error);
    }
  });
