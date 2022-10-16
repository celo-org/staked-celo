import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_SCHEDULE_PROPOSAL } from "../tasksNames";

import {
  getSignerAndSetDeploymentPath,
  parseEvents,
  TransactionArguments,
} from "../helpers/interfaceHelper";
import {
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  MULTISIG_SCHEDULE_PROPOSAL_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
  USE_LEDGER_DESCRIPTION,
  USE_LEDGER,
  USE_NODE_ACCOUNT_DESCRIPTION,
  USE_NODE_ACCOUNT,
} from "../helpers/staticVariables";

task(MULTISIG_SCHEDULE_PROPOSAL, MULTISIG_SCHEDULE_PROPOSAL_TASK_DESCRIPTION)
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
        .scheduleProposal(args.proposalId!, { type: 0 });
      const receipt = await tx.wait();
      parseEvents(receipt, "ProposalScheduled");
    } catch (error) {
      console.log(chalk.red("Error scheduling proposal:"), error);
    }
  });
