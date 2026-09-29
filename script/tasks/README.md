# StakedCelo operational task scripts

Forge scripts for operating a StakedCelo deployment: inspecting and driving MultiSig
proposals, preparing upgrade proposals, depositing and withdrawing through the Manager, and
the Account maintenance calls (activating and revoking votes, finishing withdrawals).

## How the scripts are wired

- Contract addresses come from `deployments/<network>/<Name>.json` (the `address` field of
  the deployment record). The directory is picked by the `NETWORK` environment variable,
  defaulting to the network matching the chain id (42220 -> `celo`, 11142220 -> `sepolia`,
  31337 -> `local`). An anvil fork keeps the chain id of the chain it forks, so it
  resolves to that chain's records. A `NETWORK` set explicitly has to belong to the
  connected chain (`celo`, `sepolia` and `local` by their chain id, any other directory by its
  `.chainId` file), and a record carrying the chain id of another chain is refused, so
  `NETWORK=celo` against a Sepolia node stops instead of sending anything.
- Celo core contracts (Election, LockedGold, Governance, ...) are resolved through the
  Registry at `0x000000000000000000000000000000000000ce10`, the same way the protocol
  contracts resolve them.
- Parameters are environment variables; lists are comma separated.
- Task logic lives in `script/tasks/lib/*`, so `test/script/TaskScriptsTest.t.sol` runs the
  same code the scripts run. Each script keeps a thin `internal execute(...)` taking
  explicit parameters, with `run()` reading the environment and broadcasting.

## Signing

Scripts that send transactions sign with forge's signer flags:

| Signer | forge flags |
| --- | --- |
| Ledger | `--ledger --sender <ledger address>` (add `--mnemonic-derivation-path` if not the default; without `--sender` the simulation runs as Forge's default account and owner-only calls revert before the device signs) |
| Unlocked node account | `--unlocked --sender <addr>` |
| Private key | `--private-key $DEPLOYER_PRIVATE_KEY` |

Read-only scripts need no signer. Scripts that send transactions only simulate unless
`--broadcast` is passed.

## Common flags

```
forge script <script> --rpc-url <celo|sepolia|local> [--broadcast] [signer flags]
```

`--rpc-url` accepts the aliases declared in `foundry.toml`. `sepolia` is Celo Sepolia
(11142220), the current testnet. Use forge's `-v` levels (`-vvv`) for trace detail.

Every script also reads `NETWORK` (see above); the tables below list only the other
variables.

## MultiSig scripts

| Script | What it does | Environment variables |
| --- | --- | --- |
| `multisig/GetOwners.s.sol` | prints the MultiSig owners | |
| `multisig/SubmitProposal.s.sol` | submits a proposal of destination / value / payload triples | `DESTINATIONS`, `VALUES`, `PAYLOADS` |
| `multisig/ConfirmProposal.s.sol` | confirms a proposal | `PROPOSAL_ID` |
| `multisig/RevokeConfirmation.s.sol` | revokes the sender's confirmation of a proposal | `PROPOSAL_ID` |
| `multisig/ScheduleProposal.s.sol` | schedules a fully confirmed proposal, starting its time-lock | `PROPOSAL_ID` |
| `multisig/ExecuteProposal.s.sol` | executes a scheduled proposal after checking that its time-lock has elapsed | `PROPOSAL_ID` |
| `multisig/GetProposal.s.sol` | prints a proposal's destinations, values and payloads | `PROPOSAL_ID` |
| `multisig/GetConfirmations.s.sol` | prints the owners that confirmed a proposal | `PROPOSAL_ID` |
| `multisig/IsFullyConfirmed.s.sol` | prints whether a proposal has the required confirmations | `PROPOSAL_ID` |
| `multisig/IsScheduled.s.sol` | prints whether a proposal is scheduled | `PROPOSAL_ID` |
| `multisig/GetTimestamp.s.sol` | prints the timestamp at which a proposal becomes executable | `PROPOSAL_ID` |
| `multisig/IsProposalTimelockReached.s.sol` | prints whether a proposal's time-lock has been reached | `PROPOSAL_ID` |
| `multisig/IsOwner.s.sol` | prints whether an address is a MultiSig owner | `OWNER_ADDRESS` |
| `multisig/IsConfirmedBy.s.sol` | prints whether an owner confirmed a proposal | `PROPOSAL_ID`, `OWNER_ADDRESS` |
| `multisig/EncodeProposalPayload.s.sol` | encodes a function call as a proposal payload (see below) | `FUNCTION_SIGNATURE`, `ARGS`, `CONTRACT` |
| `multisig/EncodeManagerSetDependencies.s.sol` | encodes the `Manager.setDependencies` proposal from the deployed addresses | |
| `multisig/UpdateV1ToV2.s.sol` | prepares the V1 to V2 upgrade proposal; with `--broadcast` also sends `updateGroupHealth` for listed groups GroupHealth does not consider valid | `VALIDATOR_GROUPS` |
| `multisig/UpdateV2ToV3.s.sol` | prepares the V2 to V3 upgrade proposal | `NEW_MULTISIG_OWNER` |
| `multisig/UpdateV3ToV4.s.sol` | prepares the V3 to V4 upgrade proposal (Manager, both strategies, Account) | |

The scripts read addresses, never ABIs, from the deployment files, so a record whose ABI is
out of step with `<Name>_Implementation.json` does not affect them.

## Manager scripts

| Script | What it does | Environment variables |
| --- | --- | --- |
| `manager/Deposit.s.sol` | deposits CELO and receives stCELO | `AMOUNT` |
| `manager/Withdraw.s.sol` | withdraws stCELO, scheduling the CELO withdrawal | `AMOUNT` |
| `manager/GetGroups.s.sol` | prints the groups the protocol is voting for | |
| `manager/VoteProposal.s.sol` | votes on a Celo governance proposal with the sender's stCELO | `PROPOSAL_ID`, `YES`, `NO`, `ABSTAIN` |

## Account scripts

| Script | What it does | Environment variables |
| --- | --- | --- |
| `account/ActivateAndVote.s.sol` | activates pending votes and votes the scheduled CELO for every group the protocol votes for | |
| `account/Revoke.s.sol` | revokes the scheduled votes of every group the protocol votes for | |
| `account/Withdraw.s.sol` | withdraws a beneficiary's scheduled CELO from the Account contract, group by group | `BENEFICIARY` |
| `account/FinishPendingWithdrawal.s.sol` | finishes a beneficiary's pending withdrawals once LockedGold has released them | `BENEFICIARY` |
| `account/CheckAllowedToVoteOverMaxNumberOfGroups.s.sol` | prints whether the Account contract may vote for more than the maximum number of groups | |

Paths are relative to `script/tasks/`. The account scripts revert with
`group not found in the account's voted group list` when the Account contract is not voting
for a group they need to pass lesser/greater hints for.

## Environment variables

A per-network `.env.<network>` file is loaded by `scripts/with-env.sh <network> <command>`,
since Forge only reads `.env` by itself:

```bash
scripts/with-env.sh celo forge script script/tasks/multisig/GetOwners.s.sol --rpc-url celo
```

| Variable | Format |
| --- | --- |
| `NETWORK` | `celo`, `sepolia` or `local`; optional, derived from the chain id (42220, 11142220, 31337); set explicitly, it has to belong to the connected chain |
| `DESTINATIONS` | comma separated addresses |
| `VALUES` | comma separated integers (wei) |
| `PAYLOADS` | comma separated `0x` payloads |
| `PROPOSAL_ID` | integer |
| `OWNER_ADDRESS` | address |
| `BENEFICIARY` | address |
| `AMOUNT` | integer (wei) |
| `YES` / `NO` / `ABSTAIN` | integer, default 0 |
| `CONTRACT` | deployment name, e.g. `Manager`, optional; when set, its address is printed as the proposal destination |
| `FUNCTION_SIGNATURE` | full signature, e.g. `upgradeTo(address)` |
| `ARGS` | comma separated arguments, empty for none |
| `VALIDATOR_GROUPS` | comma separated addresses, optional; groups to activate in DefaultStrategy |
| `NEW_MULTISIG_OWNER` | address, optional; the owner the V2 to V3 proposal adds, defaults to `DEFAULT_NEW_OWNER` in `UpdateV2ToV3.s.sol` |

## Encoding proposal payloads

`EncodeProposalPayload.s.sol` takes a full function signature, not a bare function name:
Solidity has no runtime ABI to look the parameter types up in. It encodes one 32 byte word
per argument, so it supports only the single word static types StakedCelo proposals use:

| Parameter type | `ARGS` entry |
| --- | --- |
| `address` | `0x` and 40 hex digits, any casing |
| `bool` | `true` or `false` |
| `bytes32` | `0x` and 64 hex digits |
| `uint8`, `uint16`, … `uint256` (steps of 8) | decimal digits, must fit the width |
| `int8`, `int16`, … `int256` (steps of 8) | decimal digits with an optional leading `-`, must fit the width |

Everything else - arrays, tuples, `string`, `bytes`, other `bytesN`, and the non canonical
`uint` / `int` aliases - is rejected by name, because a payload encoded as one word for a
type that needs head/tail encoding would be accepted by the MultiSig and then fail to
execute. Values are checked against their declared type as well, so an out of range
`uint8`, a non decimal integer, a short address or an argument count that does not match
the signature stops the encoding instead of producing a wrong payload.
The signature itself must be canonical, without whitespace, because the selector is the
hash of the exact text (`setMinCountOfActiveGroups( uint256 )` would select a different
function); such signatures are rejected too.

## Examples

Prepare and submit a Manager `setDependencies` proposal on Celo Sepolia with a Ledger:

```bash
NETWORK=sepolia forge script script/tasks/multisig/EncodeManagerSetDependencies.s.sol \
  --rpc-url sepolia

NETWORK=sepolia \
DESTINATIONS=0x… VALUES=0 PAYLOADS=0x114e6b37… \
  forge script script/tasks/multisig/SubmitProposal.s.sol \
  --rpc-url sepolia --broadcast --ledger --sender <ledger address>
```

Confirm, schedule and execute it:

```bash
PROPOSAL_ID=7 forge script script/tasks/multisig/ConfirmProposal.s.sol \
  --rpc-url sepolia --broadcast --ledger --sender <ledger address>
PROPOSAL_ID=7 forge script script/tasks/multisig/ScheduleProposal.s.sol \
  --rpc-url sepolia --broadcast --ledger --sender <ledger address>
PROPOSAL_ID=7 forge script script/tasks/multisig/ExecuteProposal.s.sol \
  --rpc-url sepolia --broadcast --ledger --sender <ledger address>
```

Run the daily account maintenance with a private key:

```bash
forge script script/tasks/account/ActivateAndVote.s.sol \
  --rpc-url celo --broadcast --private-key "$DEPLOYER_PRIVATE_KEY"
forge script script/tasks/account/Revoke.s.sol \
  --rpc-url celo --broadcast --private-key "$DEPLOYER_PRIVATE_KEY"
BENEFICIARY=0x… forge script script/tasks/account/Withdraw.s.sol \
  --rpc-url celo --broadcast --private-key "$DEPLOYER_PRIVATE_KEY"
BENEFICIARY=0x… forge script script/tasks/account/FinishPendingWithdrawal.s.sol \
  --rpc-url celo --broadcast --private-key "$DEPLOYER_PRIVATE_KEY"
```

## Shared code

| File | Purpose |
| --- | --- |
| `lib/TaskVm.sol` | minimal cheatcode interface and console logger (forge-std needs pragma >=0.8.13) |
| `lib/TaskBase.sol` | deployment lookup, Registry lookup, network resolution |
| `lib/TaskInterfaces.sol` | minimal interfaces for the protocol and Celo core contracts |
| `lib/ElectionLib.sol` | `findLesserAndGreaterAfterVote` and the voted group index lookup |
| `../common/NetworkCheck.sol` | checks that a deployments directory and its records belong to the connected chain; shared with the deploy scripts |
| `lib/GroupsLib.sol` | the active and specific strategy group lists |
| `lib/AccountTaskLib.sol` | activateAndVote, revoke, withdraw, finishPendingWithdrawal |
| `lib/ManagerTaskLib.sol` | deposit, withdraw, voteProposal |
| `lib/MultiSigTaskLib.sol` | submit, confirm, revoke, schedule, execute |
| `lib/PayloadLib.sol` | calldata encoding from a signature and comma separated arguments |
| `lib/ProposalBuilder.sol` | accumulates destination / value / payload triples |
| `lib/UpgradeProposalLib.sol` | payload builders used by the `update:*` scripts |
| `lib/FormatLib.sol` | renders arrays as the comma separated strings the scripts print |
