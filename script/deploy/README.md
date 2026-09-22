# Foundry deployment scripts

Forge port of the Hardhat era hardhat-deploy scripts (`deploy/00` .. `deploy/13`, in git history). `DeployCore.s.sol` replaces
`yarn deploy` (`hardhat stakedCelo:deploy --tags core`, i.e. `deploy/00_multisig.ts`
through `deploy/13_rebased_staked_celo.ts`), and `UpgradeImplementation.s.sol` replaces
re-running a single `deploy/NN_*.ts` file to push a new implementation.

| File | Purpose |
| --- | --- |
| `DeployBase.s.sol` | Network resolution, deployment records, ERC1967 proxy helper, console logging. |
| `DeployCore.s.sol` | Full protocol deployment: the `deploy/00` .. `deploy/13` sequence and the `forge script` entry point. |
| `UpgradeImplementation.s.sol` | New implementation for one proxy, upgraded directly or handed to the MultiSig. |

## Environment

`DeployCore` reads the same variables the Hardhat scripts read from `.env`:

| Variable | Required | Meaning |
| --- | --- | --- |
| `TIME_LOCK_MIN_DELAY` | yes | MultiSig constructor argument, in seconds. |
| `TIME_LOCK_DELAY` | yes | MultiSig proposal delay, in seconds. Must be `>= TIME_LOCK_MIN_DELAY`. |
| `MULTISIG_REQUIRED_CONFIRMATIONS` | yes | Confirmations needed to execute a proposal. |
| `MULTISIG_OWNERS` | yes, or the variables below | Comma separated owner addresses; the addresses must be distinct. |
| `MULTISIG_SIGNER_0`, `MULTISIG_SIGNER_1`, ... | yes, or the variable above | The Hardhat era named accounts, still accepted. Read from `MULTISIG_SIGNER_0` upwards until one is unset, and only when `MULTISIG_OWNERS` is empty. |
| `NETWORK` | no | `deployments/` subdirectory. Defaults to the chain id: 42220 -> `celo`, 11142220 -> `sepolia`, anything else -> `local`. |
| `VALIDATOR_GROUPS` | no | Comma separated validator groups to make healthy and activate. Empty by default, which skips both steps. |
| `CONTRACT` | for upgrades | Contract to upgrade, e.g. `Manager`. Read by `UpgradeImplementation` only. |

Either spelling of the owner set works, so a per-network env file written for the Hardhat
tooling can be used as it is. Forge itself only reads `.env`, so start the scripts through
`scripts/with-env.sh <network> ...` (or `yarn with-env <network> ...`), which exports
`.env.<network>` first, e.g.
`scripts/with-env.sh celo forge script script/deploy/DeployCore.s.sol --rpc-url celo ...`;
variables already exported win over the file. `.env.example`
shows the canonical form and keeps the legacy one commented out next to it. When neither
yields a single owner the script stops with
`set MULTISIG_OWNERS, or MULTISIG_SIGNER_0, MULTISIG_SIGNER_1, ...` instead of failing
somewhere inside the MultiSig initializer.

`UpgradeImplementation` needs `CONTRACT` and, for `CONTRACT=MultiSig` only,
`TIME_LOCK_MIN_DELAY` - it is an immutable constructor argument of the implementation.

The deployer is the signer Forge is given (`--ledger`, `--private-key`, `--account`), not a
`DEPLOYER` variable - `DEPLOYER` is still in `.env.example` for the Hardhat era tooling and
is ignored here. `DEPLOYER_PRIVATE_KEY` from `.env` is not read either; pass it explicitly
as `--private-key "$DEPLOYER_PRIVATE_KEY"`.

Which account that is, is read out of the broadcast itself (`vm.readCallers()` inside
`vm.startBroadcast()`) rather than from `msg.sender`. The two are not the same account when
the signer is not the simulation sender: with `--ledger` and no `--sender`, `msg.sender` is
Forge's default sender `0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38` while the transactions
are signed by the device, and taking the deployer from it would initialize every contract
as owned by an address nobody holds the key to. A run that reaches the broadcast with that
default sender stops before the first transaction:

```
DeployCore: pass --sender/--private-key/--ledger with --sender
```

`UpgradeImplementation` does the same, and uses the broadcaster for its `owner()` check.

The registry address passed to `Manager`, `Account`, `Vote` and `GroupHealth` is
`address(0)`, exactly as in the Hardhat scripts: `UsingRegistryUpgradeable` treats the
zero address as "use the canonical Registry at `0x0...ce10`".

