# Foundry deployment scripts

Forge port of the hardhat-deploy scripts in `legacy/deploy/`. `DeployCore.s.sol` replaces
`yarn deploy` (`hardhat stakedCelo:deploy --tags core`, i.e. `legacy/deploy/00_multisig.ts`
through `legacy/deploy/13_rebased_staked_celo.ts`), and `UpgradeImplementation.s.sol` replaces
re-running a single `legacy/deploy/NN_*.ts` file to push a new implementation.

| File | Purpose |
| --- | --- |
| `DeployBase.s.sol` | Network resolution, deployment records, ERC1967 proxy helper, console logging. |
| `DeployCore.s.sol` | Full protocol deployment: `CoreDeployer` holds the sequence, `DeployCore` is the `forge script` entry point. |
| `UpgradeImplementation.s.sol` | New implementation for one proxy, upgraded directly or handed to the MultiSig. |

## Environment

`DeployCore` reads the same variables the Hardhat scripts read from `.env`:

| Variable | Required | Meaning |
| --- | --- | --- |
| `TIME_LOCK_MIN_DELAY` | yes | MultiSig constructor argument, in seconds. |
| `TIME_LOCK_DELAY` | yes | MultiSig proposal delay, in seconds. Must be `>= TIME_LOCK_MIN_DELAY`. |
| `MULTISIG_REQUIRED_CONFIRMATIONS` | yes | Confirmations needed to execute a proposal. |
| `MULTISIG_OWNERS` | yes | Comma separated owner addresses. Replaces `MULTISIG_SIGNER_0..4`; the addresses must be distinct. |
| `NETWORK` | no | `deployments/` subdirectory. Defaults to the chain id: 42220 -> `celo`, 44787 -> `alfajores`, anything else -> `local`. |
| `CONTRACT` | for upgrades | Contract to upgrade, e.g. `Manager`. |

The deployer is the signer Forge is given (`--ledger`, `--private-key`, `--account`),
not a `DEPLOYER` variable. `DEPLOYER_PRIVATE_KEY` from `.env` can still be passed
explicitly as `--private-key "$DEPLOYER_PRIVATE_KEY"`.

The registry address passed to `Manager`, `Account`, `Vote` and `GroupHealth` is
`address(0)`, exactly as in the Hardhat scripts: `UsingRegistryUpgradeable` treats the
zero address as "use the canonical Registry at `0x0...ce10`".

## Deploying

```sh
eval "$(mise env -s zsh)"          # forge 1.8.1

forge clean                        # see "Build hygiene" below
forge script script/deploy/DeployCore.s.sol \
  --skip 'test/**' \
  --disable-code-size-limit \
  --rpc-url celo \
  --broadcast \
  --ledger            # or --private-key "$DEPLOYER_PRIVATE_KEY"
```

Drop `--broadcast` for a dry run; everything is simulated and the addresses are printed,
but note that the deployment records are still written (see "Failed runs").

Local devchain (anvil loaded with the Celo devchain state) additionally needs `--legacy`,
because the loaded chain has no fee history for EIP-1559 estimation:

```sh
NETWORK=local forge script script/deploy/DeployCore.s.sol \
  --skip 'test/**' --disable-code-size-limit --legacy \
  --rpc-url http://localhost:8545 --broadcast --private-key <anvil key>
```

### Why the extra flags

- `--disable-code-size-limit`: `Manager`, `Account` and `DefaultStrategy` compile to more
  than the 24576 byte EIP-170 limit under the production profile (no optimizer). Celo
  allows larger contracts, which is why the live implementations are that size too, but
  Forge refuses to simulate them without this flag.
- `--skip 'test/**'` after `forge clean`: see below.
- `--legacy`: only for the local devchain.

### Build hygiene

