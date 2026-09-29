# Foundry test-suite

Unit, integration and end-to-end tests for the StakedCelo contracts, run with `forge test`.

Test functions are named `test_<function>_<Context>..._<Behaviour>`: the function under
test, then the context path that narrows the scenario, then the expected behaviour, each
part in CamelCase and separated by underscores. For example
`test_blockGroup_When2ActiveGroups_WhenTheGroupIsAllowed_EmitsAStrategyBlockedEvent` tests
`blockGroup()` with two active groups and an allowed group, and expects it to emit the
blocking event.

## Layout

| Path | Purpose |
| --- | --- |
| `test/*.t.sol` | Unit tests of one contract each |
| `test/manager/`, `test/account/`, `test/default-strategy/`, `test/specific-group-strategy/`, `test/multisig/` | Large suites split by the function or area under test, each directory sharing an abstract `*TestBase.sol` |
| `test/e2e/` | End-to-end tests that deploy the production stack and drive it against the Celo core contracts |
| `test/script/` | Tests of the deploy and task scripts under `script/`, running the same library code the scripts run |
| `test/devchain/` | Devchain fixture (`allocs.json`, `meta.json`, generated) and its smoke test |
| `test/helpers/` | Shared abstract base contracts (see below) |
| `test/helpers/deploy/` | Deployment fixtures: test contract setups and the production deployment sequence |

## Toolchain constraints

- The contracts are pinned to `pragma solidity 0.8.11`. `forge-std` requires 0.8.13+, so it
  is not used: cheatcodes are declared in local interfaces (`CeloTestVm` in
  `CeloTestHelper.sol`, `DevchainVm` in `DevchainHelper.sol`). Cast the cheatcode address to
  a local interface if you need a cheatcode that is not declared yet.
- There is a single compiler profile with the production settings (solc 0.8.11, evm
  istanbul, no optimizer, no via_ir), so the tests exercise the production bytecode. Keep
  test functions small and put fixture state in storage variables to stay clear of
  "stack too deep"; do not enable via_ir or the optimizer for tests.
- `contracts/common/MultiSig.sol` and `contracts/mock/MockRegistry.sol` import the
  non-upgradeable OpenZeppelin `Initializable`, everything else the upgradeable one. Both
  cannot be imported into one compilation unit, so helpers deploy those two through
  `vm.getCode` and talk to them through `IMultiSig` / `IRegistry`.

## Helper hierarchy

```
CeloTestHelper            constants, named accounts, epoch/time utils, strategy helpers
└── MultiSigHelper        submitAndExecuteMultiSigProposal
    └── DevchainHelper    validator registration, voting, rewards against the *real* Celo contracts
TestAccountDeployHelper   fixtures of the test contracts (TestPausable, TestAccount, TestVote, ...)
FullTestManagerDeployHelper  the FullTestManager fixture (Manager + strategies + Account + StakedCelo + Vote)
CoreDeployHelper          the production deployment sequence (MultiSig, all proxies, setDependencies, ownership)
```

Every deploy fixture exists in two flavours: the no-argument version deploys a `MockRegistry`
with mock Celo contracts, the `(address registry, ...)` version deploys against a given
registry, normally the devchain registry at `0x000000000000000000000000000000000000ce10`.

## The devchain fixture

Tests that need the real Celo core contracts (`Election`, `LockedGold`, `Validators`,
`Accounts`, `Governance`, ...) load the state of the
[`@celo/devchain-anvil`](https://www.npmjs.com/package/@celo/devchain-anvil) package (a
Celo L2 devchain) into the test EVM with `vm.loadAllocs`:

```
scripts/prepare-devchain.sh      # writes test/devchain/allocs.json + meta.json (git-ignored)
forge test
```

The package version is pinned once, in `package.json`'s `devDependencies`; the script reads
it as its default (override with `DEVCHAIN_ANVIL_VERSION` for a one-off run) and CI's fixture
cache key follows the same file, so bumping the pin is a one-line `package.json` change.

`DevchainHelper.loadDevchain()` loads the allocs, sets block number and timestamp, resolves
the core contracts from the Registry and pins the epoch number. Facts about the devchain the
tests rely on:

- **Epochs** are tracked by `EpochManager`. `mineToNextEpoch()` bumps a mocked epoch
  number and mines 100 blocks.
- **Epoch rewards** are paid by `distributeEpochRewards(group, amount)`, which calls
  `Election.distributeEpochRewards` pranked as `EpochManager`.
- **Validators** are registered with `registerValidatorNoBls(ecdsa)`, and must be created
  with `createWallet()` so that their public key is known. The locked gold requirement
  (10 000 CELO) is read from `Validators` at load time.
- **The unlocking period** is 6 hours. Read it with `celoLockedGold.unlockingPeriod()`
  rather than `LOCKED_GOLD_UNLOCKING_PERIOD` when the exact value matters.
- **Overflow scenarios**: the vote amounts `prepareOverflow` casts are solved from the
  chain state, so that 40 / 100 / 200 CELO stay receivable.
- **Core contract owners** are the governance owner address; read them from the contracts
  (`celoRegistry.owner()` etc.) instead of assuming an account.
- **GroupHealth** is upgraded to `MockGroupHealth` in the E2E tests, via
  `upgradeToMockGroupHealthE2E()`. The mock serves the validator set GroupHealth
  normally reads from Celo precompiles, which the test EVM does not have, and lets tests set
  group validity directly.

`test/devchain/DevchainSmoke.t.sol` exercises each of these flows and is the reference for
how to use the helper.

## Conventions

- Derive expected values that depend on the devchain from its state (group votes, locked
  gold requirement, unlocking period) instead of hardcoding numbers.
- `setUp()` runs before every test on fresh state, so tests never depend on each other.
- Use `vm.expectRevert(Contract.Error.selector)` / `abi.encodeWithSelector(...)` for custom
  errors and `vm.expectRevert(bytes("..."))` for string reverts.
- Prank ordering: `vm.prank` applies to the *next* external call, including view calls. Resolve
  arguments (lesser/greater, owners, balances) before pranking.
- Do not modify anything under `contracts/`. The production bytecode must stay byte-identical
  to the deployed bytecode (`scripts/bytecode-compat-check.ts`).
- Formatting here is `forge fmt`, not prettier: run `yarn fmt` before committing, and CI runs
  `yarn fmt:check`. The settings live under `[fmt]` in `foundry.toml`. `contracts/` goes the
  other way round, prettier and solhint, and is on the `ignore` list under `[fmt]` so that
  neither formatter reaches the other's tree.