## Deploying

```sh
eval "$(mise env -s zsh)"          # forge 1.8.1

forge script script/deploy/DeployCore.s.sol \
  --disable-code-size-limit \
  --rpc-url celo \
  --broadcast \
  --ledger --sender <ledger address>   # or --private-key "$DEPLOYER_PRIVATE_KEY"
```

Drop `--broadcast` for a dry run; everything is simulated and the addresses are printed.
The deployment records are written even then, but a record whose address holds no code on
the target chain is ignored by the next run, so a dry run can be followed by the real one.

`contracts/`, `test/` and `script/` are compiled with one and the same profile, so `out/`
holds exactly one artifact per contract and nothing has to be skipped or cleaned before a
deploy. `--disable-code-size-limit` is the only extra flag a mainnet deploy needs.

### Signing with a Ledger

`--ledger` signs with the first account of the default derivation path. `--sender
<address>` is required next to it: the simulation has to run as the account that will
actually broadcast, and the script stops if it does not. Use
`--mnemonic-derivation-paths "m/44'/60'/0'/0/<i>"` for another account.
The device has to be unlocked with the Ethereum app open and blind signing enabled -
every transaction here is a contract creation or a contract call.

The Ledger path was not exercised during the Foundry migration (the scripts were run with
a private key against a local devchain and read-only against mainnet). Before the first
real use, run the script once without `--broadcast` with the device attached, and confirm
the printed sender matches the expected Ledger account.

### Why `--disable-code-size-limit`

Three implementations are larger than the 24576 byte EIP-170 limit under the production
profile (solc 0.8.11, no optimizer, no via-ir):

| Contract | Deployed size |
| --- | --- |
| `Manager` | 26595 |
| `DefaultStrategy` | 25957 |
| `Account` | 24911 |

Celo has always allowed larger contracts, which is why the live implementations are that
size too, but Forge applies the EIP-170 limit while simulating the broadcast and aborts
with `` `DefaultStrategy` is above the contract size limit `` without the flag. The
in-process script execution is not affected, so the failure only shows up once the
transactions are prepared.

### Fee estimation on a local node

The scripts broadcast EIP-1559 transactions. Add `--legacy` when the node exposes no base
fee or fee history - an anvil started from a `--load-state` snapshot, for example. An
anvil started with `--init <genesis>` as described below does have a base fee, so
`--legacy` is not needed there.

### Validator groups

`VALIDATOR_GROUPS` gives the protocol the groups it votes for on a first deployment, the
same way it did in `deploy/05` and `deploy/11`:

- right after `GroupHealth` is deployed, `updateGroupHealth(group)` is called for every
  listed group, which records whether the group is a registered validator group with an
  elected member and an untouched slashing multiplier;
- right after `DefaultStrategy.setDependencies`, every listed group that came out healthy
  is passed to `addActivatableGroup(group)` and then `activateGroup(group, 0, tail)`.

Groups are activated in descending order of the CELO the `Account` holds for them
(`Account.getCeloForGroup`), which on a first deployment is zero everywhere, so they end
up in the sorted list in the order they were listed in - the first entry becomes the head.

The two steps are skipped, with a log line, in the situations the Hardhat scripts skipped
them in:

```
GroupHealth: reused 0x1b6b...                                   # health is not refreshed
DefaultStrategy: owned by MultiSig, propose setDependencies through the MultiSig
DefaultStrategy: Manager owned by MultiSig, activate the groups through it
DefaultStrategy: group is not healthy, not activated 0x5409...
DefaultStrategy: group already active 0x70997...
```

`addActivatableGroup` is `onlyOwner`, so the groups can only be activated while the
deployer still owns the `DefaultStrategy` - that is, during the run that deploys it. Once
the MultiSig owns it, `addActivatableGroup` and `activateGroup` have to go through a
proposal, the same as `setDependencies`. A group that is already activatable or already
active is left alone, so an interrupted run can simply be repeated.

Add `--gas-estimate-multiplier 200` whenever `VALIDATOR_GROUPS` is set. While it walks the
elected validator set, `updateGroupHealth` flags the group members in a scratch mapping
and clears it again, and the clearing earns a storage refund. Forge sizes the transaction
from the gas the simulation reports *after* that refund (plus 30%), which is less than the
transaction needs while it runs, so the broadcast fails even though the simulation and an
`eth_call` both succeed:

```
Error: Transaction Failure: 0x3312...
```

