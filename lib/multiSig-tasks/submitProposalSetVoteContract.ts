import chalk from "chalk";
import { task, types } from "hardhat/config";
import { TransactionArguments } from "../helpers/interfaceHelper";

import {
  MULTISIG_SUBMIT_PROPOSAL_SET_VOTE,
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD,
  MULTISIG_SUBMIT_PROPOSAL,
} from "../tasksNames";
import {
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  MULTISIG_SUBMIT_PROPOSAL_SET_VOTE_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_SUBMIT_PROPOSAL_SET_VOTE, MULTISIG_SUBMIT_PROPOSAL_SET_VOTE_DESCRIPTION)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    try {
      console.log(`${MULTISIG_SUBMIT_PROPOSAL_SET_VOTE} task...`);

      const payload = await hre.run(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, {
        contract: "Manager",
        function: "setVoteContract",
        args: (await hre.deployments.get("Vote")).address,
      });

      await hre.run(MULTISIG_SUBMIT_PROPOSAL, {
        destinations: [(await hre.deployments.get("Manager")).address],
        values: [0],
        payloads: [payload],
        account: args.account,
        useNodeAccount: args.useNodeAccount,
      });
    } catch (error) {
      console.log(chalk.red("Error getting groups:"), error);
    }
  });
