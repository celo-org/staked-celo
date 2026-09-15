# StakedCelo

StakedCelo is a liquid staking derivative of CELO, the native token on the Celo
blockchain.

Users can deposit CELO to the Staked Celo smart contract and receive stCELO tokens in
return, allowing them to earn staking rewards.

The repository is Foundry-first: contracts, tests, deployment and the operational tasks
all run through `forge`. The Hardhat/TypeScript toolchain the project started with is
frozen under [`legacy/`](legacy/README.md).

## Contracts

### StakedCelo.sol

An ERC-20 token (ticker: stCELO) representing a share of the staked pool of CELO. Over
time, a unit of stCELO becomes withdrawable for more and more CELO, as staking yield
accrues to the pool.

### Manager.sol

The main control center of the system. Defines exchange rate between CELO and stCELO, has
ability to mint and burn stCELO, is the main point of interaction for depositing and
withdrawing CELO from the pool, and defines the system's voting strategy.

#### Voting strategy

An account can vote for up to 10 different validator groups (based on the
`maxNumGroupsVotedFor` parameter of the Elections core contract). Thus the manager is
limited to actively voting for up to 10 validator groups. Given the list of validator
groups to vote for, Manager uses incoming deposits or withdrawals to approach as even a
distribution between the groups as possible.

### Account.sol

This contract sets up an account in the core Accounts contract, enabling it to lock CELO
and vote in validator elections. The system's pool of CELO is held by this contract. This
contract needs to be interacted with to lock/vote/activate votes, as assigned to validator
groups according to Manager's strategy, and to finalize withdrawals of CELO, after the
unlocking period of LockedGold has elapsed.

### RebasedStakedCelo.sol

This is a wrapper token (ticker: rstCELO) around stCELO that, instead of accruing value to
each token as staking yield accrues in the pool, rebases balances, such that an account's
balance always represents the amount of CELO that could be withdrawn for the underlying
stCELO. Thus, the value of one unit of rstCELO and one unit of CELO should be
approximately equivalent.

## Deposit/withdrawal flows

These are the full flows of how CELO is deposited and withdrawn from the system, including
specific contract functions that need to be called.

Deposit flow:

1. Call `Manager.deposit`, setting `msg.value` to the amount of CELO one wants to deposit.
   stCELO is minted to the user, and Manager schedules votes according to the voting
   strategy.
2. At some point, `Account.activateAndVote` should be called for each validator group that
   has had votes scheduled recently. Note that this does not need to be called for every
   `deposit` call, but ideally should be called before the epoch during which the deposit
   was made ends. This is because voting CELO doesn't start generating yield until the next
   epoch after it was used for voting. The function can be called by any address, whether
   or not it had previously deposited into the system (in particular, there could be a bot
   that calls it once a day per validator group).

Withdrawal flow:

1. Call `Manager.withdraw`. stCELO is burned from the user, and Manager schedules
   withdrawals according to the voting strategy. The following steps are necessary to
   unlock Account's CELO from the LockedGold contract and actually distribute them to the
   user.
2. Call `Account.withdraw` for each group that was scheduled to be withdrawn from in the
   previous step. Some CELO might be available for immediate withdrawal, if it hadn't been
   yet locked and used for voting, and will be transferred to the user. For the rest of the
   withdrawal amount, it will be unvoted from the specified group and the LockedGold
   unlocking process will begin.
3. After the 3 day unlocking period has passed, `Account.finishPendingWithdrawal` should be
   called, specifying the pending withdrawal that was created in the previous step. This
   will finalize the LockedGold withdrawal and return the remaining CELO to the user.

## Prerequisites

- **Foundry 1.8.1.** `mise.toml` pins it, so `mise install` followed by
  `eval "$(mise env -s zsh)"` is enough. Without mise: `foundryup -i 1.8.1`. The version is
  pinned because the compiler settings and the cheatcodes the suite uses must match CI.
- **node and yarn**, for two things only: the Solidity linters (`yarn lint:sol`) and the
  `@celo/devchain-anvil` package that `scripts/prepare-devchain.sh` extracts the test
  fixture from. Nothing in the build, the tests or the deployment runs on node. The
  package's version is pinned once, in `package.json`'s `devDependencies`; CI's fixture
  cache key follows the same file.
- **python3**, for `scripts/bytecode-compat-check.py` and `scripts/abi-compat-check.py`.

```sh
mise install && eval "$(mise env -s zsh)"
yarn install
```

## Build and test

```sh
scripts/prepare-devchain.sh   # once: writes the git-ignored test/devchain fixture
forge build
forge test
```

Run a subset while working on one area:

```sh
forge test --match-path 'test/manager/*'
forge test --match-path test/e2e/EndToEndTest.t.sol
forge test --match-test test_deposit_WhenThereAreActiveGroups -vvv
```

`yarn build` and `yarn test` are thin aliases for `forge build` and `forge test`.

See [test/README.md](test/README.md) for the layout of the suite, the helper hierarchy, the
devchain fixture, and the conventions the ported tests follow.

## Bytecode guarantee

The deployed contracts must keep compiling to exactly the bytecode that was audited and
deployed, which is the bytecode the Hardhat toolchain produced. `foundry.toml` therefore
has a single production compiler profile with those settings (solc 0.8.11, evm `istanbul`,
optimizer off, literal metadata content), and `scripts/bytecode-reference.json` pins a
digest of the creation and runtime bytecode of every contract under `contracts/`:

