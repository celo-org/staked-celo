import { task } from "hardhat/config";
import { MULTISIG_ENCODE_PROPOSAL_PAYLOAD } from "../tasksNames";

task(MULTISIG_ENCODE_PROPOSAL_PAYLOAD, "Encodes function payload on contract for proposal.")
  .addParam("contract", "Name of the contract")
  .addParam("function", "Name of the function")
  .addParam("args", "Arguments of function separated by ,")
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
