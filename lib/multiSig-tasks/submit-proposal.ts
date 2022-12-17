import chalk from "chalk";
import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  DESTINATIONS,
  DESTINATIONS_DESCRIPTION,
  MULTISIG_SUBMIT_PROPOSAL_TASK_DESCRIPTION,
  PAYLOADS,
  PAYLOADS_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
  VALUES,
  VALUES_DESCRIPTION,
  VERBOSE_LOG,
  VERBOSE_LOG_DESCRIPTION,
} from "../helpers/staticVariables";
import { MULTISIG_SUBMIT_PROPOSAL } from "../tasksNames";

task(MULTISIG_SUBMIT_PROPOSAL, MULTISIG_SUBMIT_PROPOSAL_TASK_DESCRIPTION)
  .addParam(DESTINATIONS, DESTINATIONS_DESCRIPTION, undefined, types.string)
  .addParam(VALUES, VALUES_DESCRIPTION, undefined, types.string)
  .addParam(PAYLOADS, PAYLOADS_DESCRIPTION, undefined, types.string)
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
        .submitProposal(
          args.destinations!.split(","),
          args.values!.split(","),
          args.payloads!.split(","),
          {
            type: 0,
          }
        );
      const receipt = await tx.wait();
      const events = receipt.events;
      let proposalId = -1;

      // extracting proposal ID from events emitted
      if (events !== undefined) {
        for (let i = 0; i < events!.length; i++) {
          if (events[i].event == "ProposalScheduled") {
            proposalId = events[i].args[0].toNumber();
          }
          if (args.verboseLog) {
            console.log(chalk.green("new event emitted:"), events[i].event, `(${events[i].args})`);
          }
        }
      }
      return proposalId;
    } catch (error) {
      console.log(chalk.red("Error submitting proposal:"), error);
    }
  });
