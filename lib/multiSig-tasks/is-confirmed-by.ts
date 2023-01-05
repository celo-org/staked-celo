import { task, types } from "hardhat/config";
import { TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MULTISIG_IS_CONFIRMED_TASK_DESCRIPTION,
  OWNER_ADDRESS,
  OWNER_ADDRESS_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_IS_CONFIRMED_BY } from "../tasksNames";

task(MULTISIG_IS_CONFIRMED_BY, MULTISIG_IS_CONFIRMED_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addParam(OWNER_ADDRESS, OWNER_ADDRESS_DESCRIPTION, undefined, types.string)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isConfirmedBy(args.proposalId, args.ownerAddress);
      taskLogger.log("is Proposal confirmed:", result);
    } catch (error) {
      taskLogger.error("Error getting proposal confirmation by address:", error);
    }
  });
