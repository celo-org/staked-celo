import { task, types } from "hardhat/config";

import { MULTISIG_REVOKE_CONFIRMATION } from "../tasksNames";

import {
  getSigner,
  getContract,
  revokeConfirmation,
  parseEvents,
} from "../helpers/multiSigInterfaceHelper";

task(MULTISIG_REVOKE_CONFIRMATION, "Revoke a proposal confirmation")
  .addParam("proposalId", "ID of the proposal", undefined, types.int)
  .addOptionalParam("namedAccount", "named account of multiSig owner", undefined, types.string)
  .addFlag("useLedger", "use ledger signer")
  .setAction(async ({ proposalId, namedAccount, useLedger }, hre) => {
    try {
      const signer = await getSigner(hre, namedAccount, useLedger);
      const multiSigContract = await getContract(hre);
      const receipt = await revokeConfirmation(multiSigContract, proposalId, signer);
      parseEvents(receipt, "ConfirmationRevoked");
    } catch (error) {
      console.log(error);
    }
  });