### Library linking

`AddressSortedLinkedList` is deployed and linked by Forge automatically, so the "reuse the
recorded library address" branch of `deploy/07_default_strategy.ts` has no equivalent
here. Pass
`--libraries contracts/common/linkedlists/AddressSortedLinkedList.sol:AddressSortedLinkedList:<address>`
to reuse an already deployed library instead.

The library ends up at an address of its own and has to be verified like any other
contract, so `DeployCore` writes it to `AddressSortedLinkedList_Implementation.json`
next to the rest. hardhat-deploy instead noted it under `libraries` in
`DefaultStrategy_Implementation.json`; `scripts/verify-contracts.sh` reads both.

## Deployment records

Records are written to `deployments/<network>/` in the hardhat-deploy layout the CLI
scripts read:

```
Manager.json                                 { address: <proxy>, implementation: <logic>, args, contract, chainId, deployer }
Manager_Proxy.json                           same as above
Manager_Implementation.json                  { address: <logic>, args, contract, chainId, deployer }
AddressSortedLinkedList_Implementation.json  { address: <library>, args, contract, chainId, deployer }
```

`args` holds the constructor arguments in the shape hardhat-deploy wrote them: the
implementation address and the initializer calldata for a proxy record, `minDelay` for the
`MultiSig` implementation, and an empty array for the implementations that take none.
`scripts/verify-contracts.sh` ABI-encodes them; an explorer cannot reproduce the creation
code without them. Numbers are written as decimal strings rather than as JSON numbers -
Forge's serializer is typed, and both `cast abi-encode` and the verification script read
either form.

A proxy record refreshed by `UpgradeImplementation` is the one exception: the proxy was
constructed by an earlier run and its arguments are not known there, so `args` comes out
empty and verification falls back to `--guess-constructor-args`.

The `abi` and `receipt` fields hardhat-deploy wrote are not reproduced; the ABI comes from
the Forge artifacts in `out/` and the transaction details from
`broadcast/DeployCore.s.sol/<chainId>/run-latest.json`.

### Idempotency

Like hardhat-deploy, a contract that already has a record is reused and its deployment is
skipped (unless the recorded address has no code on the chain, which is what a dry run or
a failed broadcast leaves behind), and the wiring steps are skipped once ownership has
moved to the MultiSig:

```
MultiSig: reused 0xA9e6...
Manager: owned by MultiSig, propose setDependencies through the MultiSig
Account: already owned by MultiSig
```

This mirrors the `if (owner !== multisig.address)` guards in `deploy/08` to `deploy/12`.
Re-running against a fully deployed network therefore broadcasts nothing and ends with
`Warning: No transactions to broadcast.`

### Failed runs

Forge writes files during the simulation phase, so a run that fails while broadcasting
can leave records for contracts that never made it on chain. Delete the affected
`deployments/<network>/*.json` files before retrying, otherwise the next run reuses
addresses that hold no code. The three files of one contract always have to go together:
`<Name>.json`, `<Name>_Proxy.json` and `<Name>_Implementation.json`.

## Upgrading one implementation

```sh
CONTRACT=Manager forge script script/deploy/UpgradeImplementation.s.sol \
  --disable-code-size-limit \
  --rpc-url celo --broadcast --ledger --sender <ledger address>
```

The script deploys the new implementation, then:

- if the broadcaster owns the proxy it calls `upgradeTo(newImplementation)` and refreshes
  `<Name>.json`, `<Name>_Proxy.json` and `<Name>_Implementation.json`;
- otherwise (the normal case, since the MultiSig owns everything after `deploy/12`) it
  prints the destination, value and `upgradeTo(address)` payload to submit through the
  MultiSig, and only writes `<Name>_Implementation.json`:

```
Manager: proxy 0x3fdc08D815cc4ED3B7F69Ee246716f2C8bCD6b07
Manager: current implementation 0x1E3b98102e19D3a164d239BdD190913C2F02E756
Broadcaster does not own the proxy; submit this through the MultiSig:
  destination 0x3fdc08D815cc4ED3B7F69Ee246716f2C8bCD6b07
  value 0
  payload 0x3659cfe6000000000000000000000000c32609c91d6b6b51d48f2611308fef121b02041f
Manager: new implementation 0xC32609C91d6B6b51D48f2611308FEf121B02041f
```

Feed those three values to `MultiSig.submitProposal([destination], [value], [payload])`,
collect the confirmations, wait out the delay and execute. `<Name>.json` keeps pointing at
the old implementation until the proposal has gone through, which is intentional: it
records what the proxy actually delegates to.

