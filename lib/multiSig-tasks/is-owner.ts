import { task, types } from "hardhat/config";
import { TransactionArguments } from "../helpers/interfaceHelper";
import {
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MULTISIG_IS_OWNER_TASK_DESCRIPTION,
  OWNER_ADDRESS,
  OWNER_ADDRESS_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_IS_OWNER } from "../tasksNames";

task(MULTISIG_IS_OWNER, MULTISIG_IS_OWNER_TASK_DESCRIPTION)
  .addParam(OWNER_ADDRESS, OWNER_ADDRESS_DESCRIPTION, undefined, types.string)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isOwner(args.ownerAddress);
      taskLogger.log("is multiSig owner:", result);
    } catch (error) {
      taskLogger.error("Error checking if address is a multiSig owner", error);
    }
  });
