import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_SUBMIT_PROPOSAL } from "../tasksNames";

import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  DESTINATIONS,
  DESTINATIONS_DESCRIPTION,
  ACCOUNT_DESCRIPTION,
  ACCOUNT,
  MULTISIG_SUBMIT_PROPOSAL_TASK_DESCRIPTION,
  PAYLOADS,
  PAYLOADS_DESCRIPTION,
  USE_LEDGER_DESCRIPTION,
  USE_LEDGER,
  USE_NODE_ACCOUNT_DESCRIPTION,
  USE_NODE_ACCOUNT,
  VALUES,
  VALUES_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_SUBMIT_PROPOSAL, MULTISIG_SUBMIT_PROPOSAL_TASK_DESCRIPTION)
  .addParam(DESTINATIONS, DESTINATIONS_DESCRIPTION, undefined, types.string)
  .addParam(VALUES, VALUES_DESCRIPTION, undefined, types.string)
  .addParam(PAYLOADS, PAYLOADS_DESCRIPTION, undefined, types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
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
      if (events !== undefined) {
        for (var i = 0; i < events!.length; i++) {
          console.log(chalk.green("new event emitted:"), events[i].event, `(${events[i].args})`);
        }
      }
    } catch (error) {
      console.log(chalk.red("Error submitting proposal:"), error);
    }
  });
