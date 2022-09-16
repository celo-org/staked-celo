import { task, types } from "hardhat/config";
import chalk from "chalk";

import { MULTISIG_SUBMIT_PROPOSAL } from "../tasksNames";

import { getSigner, setLocalNodeDeploymentPath } from "../helpers/interfaceHelper";
import {
  USE_NODE_ACCOUNT_DESCRIPTION,
  USE_NODE_ACCOUNT_PARAM_NAME,
} from "../helpers/staticVariables";

task(MULTISIG_SUBMIT_PROPOSAL, "Submit a proposal to the multiSig contract")
  .addParam(
    "destinations",
    "The addresses at which the operations are targeted | Use comma separated values for multiple entries.",
    undefined,
    types.string
  )
  .addParam(
    "values",
    "The CELO values involved in the proposal if any | Use comma separated values for multiple entries",
    undefined,
    types.string
  )
  .addParam(
    "payloads",
    "The payloads of the proposal| Use comma separated values for multiple entries",
    undefined,
    types.string
  )
  .addOptionalParam(
    "account",
    "Named account or address of multiSig owner",
    undefined,
    types.string
  )
  .addFlag("useLedger", "Use ledger hardware wallet")
  .addFlag(USE_NODE_ACCOUNT_PARAM_NAME, USE_NODE_ACCOUNT_DESCRIPTION)
  .setAction(
    async ({ destinations, values, payloads, account, useLedger, useNodeAccount }, hre) => {
      try {
        const signer = await getSigner(hre, account, useLedger, useNodeAccount);
        await setLocalNodeDeploymentPath(hre);
        const multiSigContract = await hre.ethers.getContract("MultiSig");
        const tx = await multiSigContract
          .connect(signer)
          .submitProposal(destinations.split(","), values.split(","), payloads.split(","), {
            type: 0,
          });
        const receipt = await tx.wait();
        const events = receipt.events;
        if (events !== undefined) {
          for (var i = 0; i < events!.length; i++) {
            console.log(chalk.green("new event emitted:"), events[i].event, `(${events[i].args})`);
          }
        }
      } catch (error) {
        console.log(chalk.red("Error submitting proposal:"), error);
      }
    }
  );
