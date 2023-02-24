// PARAM NAMES
export const ACCOUNT = "account";
export const AMOUNT = "amount";
export const BENEFICIARY = "beneficiary";
export const DESTINATIONS = "destinations";
export const PAYLOADS = "payloads";
export const PROPOSAL_ID = "proposalId";
export const OWNER_ADDRESS = "ownerAddress";
export const USE_LEDGER = "useLedger";
export const USE_NODE_ACCOUNT = "useNodeAccount";
export const VALUES = "values";
export const CONTRACT = "contract";
export const FUNCTION = "function";
export const ARGS = "args";
export const LOG_LEVEL = "logLevel";

// PARAM DESCRIPTIONS
export const AMOUNT_DESCRIPTION =
  "The amount of token to send. | This could be either CELO or stCELO";
export const BENEFICIARY_DESCRIPTION = "The address of the beneficiary to withdraw for.";
export const DESTINATIONS_DESCRIPTION =
  "The addresses at which the operations are targeted | Use comma separated values for multiple entries.";
export const ACCOUNT_DESCRIPTION = "The address or name of the account used to sign transactions.";
export const PAYLOADS_DESCRIPTION =
  "The payloads of the proposal | Use comma separated values for multiple entries.";
export const PROPOSAL_ID_DESCRIPTION = "The ID of the proposal.";
export const OWNER_ADDRESS_DESCRIPTION = "The address of the multiSig contract owner.";
export const USE_LEDGER_DESCRIPTION =
  "Determines if ledger hardware wallet is used for signing transactions.";
export const USE_NODE_ACCOUNT_DESCRIPTION =
  "Determines if node account is used for signing transactions. | This could be either a local or a remote node.";
export const VALUES_DESCRIPTION =
  "The CELO values involved in the proposal if any | Use comma separated values for multiple entries.";
export const CONTRACT_DESCRIPTION = "Name of the contract.";
export const FUNCTION_DESCRIPTION = "Name of the function.";
export const ARGS_DESCRIPTION = "Arguments of function separated by ,";
export const LOG_LEVEL_DESCRIPTION = "Specify logging level (e.g.: debug, info, warn, error).";

// ACCOUNT TASK DESCRIPTIONS
export const ACCOUNT_ACTIVATE_AND_VOTE_TASK_DESCRIPTION =
  "Activate CELO and vote for validator groups";
export const ACCOUNT_FINISH_PENDING_WITHDRAWAL_TASK_DESCRIPTION =
  "Finish a pending withdrawal created as a result of a `withdraw` call.";
export const ACCOUNT_GET_PENDING_WITHDRAWALS_TASK_DESCRIPTION =
  "Returns the pending withdrawals for a beneficiary.";
export const ACCOUNT_WITHDRAW_TASK_DESCRIPTION = "Withdraws CELO from account contract.";
export const ACCOUNT_REVOKE_TASK_DESCRIPTION = "Revokes votes from a validator group.";

// MANAGER TASK DESCRIPTIONS
export const MANAGER_DEPOSIT_TASK_DESCRIPTION = "Deposits CELO in staked CELO protocol.";
export const MANAGER_GET_GROUPS_TASK_DESCRIPTION = "Returns all groups voting for";
export const MANAGER_WITHDRAW_TASK_DESCRIPTION = "Withdraws stCELO from staked CELO protocol.";

// MULTISIG TASK DESCRIPTIONS
export const MULTISIG_CONFIRM_PROPOSAL_TASK_DESCRIPTION = "Confirm a multiSig proposal.";
export const MULTISIG_EXECUTE_PROPOSAL_TASK_DESCRIPTION = "Execute a multiSig proposal.";
export const MULTISIG_GET_CONFIRMATIONS_TASK_DESCRIPTION =
  "Get list of addresses that have confirmed a proposal.";
export const MULTISIG_GET_OWNERS_TASK_DESCRIPTION = "Get multiSig owners.";
export const MULTISIG_GET_PROPOSAL_TASK_DESCRIPTION = "Get a multiSig proposal by it's ID.";
export const MULTISIG_GET_TIMESTAMP_TASK_DESCRIPTION = "Get a proposal timestamp.";
export const MULTISIG_IS_CONFIRMED_TASK_DESCRIPTION =
  "Check if a proposal has been confirmed a multiSig owner.";
export const MULTISIG_IS_FULLY_CONFIRMED_TASK_DESCRIPTION =
  "Check if a proposal has been fully confirmed.";
export const MULTISIG_IS_OWNER_TASK_DESCRIPTION = "Check if an address is a multiSig owner.";
export const MULTISIG_IS_PROPOSAL_TIMELOCK_REACHED_TASK_DESCRIPTION =
  "Check if a proposal time-lock has been reached.";
export const MULTISIG_IS_SCHEDULED_TASK_DESCRIPTION = "Check if a proposal is scheduled.";
export const MULTISIG_REVOKE_CONFIRMATION_TASK_DESCRIPTION = "Revoke a proposal confirmation.";
export const MULTISIG_SCHEDULE_PROPOSAL_TASK_DESCRIPTION = "Schedule a proposal.";
export const MULTISIG_SUBMIT_PROPOSAL_TASK_DESCRIPTION =
  "Submit a proposal to the multiSig contract.";
export const MULTISIG_ENCODE_PROPOSAL_PAYLOAD_TASK_DESCRIPTION =
  "Encodes function payload on contract for proposal.";
export const MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES_DESCRIPTION =
  "Encodes manager set dependencies";
