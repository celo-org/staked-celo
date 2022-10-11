import { task } from "hardhat/config";
import {
  ARGS,
  ARGS_DESCRIPTION,
  CONTRACT,
  CONTRACT_DESCRIPTION,
  FUNCTION,
  FUNCTION_DESCRIPTION,
  MULTISIG_ENCODE_PROPOSAL_PAYLOAD_TASK_DESCRIPTION,
} from "../helpers/staticVariables";
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
        console.log(`Starting ${MULTISIG_ENCODE_PROPOSAL_PAYLOAD} task...`);

        const contract = await hre.ethers.getContract(args.contract);
        if (contract == null) {
          throw new Error(`Contract ${args.contract} not found!`);
        }

        const encodedFunction = contract.interface.encodeFunctionData(
          args.function,
          args.args.split(",")
        );
        console.log("encoded payload:");
        console.log(encodedFunction);

        return encodedFunction;
      } catch (error) {
        console.log(error);
      }
    }
  );
