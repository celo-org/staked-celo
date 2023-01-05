import { task, types } from "hardhat/config";
import { TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED } from "../tasksNames";

task(MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED, MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isProposalTimelockReached(args.proposalId);
      taskLogger.log("is timelock reached:", result);
    } catch (error) {
      taskLogger.error("Error cheking if proposal timelock has been reached:", error);
    }
  });