This replaces `catchNotOwnerForProxy` / `catchUpgradeErrorInMultisig`, which discovered
the same thing by letting the transaction revert on chain.

`MultiSig` has no `owner()` - it authorizes its own upgrades through a proposal - so
`CONTRACT=MultiSig` always prints the payload.

`CONTRACT=DefaultStrategy` also redeploys `AddressSortedLinkedList`: Forge links the
library into every new implementation it builds, and the library is a contract of its own
on chain. `AddressSortedLinkedList_Implementation.json` is rewritten with the new address
on that path, the same way `DeployCore` records it, so the verification script does not
keep submitting the library of the previous deployment. Pass `--libraries ...` (see
"Library linking") to link an already deployed one instead, in which case the record simply
keeps pointing at it.

### A run without `--broadcast` rewrites the record too

Forge simulates the whole script before it broadcasts anything, and the records are written
by that simulation. `UpgradeImplementation` therefore rewrites
`<Name>_Implementation.json` - and, for `CONTRACT=DefaultStrategy`,
`AddressSortedLinkedList_Implementation.json` - even without `--broadcast`, naming an
implementation that only ever existed inside the simulation and holds no code on the chain.
The run says so after it prints the new implementation:

```
note: deployments/celo/Manager_Implementation.json was written by the simulation as well;
      it only names a deployed contract once this run was broadcast.
      A dry run has to be repeated with --broadcast, which deploys again and
      replaces the record with the address that went on chain.
```

Nothing has to be cleaned up: repeating the run with `--broadcast` deploys a fresh
implementation and overwrites the record with the address that went on chain, so the dry
run's address is never reused. Until then the leftover is refused rather than acted on -
the MultiSig upgrade tasks stop with `record <Name>_Implementation.json points at an
address without code on this chain (dry-run leftover?)` instead of proposing an `upgradeTo`
that would leave the proxy delegating to nothing, and `scripts/verify-contracts.sh` warns
and skips the record instead of submitting it.

## Verifying deployed contracts

`scripts/verify-contracts.sh` (also `yarn verify`) replaces `yarn verify:deploy`
(`hardhat sourcify`). It walks `deployments/<network>/` and submits every recorded address
to Sourcify and, when an API key is around, to Celoscan:

```sh
eval "$(mise env -s zsh)"

scripts/verify-contracts.sh --dry-run celo        # print the forge commands
scripts/verify-contracts.sh --watch celo          # everything, waiting for each result
scripts/verify-contracts.sh celo Manager          # one contract
scripts/verify-contracts.sh --dry-run sepolia     # Celo Sepolia
CELOSCAN_API_KEY=... scripts/verify-contracts.sh --watch celo

yarn verify --watch celo                          # same thing through package.json
```

A network with no `deployments/<network>/` directory is not an error: the script prints the
chain, the explorer endpoint and `nothing to verify`, which is the quickest way to see what
a network resolves to.

Each contract has two addresses on chain and both are submitted: the implementation from
`<Name>_Implementation.json` as `contracts/<Name>.sol:<Name>`, and the proxy in front of
it from `<Name>_Proxy.json` as
`@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy`. The library
`AddressSortedLinkedList` is submitted as well; it is a contract of its own on chain.

| Variable | Meaning |
| --- | --- |
| `CELOSCAN_API_KEY` | API key for the explorer. Celoscan is part of the Etherscan V2 API now, so this is an **etherscan.io** key (one key, every chain in that API); a V1-era Celoscan key is not one. `ETHERSCAN_API_KEY` (the name in `.env.example`) and `CELO_SCAN_API_KEY` (the Hardhat era one) are accepted too. Without one only Sourcify is used - it needs no key. |
| `LIBRARY_ADDRESS` | `AddressSortedLinkedList` address, for records that carry neither the `libraries` map nor an `AddressSortedLinkedList_Implementation.json`. |
| `CHAIN_ID` | Chain id, for a network the script has no entry for. It knows `celo` (42220) and `sepolia` (11142220); for anything else it asks the node. |
| `ETH_RPC_URL` | Node to read the chain id and proxy creation code from, overriding the built-in endpoint. |

### Why this works with contracts deployed before the port

