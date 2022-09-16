export const BENEFICIARY_PARAM_NAME = "beneficiary";
export const FROM_PARAM_NAME = "from";
export const AMOUNT_PARAM_NAME = "amount";
export const DEPLOYMENTS_PATH_PARAM_NAME = "deploymentsPath";
export const USE_PRIVATE_KEY_PARAM_NAME = "usePrivateKey";
export const USE_LEDGER_PARAM_NAME = "useLedger";

export const BENEFICIARY_DESCRIPTION = "The address of the account to withdraw for.";
export const FROM_DESCRIPTION = "The address of the account used to sign transactions.";
export const AMOUNT_DESCRIPTION = "The amount of token to send.";
export const DEPLOYMENTS_PATH_DESCRIPTION =
  "Path of deployed contracts data. Used when connecting to a local node.";
export const USE_PRIVATE_KEY_DESCRIPTION =
  "Determines if private key in environment is used or not. Private key will be used automatically if network url is a remote host.";
export const USE_LEDGER_DESCRIPTION =
  "Determines if ledger hardware wallet is used or not. Private key will be used automatically if available.";

// ACCOUNT TASK DESCRIPTIONS
export const ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION =
  "Activate CELO and vote for validator groups";
export const ACCOUNT_WITHDRAW_TASK_DESCRIPTION = "Withdraws CELO from account contract.";
export const ACCOUNT_FINISH_PENDING_WITHDRAWAL_TASK_DESCRIPTION =
  "Finish a pending withdrawal created as a result of a `withdraw` call.";
export const ACCOUNT_GET_PENDING_WITHDRAWALS_TASK_DESCRIPTION =
  "Returns the pending withdrawals for a beneficiary";

// MANAGER TASK DESCRIPTION
export const MANAGER_DEPOSIT_TASK_DESCRIPTION = "Deposits CELO in staked CELO protocol.";
export const MANAGER_WITHDRAW_TASK_DESCRIPTION = "Withdraws stCELO from staked CELO protocol.";