```sh
forge build
python3 scripts/bytecode-compat-check.py --reference scripts/bytecode-reference.json
```

CI runs this on every push. It fails on any contract edit and on any change to the compiler
settings, because the settings are hashed into the metadata trailer of the bytecode. When a
contract change is intended, regenerate the reference in the same commit and review its
diff as carefully as the contract diff:

```sh
python3 scripts/bytecode-compat-check.py --update-reference scripts/bytecode-reference.json
```

`yarn bytecode:check` is an alias for the checking form.

## Upgrade compatibility

The upgradeable contracts must stay storage- and ABI-compatible with the release they are
upgrading, currently `releases/4`. CI builds that release with the current toolchain and
compares the two `out/` directories:

```sh
python3 scripts/abi-compat-check.py --baseline baseline/out --current out
```

This replaces the Hardhat-based `@celo/contract-compatibility-check` and keeps its contract
exclusion list. See the `compatibility` job in
[.github/workflows/solidity.yml](.github/workflows/solidity.yml) for how the baseline is
checked out and overlaid.

## Deployment

`script/deploy/DeployCore.s.sol` deploys the whole protocol and
`script/deploy/UpgradeImplementation.s.sol` pushes a new implementation for one proxy.
Both read their parameters from the environment; `.env.example` lists the variables and
`yarn keys:decrypt` fetches the encrypted environment files from GCP.

```sh
forge script script/deploy/DeployCore.s.sol \
  --disable-code-size-limit \
  --rpc-url celo --broadcast --ledger
```

Read [script/deploy/README.md](script/deploy/README.md) before deploying: it documents the
required environment variables, why `--disable-code-size-limit` is needed, the deployment
records written under `deployments/<network>/`, and how a failed run must be cleaned up.

### Addresses and ABIs for integrators

- Addresses: `deployments/<network>/<Name>.json` (`address` is the proxy,
  `<Name>_Implementation.json` the current implementation).
- ABIs: `forge build` writes them to `out/<Name>.sol/<Name>.json` (`abi` field), or print one
  with `forge inspect <Name> abi`. The Hardhat `artifacts/` directory no longer exists.

`yarn verify <network>` (`scripts/verify-contracts.sh`) publishes the sources of everything
under `deployments/<network>/` to Sourcify and, with `CELOSCAN_API_KEY` set, to Celoscan.
It replaces `yarn verify:deploy`; because the production build is byte-identical to the
Hardhat one, contracts deployed before the port still verify from these sources.

## Operational tasks

Every `yarn hardhat stakedCelo:*` task has a forge script counterpart under
`script/tasks/`. Parameters became environment variables and the signer flags became
forge's (`--ledger`, `--unlocked --sender`, `--private-key`):

```sh
PROPOSAL_ID=7 forge script script/tasks/multisig/ConfirmProposal.s.sol \
  --rpc-url alfajores --broadcast --ledger
```

[script/tasks/README.md](script/tasks/README.md) has the full mapping table - MultiSig,
Manager and Account tasks, one row per old task - plus the environment variables and
worked examples for submitting, confirming, scheduling and executing a MultiSig proposal.

## Linting

Solidity only, and the tree decides the tool. `contracts/` is formatted by prettier and
linted by solhint; `test/` and `script/` are formatted by `forge fmt`. The two formatters
disagree, so neither is ever pointed at the other's tree: `contracts/` is listed in the
`ignore` list under `[fmt]` in [foundry.toml](foundry.toml), and `test/` and `script/` are
outside prettier's glob and listed in [.solhintignore](.solhintignore). The split exists
because the solhint rules (ordering, `func-name-mixedcase`, line length) are written for
production contracts, while the test-suite follows the forge-std conventions.

```sh
yarn lint:sol      # contracts/: format and fix
yarn lint:sol:ci   # contracts/: check only, what CI runs
yarn fmt           # test/ and script/: format
yarn fmt:check     # test/ and script/: check only, what CI runs
```

A husky pre-commit hook runs `lint-staged` on staged `*.sol` files. Set
`STAKED_CELO_DISABLE_PRECOMIT=1` to skip it.

## CI

[.github/workflows/solidity.yml](.github/workflows/solidity.yml) runs four independent
jobs on every push and pull request:

| Job | What it does |
| --- | --- |
| `lint` | `yarn lint:sol:ci` - prettier and solhint over `contracts/` - and `yarn fmt:check` - `forge fmt` over `test/` and `script/` |
| `test` | prepares the devchain fixture, `forge build`, `forge test -vvv` |
| `bytecode` | `scripts/bytecode-compat-check.py` against the pinned reference |
| `compatibility` | `scripts/abi-compat-check.py` against `releases/4` |

## Legacy

[`legacy/`](legacy/README.md) holds the Hardhat toolchain the project used before the
Foundry migration: the Mocha test-suite (`legacy/test-ts/`), the hardhat-deploy scripts
(`legacy/deploy/`), the Hardhat tasks (`legacy/lib/`), the ganache devchain tarballs and
the TypeScript build configuration. It is frozen, not built and not run by CI; it is kept
because it is what the current Foundry code was ported from. Its README maps each part to
its replacement.

## Audits

Audit reports are in [`audit/`](audit/).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for style and how to contribute. All communication
and contributions to this project are subject to the
[Celo Code of Conduct](code-of-conduct.md).
