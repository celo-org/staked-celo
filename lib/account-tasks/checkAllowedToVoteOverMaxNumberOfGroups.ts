import { task } from "hardhat/config";
import { TransactionArguments } from "../helpers/interfaceHelper";
import {
  ACCOUNT_ALLOWED_TO_VOTE_OVER_MAXIMUM_NUMBER_OF_GROUPS_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { ACCOUNT_ALLOWED_TO_VOTE_OVER_MAXIMUM_NUMBER_OF_GROUPS } from "../tasksNames";

task(ACCOUNT_ALLOWED_TO_VOTE_OVER_MAXIMUM_NUMBER_OF_GROUPS, ACCOUNT_ALLOWED_TO_VOTE_OVER_MAXIMUM_NUMBER_OF_GROUPS_DESCRIPTION)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);

    try {
      taskLogger.info(`Starting ${ACCOUNT_ALLOWED_TO_VOTE_OVER_MAXIMUM_NUMBER_OF_GROUPS} task...`);

      const electionWrapper = await hre.kit.contracts.getElection();
      const electionContract = electionWrapper["contract"];

      const accountContract = await hre.ethers.getContract("Account");

      const allowed = await electionContract.methods.allowedToVoteOverMaxNumberOfGroups(accountContract.address).call()

      taskLogger.info("Account allowed to vote over maximum number of groups:", allowed)

    } catch (error) {
      taskLogger.error("Error checking allowed to vote over maximum number of groups CELO:", error);
    }
  });
