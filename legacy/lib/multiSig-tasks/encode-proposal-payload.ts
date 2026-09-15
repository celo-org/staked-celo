import { task } from "hardhat/config";
import { setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";
import {
  ARGS,
  ARGS_DESCRIPTION,
  CONTRACT,
  CONTRACT_DESCRIPTION,
  FUNCTION,
  FUNCTION_DESCRIPTION,
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD_TASK_DESCRIPTION,
} from "../helpers/staticVariables";
import { taskLogger } from "../logger";
import { MULTISIG_ENCODE_PROPOSAL_PAYLOAD } from "../tasksNames";

task(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, MULTISIG_ENCODE_PROPOSAL_PAYLOAD_TASK_DESCRIPTION)
  .addParam(CONTRACT, CONTRACT_DESCRIPTION)
  .addParam(FUNCTION, FUNCTION_DESCRIPTION)
  .addParam(ARGS, ARGS_DESCRIPTION)
  .setAction(
    async (
      args: {
        contract: string;
        function: string;
        args: string;
      },
      hre
    ) => {
      try {
        taskLogger.setLogLevel("info");
        taskLogger.info(`Starting ${MULTISIG_ENCODE_PROPOSAL_PAYLOAD} task...`);
        await setLocalNodeDeploymentPath(hre);
        const contract = await hre.ethers.getContract(args.contract);
        if (contract == null) {
          throw new Error(`Contract ${args.contract} not found!`);
        }

        const functionArg = args.args.length == 0 ? undefined : args.args.split(",");

        const encodedFunction = contract.interface.encodeFunctionData(args.function, functionArg);
        taskLogger.info("encoded payload:", encodedFunction);

        return encodedFunction;
      } catch (error) {
        taskLogger.error("Error encoding payload", error);
      }
    }
  );
