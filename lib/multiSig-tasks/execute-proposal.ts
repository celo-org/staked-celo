import chalk from "chalk";
import { task, types } from "hardhat/config";
import {
  getSignerAndSetDeploymentPath,
  parseEvents,
  TransactionArguments,
} from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  MULTISIG_EXECUTE_PROPOSAL_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
  VERBOSE_LOG,
  VERBOSE_LOG_DESCRIPTION,
} from "../helpers/staticVariables";
import { MULTISIG_EXECUTE_PROPOSAL } from "../tasksNames";

task(MULTISIG_EXECUTE_PROPOSAL, MULTISIG_EXECUTE_PROPOSAL_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .addFlag(VERBOSE_LOG, VERBOSE_LOG_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      const signer = await getSignerAndSetDeploymentPath(hre, args);

      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const tx = await multiSigContract
        .connect(signer)
        .executeProposal(args.proposalId!, { type: 0 });
      const receipt = await tx.wait();
      parseEvents(args.verboseLog, receipt, "TransactionExecuted");
    } catch (error) {
      console.log(chalk.red("Error executing proposal:"), error);
      throw error;
    }
  });
