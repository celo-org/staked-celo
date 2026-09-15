# StakedCelo operational task scripts

Foundry ports of the Hardhat tasks that used to live in `legacy/lib/multiSig-tasks`,
`legacy/lib/manager-tasks` and `legacy/lib/account-tasks`. Every task has a counterpart here, and the
behaviour (which contracts are called, in which order, with which lesser/greater hints) is
preserved.

## How the scripts are wired

- Contract addresses come from `deployments/<network>/<Name>.json` (the `address` field of
  the hardhat-deploy files). The directory is picked by the `NETWORK` environment variable,
  defaulting to the network matching the chain id (42220 -> `celo`, 11142220 -> `sepolia`,
  44787 -> `alfajores`, 1101 -> `staging`, 31337 -> `local`). Set `NETWORK` explicitly when running against a
  fork.
- Celo core contracts (Election, LockedGold, Governance, ...) are resolved through the
  Registry at `0x000000000000000000000000000000000000ce10`, the same way the protocol
  contracts resolve them.
- Task parameters became environment variables. Comma separated lists keep the format the
  Hardhat parameters used.
- Task logic lives in `script/tasks/lib/*`, so `test/script/TaskScriptsTest.t.sol` runs the
  same code the scripts run. Each script keeps a thin `internal execute(...)` taking
  explicit parameters, with `run()` reading the environment and broadcasting.

## Signing

`--use-ledger` / `--use-node-account` / `DEPLOYER_PRIVATE_KEY` are replaced by the forge
script signer flags:

| Hardhat | forge |
| --- | --- |
| `--use-ledger` | `--ledger --sender <ledger address>` (add `--mnemonic-derivation-path` if not the default; without `--sender` the simulation runs as Forge's default account and owner-only calls revert before the device signs) |
| `--use-node-account --account <addr>` | `--unlocked --sender <addr>` |
| `DEPLOYER_PRIVATE_KEY` in the environment | `--private-key $DEPLOYER_PRIVATE_KEY` |

Read-only scripts need no signer. Scripts that send transactions only simulate unless
`--broadcast` is passed.

## Common flags

```
forge script <script> --rpc-url <celo|sepolia|alfajores|staging|local> [--broadcast] [signer flags]
```

`--rpc-url` accepts the aliases declared in `foundry.toml`. `sepolia` is Celo Sepolia
(11142220), the current testnet; `alfajores` (44787) is the one it replaces.

## MultiSig tasks

| Hardhat task | forge script | Environment variables |
| --- | --- | --- |
| `stakedCelo:multiSig:getOwners` | `script/tasks/multisig/GetOwners.s.sol` | `NETWORK` |
| `stakedCelo:multiSig:submitProposal --destinations --values --payloads` | `script/tasks/multisig/SubmitProposal.s.sol` | `DESTINATIONS`, `VALUES`, `PAYLOADS`, `NETWORK` |
| `stakedCelo:multiSig:confirmProposal --proposal-id` | `script/tasks/multisig/ConfirmProposal.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:revokeConfirmation --proposal-id` | `script/tasks/multisig/RevokeConfirmation.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:scheduleProposal --proposal-id` | `script/tasks/multisig/ScheduleProposal.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:executeProposal --proposal-id` | `script/tasks/multisig/ExecuteProposal.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:getProposal --proposal-id` | `script/tasks/multisig/GetProposal.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:getConfirmations --proposal-id` | `script/tasks/multisig/GetConfirmations.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:isFullyConfirmed --proposal-id` | `script/tasks/multisig/IsFullyConfirmed.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:isScheduled --proposal-id` | `script/tasks/multisig/IsScheduled.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:getTimestamp --proposal-id` | `script/tasks/multisig/GetTimestamp.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:isProposalTimelockReached --proposal-id` | `script/tasks/multisig/IsProposalTimelockReached.s.sol` | `PROPOSAL_ID`, `NETWORK` |
| `stakedCelo:multiSig:isOwner --owner-address` | `script/tasks/multisig/IsOwner.s.sol` | `OWNER_ADDRESS`, `NETWORK` |
| `stakedCelo:multiSig:isConfirmedBy --proposal-id --owner-address` | `script/tasks/multisig/IsConfirmedBy.s.sol` | `PROPOSAL_ID`, `OWNER_ADDRESS`, `NETWORK` |
| `stakedCelo:multiSig:encode:proposal:payload --contract --function --args` | `script/tasks/multisig/EncodeProposalPayload.s.sol` | `FUNCTION_SIGNATURE`, `ARGS`, `CONTRACT`, `NETWORK` |
| `stakedCelo:multisig:encode:managerSetDependencies` | `script/tasks/multisig/EncodeManagerSetDependencies.s.sol` | `NETWORK` |
| `stakedCelo:multiSig:update:v1:v2` | `script/tasks/multisig/UpdateV1ToV2.s.sol` | `VALIDATOR_GROUPS`, `NETWORK` |
| `stakedCelo:multiSig:update:v2:v3` | `script/tasks/multisig/UpdateV2ToV3.s.sol` | `NEW_MULTISIG_OWNER`, `NETWORK` |
| `stakedCelo:multiSig:update:v3:v4` | `script/tasks/multisig/UpdateV3ToV4.s.sol` | `NETWORK` |

## Manager tasks

| Hardhat task | forge script | Environment variables |
| --- | --- | --- |
| `stakedCelo:manager:deposit --amount` | `script/tasks/manager/Deposit.s.sol` | `AMOUNT`, `NETWORK` |
| `stakedCelo:manager:withdraw --amount` | `script/tasks/manager/Withdraw.s.sol` | `AMOUNT`, `NETWORK` |
| `stakedCelo:manager:getGroups` | `script/tasks/manager/GetGroups.s.sol` | `NETWORK` |
| `stakedCelo:manager:voteProposal --proposal-id --yes --no --abstain` | `script/tasks/manager/VoteProposal.s.sol` | `PROPOSAL_ID`, `YES`, `NO`, `ABSTAIN`, `NETWORK` |

## Account tasks

| Hardhat task | forge script | Environment variables |
| --- | --- | --- |
| `stakedCelo:account:activateAndVote` | `script/tasks/account/ActivateAndVote.s.sol` | `NETWORK` |
| `stakedCelo:account:revoke` | `script/tasks/account/Revoke.s.sol` | `NETWORK` |
| `stakedCelo:account:withdraw --beneficiary` | `script/tasks/account/Withdraw.s.sol` | `BENEFICIARY`, `NETWORK` |
| `stakedCelo:account:finishPendingWithdrawal --beneficiary` | `script/tasks/account/FinishPendingWithdrawal.s.sol` | `BENEFICIARY`, `NETWORK` |
| `stakedCelo:account:voteOverMax` | `script/tasks/account/CheckAllowedToVoteOverMaxNumberOfGroups.s.sol` | `NETWORK` |

## Environment variables

The encrypted per-network files (`yarn keys:decrypt` writes `.env.staging` and
`.env.alfajores`) are loaded by `scripts/with-env.sh <network> <command>`, since Forge
only reads `.env` by itself:

```bash
scripts/with-env.sh staging forge script script/tasks/multisig/GetOwners.s.sol --rpc-url staging
```


| Variable | Replaces | Format |
| --- | --- | --- |
| `NETWORK` | the deployments directory hardhat-deploy picked from the network name | `celo`, `sepolia`, `alfajores`, `staging` or `local`; optional, derived from the chain id (42220, 11142220, 44787, 1101, 31337) |
| `DESTINATIONS` | `--destinations` | comma separated addresses |
| `VALUES` | `--values` | comma separated integers (wei) |
| `PAYLOADS` | `--payloads` | comma separated `0x` payloads |
| `PROPOSAL_ID` | `--proposal-id` | integer |
| `OWNER_ADDRESS` | `--owner-address` | address |
| `BENEFICIARY` | `--beneficiary` | address |
| `AMOUNT` | `--amount` | integer (wei) |
| `YES` / `NO` / `ABSTAIN` | `--yes` / `--no` / `--abstain` | integer, default 0 |
| `CONTRACT` | `--contract` | deployment name, optional |
| `FUNCTION_SIGNATURE` | `--function` | full signature, e.g. `upgradeTo(address)` |
| `ARGS` | `--args` | comma separated arguments, empty for none |
| `VALIDATOR_GROUPS` | `VALIDATOR_GROUPS` (same name) | comma separated addresses |
| `NEW_MULTISIG_OWNER` | the owner hardcoded in `legacy/lib/multiSig-tasks/update-v2-to-v3.ts` | address, optional |

`--log-level` has no counterpart: use forge's `-v` levels for trace detail.

## Examples

Prepare and submit a Manager `setDependencies` proposal on Alfajores with a Ledger:

```bash
NETWORK=alfajores forge script script/tasks/multisig/EncodeManagerSetDependencies.s.sol \
  --rpc-url alfajores

NETWORK=alfajores \
DESTINATIONS=0x… VALUES=0 PAYLOADS=0x114e6b37… \
  forge script script/tasks/multisig/SubmitProposal.s.sol \
  --rpc-url alfajores --broadcast --ledger --sender <ledger address>
```

Confirm, schedule and execute it:

```bash
PROPOSAL_ID=7 forge script script/tasks/multisig/ConfirmProposal.s.sol \
  --rpc-url alfajores --broadcast --ledger --sender <ledger address>
PROPOSAL_ID=7 forge script script/tasks/multisig/ScheduleProposal.s.sol \
  --rpc-url alfajores --broadcast --ledger --sender <ledger address>
PROPOSAL_ID=7 forge script script/tasks/multisig/ExecuteProposal.s.sol \
  --rpc-url alfajores --broadcast --ledger --sender <ledger address>
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

## Differences from the Hardhat tasks

- `encode:proposal:payload` takes a full function signature instead of a bare function name:
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
- `encode:managerSetDependencies` and `update:v1:v2` no longer repair the deployment ABI file
  when hardhat-deploy refreshed only `<Name>_Implementation.json`: the scripts read addresses,
  never ABIs, from the deployment files.
- The account tasks returned `-1` from `Array.indexOf` when the Account contract was not
  voting for a group, which made ethers fail while encoding the call. The port reverts with
  `group not found in the account's voted group list` instead.
- Logging levels are gone; use forge's `-vvv` traces.

## Shared code

| File | Purpose |
| --- | --- |
| `lib/TaskVm.sol` | minimal cheatcode interface and console logger (forge-std needs pragma >=0.8.13) |
| `lib/TaskBase.sol` | deployment lookup, Registry lookup, network resolution |
| `lib/TaskInterfaces.sol` | minimal interfaces for the protocol and Celo core contracts |
| `lib/ElectionLib.sol` | `findLesserAndGreaterAfterVote` and the voted group index lookup |
| `lib/GroupsLib.sol` | the active and specific strategy group lists (`legacy/lib/task-utils.ts`) |
| `lib/AccountTaskLib.sol` | activateAndVote, revoke, withdraw, finishPendingWithdrawal |
| `lib/ManagerTaskLib.sol` | deposit, withdraw, voteProposal |
| `lib/MultiSigTaskLib.sol` | submit, confirm, revoke, schedule, execute |
| `lib/PayloadLib.sol` | calldata encoding from a signature and comma separated arguments |
| `lib/ProposalBuilder.sol` | accumulates destination / value / payload triples |
| `lib/UpgradeProposalLib.sol` | payload builders used by the `update:*` scripts |
| `lib/FormatLib.sol` | renders arrays as the comma separated strings the scripts print |