The production profile reproduces the Hardhat build byte for byte, metadata trailer
included - that is what `foundry.toml` pins (`solc 0.8.11`, `evm istanbul`, optimizer off,
`use_literal_content`, `bytecode_hash = "ipfs"`) and what `scripts/bytecode-compat-check.ts`
checks on every CI run. A contract deployed by the Hardhat tooling therefore still verifies
as a full match from these sources, as long as the source itself has not changed since it
was deployed. Check which implementations still qualify before submitting anything:

```sh
node scripts/bytecode-compat-check.ts --deployments celo
```

Contracts reported as `DIFF` there have been edited since they were deployed and will come
back from Sourcify as `bytecode_length_mismatch` or a partial match. That is a correct
result, not a tooling problem: verify those addresses from the commit they were deployed
from. The script exits non-zero when any submission fails.

### Constructor arguments

`ERC1967Proxy(address _logic, bytes _data)` takes the implementation and the initializer
calldata, and the `MultiSig` implementation takes `uint256 _minDelay`. An explorer only
reproduces the creation code when it is given them, so a submission without them fails for
those addresses.

The script takes the values from the `args` field of the deployment record and ABI-encodes
them against the constructor of the matching artifact in `out/`, so a contract whose
constructor changes needs no change here. Records written by `DeployCore` carry `args`
just as the hardhat-deploy ones do; a record that has none - one from a `DeployCore` run
that predates the field, or a proxy record refreshed by `UpgradeImplementation` - falls
back to `--guess-constructor-args`, which recovers the arguments from the creation code on
chain. Right after a deploy they can also be read out of
`broadcast/DeployCore.s.sol/<chainId>/run-latest.json` and passed by hand:

```sh
forge verify-contract <proxy> \
  '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy' \
  --chain 42220 --verifier sourcify \
  --constructor-args "$(cast abi-encode 'constructor(address,bytes)' <implementation> <initializeCalldata>)"

forge verify-contract <multiSigImplementation> contracts/common/MultiSig.sol:MultiSig \
  --chain 42220 --verifier sourcify \
  --constructor-args "$(cast abi-encode 'constructor(uint256)' 345600)"
```

### The linked library

`DefaultStrategy` is compiled unlinked - `settings.libraries` is empty in the metadata of
the deployed code - and `AddressSortedLinkedList` is substituted into the bytecode at
deploy time. Verification has to be submitted the same way, so the script does *not* pass
`--libraries`: adding an address there puts it into `settings.libraries`, which changes the
metadata hash and with it the last 32 bytes of the deployed bytecode, and the match fails.
Sourcify resolves the library placeholders from the deployed code itself. `--link-libraries`
forces the address in anyway, for a verifier that cannot.

### Networks

Celoscan is served by the unified **Etherscan V2** API: one host, `https://api.etherscan.io/v2/api`,
with the chain picked by a `chainid` query parameter. The per-explorer V1 endpoint it
replaced (`api.celoscan.io`) was retired in August 2025 and now answers every request
with `You are using a deprecated V1 endpoint`. An
**etherscan.io** API key is what V2 authenticates with, and one key covers every chain in
it.

Forge resolves that endpoint on its own from `--chain` for the chains it knows, which is
why the `[etherscan]` entry in `foundry.toml` needs a key and a chain but no `url`. It
does *not* append `chainid` to a `--verifier-url` it is handed, so the script passes the
parameter itself and covers the chains forge has no entry for.

| Network | Chain | Sourcify | Etherscan V2 |
| --- | --- | --- | --- |
| `celo` | 42220 | yes | `https://api.etherscan.io/v2/api?chainid=42220` |
| `sepolia` (Celo Sepolia) | 11142220 | yes | `https://api.etherscan.io/v2/api?chainid=11142220` |

Mainnet and Celo Sepolia are fully covered. `sourcify.dev/server/chains` lists Celo
Mainnet and `Celo Sepolia Testnet` (11142220) as supported, and Etherscan V2 lists both
(`https://api.etherscan.io/v2/chainlist`).

Any other chain needs `CHAIN_ID` and `ETH_RPC_URL`, and is only verifiable if a service
covers it.

## Local devchain

The devchain fixture in `test/devchain/` is a state dump of the Celo L2 devchain
(`@celo/devchain-anvil`): `allocs.json` holds every account and `meta.json` the block
number and timestamp it was taken at. Turn it into a genesis file and start anvil from
that. `anvil --load-state` on the original `l2-devchain.json` is not an option; anvil
1.8.1 rejects the 716 MB snapshot.

