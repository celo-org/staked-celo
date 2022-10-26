import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED } from "../tasksNames";
import {
  MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED_TASK_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
} from "../helpers/staticVariables";

task(MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED, MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .setAction(async (args, hre) => {
    try {
      const multiSigContract = await hre.ethers.getContract("MultiSig");
      const result = await multiSigContract.isProposalTimelockReached(args[PROPOSAL_ID]);
      console.log(result);
    } catch (error) {
      console.log(chalk.red("Error cheking if proposal timelock has been reached:"), error);
    }
  });
