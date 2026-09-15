import { task, types } from "hardhat/config";
import { getSignerAndSetDeploymentPath, TransactionArguments } from "../helpers/interfaceHelper";
import {
  ABSTAIN,
  ABSTAIN_DESCRIPTION,
  ACCOUNT,
  ACCOUNT_DESCRIPTION,
  LOG_LEVEL,
  LOG_LEVEL_DESCRIPTION,
  MANAGER_VOTE_TASK_DESCRIPTION,
  NO,
  NO_DESCRIPTION,
  PROPOSAL_ID,
  PROPOSAL_ID_DESCRIPTION,
  USE_LEDGER,
  USE_LEDGER_DESCRIPTION,
  USE_NODE_ACCOUNT,
  USE_NODE_ACCOUNT_DESCRIPTION,
  YES,
  YES_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MANAGER_VOTE_PROPOSAL } from "../tasksNames";

task(MANAGER_VOTE_PROPOSAL, MANAGER_VOTE_TASK_DESCRIPTION)
  .addParam(PROPOSAL_ID, PROPOSAL_ID_DESCRIPTION, undefined, types.int)
  .addOptionalParam(YES, YES_DESCRIPTION, "0", types.string)
  .addOptionalParam(NO, NO_DESCRIPTION, "0", types.string)
  .addOptionalParam(ABSTAIN, ABSTAIN_DESCRIPTION, "0", types.string)
  .addOptionalParam(ACCOUNT, ACCOUNT_DESCRIPTION, undefined, types.string)
  .addOptionalParam(LOG_LEVEL, LOG_LEVEL_DESCRIPTION, undefined, types.string)
  .addFlag(USE_LEDGER, USE_LEDGER_DESCRIPTION)
  .addFlag(USE_NODE_ACCOUNT, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(async (args: TransactionArguments, hre) => {
    taskLogger.setLogLevel(args.logLevel);
    try {
      taskLogger.info(`Starting ${MANAGER_VOTE_PROPOSAL} task...`);
      const signer = await getSignerAndSetDeploymentPath(hre, args);
      
      const governance = await hre.kit.contracts.getGovernance();
      const dequeue = await governance.getDequeue()
      const proposalIndex = dequeue.findIndex(d => d.eq(args.proposalId!))
      if (proposalIndex == -1) {
        throw new Error(`Proposal ${args.proposalId} is not dequeued!`)
      }

      if (args.yes == null && args.no == null && args.abstain == null) {
        throw new Error('At least one vote choice needs to be > 0.')
      }

      const managerContract = await hre.ethers.getContract("Manager");
      const tx = await managerContract.connect(signer).voteProposal(args.proposalId!, proposalIndex, args.yes, args.no, args.abstain);
      const receipt = await tx.wait();

      taskLogger.debug("receipt status", receipt.status);
    } catch (error) {
      taskLogger.error("Error voting governance proposal:", error);
    }
  });