```sh
node --input-type=module -e '
import { readFileSync, writeFileSync } from "node:fs";
const alloc = JSON.parse(readFileSync("test/devchain/allocs.json", "utf8"));
const meta = JSON.parse(readFileSync("test/devchain/meta.json", "utf8"));
for (const account of Object.values(alloc)) {
  account.nonce = "0x" + BigInt(account.nonce).toString(16);
}
writeFileSync(
  "/tmp/devchain-genesis.json",
  JSON.stringify({
    config: { chainId: 31337 },
    timestamp: "0x" + meta.timestamp.toString(16),
    gasLimit: "0x1c9c380",
    difficulty: "0x0",
    alloc,
  })
);
'

anvil --celo --disable-code-size-limit --init /tmp/devchain-genesis.json
```

`--celo` enables the Celo transaction types and `--disable-code-size-limit` lets the
oversized implementations be created on the node, the same reason the script needs the
flag. Write the genesis file outside the repository; it is 11 MB.

Deploying against it is the normal command with `NETWORK=local` and one of the anvil
development keys:

```sh
NETWORK=local \
TIME_LOCK_MIN_DELAY=86400 TIME_LOCK_DELAY=259200 MULTISIG_REQUIRED_CONFIRMATIONS=3 \
MULTISIG_OWNERS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,0x70997970C51812dc3A010C7d01b50e0d17dc79C8,0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,0x90F79bf6EB2c4f870365E785982E1f101E93b906,0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 \
forge script script/deploy/DeployCore.s.sol \
  --disable-code-size-limit \
  --rpc-url http://localhost:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

A full run is 29 transactions: nine implementations, the `AddressSortedLinkedList`
library, nine proxies, four `setDependencies` calls and six `transferOwnership` calls.
`deployments/local/` and `broadcast/` are git-ignored.

### Deploying and mining, the `deploy:devchain` recipe

`yarn deploy:devchain` was `hardhat deploy --network devchain && ts-node scripts/mineBlocks.ts`:
deploy, then mine 35 blocks so that the epoch based logic of the core contracts has some
history behind it. The Forge equivalent is the command above followed by
`scripts/mine-blocks.sh`, which sends one `anvil_mine` for the whole batch:

```sh
NETWORK=local \
TIME_LOCK_MIN_DELAY=86400 TIME_LOCK_DELAY=259200 MULTISIG_REQUIRED_CONFIRMATIONS=3 \
MULTISIG_OWNERS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,0x70997970C51812dc3A010C7d01b50e0d17dc79C8,0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,0x90F79bf6EB2c4f870365E785982E1f101E93b906,0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 \
VALIDATOR_GROUPS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8,0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,0x90F79bf6EB2c4f870365E785982E1f101E93b906 \
forge script script/deploy/DeployCore.s.sol \
  --disable-code-size-limit \
  --gas-estimate-multiplier 200 \
  --rpc-url http://localhost:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

scripts/mine-blocks.sh 35 http://localhost:8545
```

Those three `VALIDATOR_GROUPS` are the validator groups the devchain genesis registers,
and their members are the elected set, so all three come out healthy and end up active in
the `DefaultStrategy`. (They double as MultiSig owners above only because both lists are
made of the anvil development accounts.)

`scripts/mine-blocks.sh [blocks] [rpc-url]` defaults to 35 blocks on
`http://localhost:8545` and documents the equivalent call for hardhat node, ganache and
`geth --dev`. A real network needs none of it: its validators produce the blocks.

## Tests

`test/script/DeployCoreScriptTest.t.sol` runs the same sequence in-process against the
Celo devchain fixture through `DeployCore.runInProcess`, which pranks the deployer instead
of broadcasting and writes no records. It checks the proxies, the wiring, the ownership
transfers and that each implementation is byte-for-byte the compiled artifact, apart from
the immutable slots the artifact leaves zeroed (`UUPSUpgradeable.__self` everywhere, plus
`MultiSig.minDelay`).

A second suite in the same file runs the sequence with `VALIDATOR_GROUPS` set: it registers
four validator groups on the devchain, puts the members of three of them in the elected set
and checks that those three end up healthy and active in the listed order, that the fourth
is skipped as unhealthy, and that a second run leaves all of it untouched.

A third suite covers `_configFromEnv` on its own, without a devchain: it sets
`MULTISIG_SIGNER_0` .. `MULTISIG_SIGNER_2` and checks they become the owner set, that a hole
in the numbering ends it, that `MULTISIG_OWNERS` wins once it is set, and that neither
spelling being set stops the run with a message naming both.