`foundry.toml` compiles `test/**` with via-ir through `compilation_restrictions`, so a
normal `forge build` leaves two artifacts per contract (`Manager.json` and
`Manager.test-via-ir.json`). When Forge maps a broadcast transaction back onto an
artifact it can pick the via-ir one and then fails to decode the constructor arguments of
`MultiSig`. Running `forge clean` and passing `--skip 'test/**'` keeps only the
production artifacts, which are the ones the script deploys anyway.

Run `forge clean && forge build` again afterwards, before `forge test`. An incremental
build on top of a `--skip 'test/**'` build leaves a mixed artifact set, and Forge then
cannot decide which `AddressSortedLinkedList` to link ("multiple library artifacts
resolve to the same key"). A full rebuild is the fix.

`AddressSortedLinkedList` is deployed and linked by Forge automatically, so the
"reuse the recorded library address" branch of `legacy/deploy/07_default_strategy.ts` has no
equivalent here. Pass `--libraries contracts/common/linkedlists/AddressSortedLinkedList.sol:AddressSortedLinkedList:<address>`
to reuse an already deployed library instead.

## Deployment records

Records are written to `deployments/<network>/` in the hardhat-deploy layout the CLI
scripts read:

```
Manager.json                 { address: <proxy>, implementation: <logic>, contract, chainId, deployer }
Manager_Proxy.json           same as above
Manager_Implementation.json  { address: <logic>, contract, chainId, deployer }
```

The `abi`, `receipt` and `args` fields hardhat-deploy wrote are not reproduced; the ABI
comes from the Forge artifacts in `out/` and the transaction details from
`broadcast/DeployCore.s.sol/<chainId>/run-latest.json`.

### Idempotency

Like hardhat-deploy, a contract that already has a record is reused and its deployment is
skipped, and the wiring steps are skipped once ownership has moved to the MultiSig:

```
MultiSig: reused 0xA9e6...
Manager: owned by MultiSig, propose setDependencies through the MultiSig
Account: already owned by MultiSig
```

This mirrors the `if (owner !== multisig.address)` guards in `legacy/deploy/08` to `legacy/deploy/12`.
Re-running against a fully deployed network therefore broadcasts nothing.

### Failed runs

Forge writes files during the simulation phase, so a run that fails while broadcasting
can leave records for contracts that never made it on chain. Delete the affected
`deployments/<network>/*.json` files before retrying, otherwise the next run reuses
addresses that hold no code.

## Upgrading one implementation

```sh
CONTRACT=Manager forge script script/deploy/UpgradeImplementation.s.sol \
  --skip 'test/**' --disable-code-size-limit \
  --rpc-url celo --broadcast --ledger
```

The script deploys the new implementation, then:

- if the broadcaster owns the proxy it calls `upgradeTo(newImplementation)` and refreshes
  `<Name>.json`, `<Name>_Proxy.json` and `<Name>_Implementation.json`;
- otherwise (the normal case, since the MultiSig owns everything after legacy/deploy/12) it
  prints the destination, value and `upgradeTo(address)` payload to submit through the
  MultiSig, and only writes `<Name>_Implementation.json`.

This replaces `catchNotOwnerForProxy` / `catchUpgradeErrorInMultisig`, which discovered
the same thing by letting the transaction revert on chain.

`MultiSig` has no `owner()` - it authorizes its own upgrades through a proposal - so
`CONTRACT=MultiSig` always prints the payload. It also re-reads `TIME_LOCK_MIN_DELAY`,
which is an immutable constructor argument of the implementation.

## Not ported

- `VALIDATOR_GROUPS` handling from `legacy/deploy/05` and `legacy/deploy/11` (calling
  `updateGroupHealth` and `activateGroup` for a list of groups after a first deployment).
- `deploy:devchain`, which mined extra blocks after deploying through Hardhat.

## Tests

`test/script/DeployCoreScriptTest.t.sol` runs the same sequence in-process against the
Celo devchain fixture through `CoreDeployer.runInProcess`, which pranks the deployer
instead of broadcasting and writes no records. It checks the proxies, the wiring, the
ownership transfers and that each implementation is byte-for-byte the compiled artifact.
