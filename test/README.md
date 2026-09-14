# Foundry test-suite

The tests are a 1:1 port of the former Hardhat/TypeScript suite (`test-ts/`, kept under
`legacy/` after the migration). Every `it()` of the original suite maps to one
`function test_...()`; the original `describe` path is encoded in the function name, e.g.
`describe("#deposit()") > describe("when there are active groups") > it("distributes votes")`
becomes `test_deposit_WhenThereAreActiveGroups_DistributesVotes`.

## Layout

| Path | Purpose |
| --- | --- |
| `test/*.t.sol` | Unit tests of one contract each |
| `test/manager/`, `test/account/` | Large suites split by top-level `describe` block, sharing an abstract `*TestBase.sol` |
| `test/e2e/` | End-to-end tests that deploy the production stack and drive it against the Celo core contracts |
| `test/devchain/` | Devchain fixture (`allocs.json`, `meta.json`, generated) and its smoke test |
| `test/helpers/` | Shared abstract base contracts (see below) |
| `test/helpers/deploy/` | Deployment fixtures mirroring `legacy/deploy/test/*.ts` and the production deploy scripts |

## Toolchain constraints

- The contracts are pinned to `pragma solidity 0.8.11`. `forge-std` requires 0.8.13+, so it
  is not used: cheatcodes are declared in local interfaces (`CeloTestVm` in
  `CeloTestHelper.sol`, `DevchainVm` in `DevchainHelper.sol`). Cast the cheatcode address to
  a local interface if you need a cheatcode that is not declared yet.
- The default profile compiles the production contracts with the exact Hardhat settings
  (no optimizer, evm istanbul). `test/**` and `script/**` are compiled with `via_ir` and the
  optimizer through `compilation_restrictions`, which keeps "stack too deep" away from the
  test code without touching the contract bytecode.
- `contracts/common/MultiSig.sol` and `contracts/mock/MockRegistry.sol` import the
  non-upgradeable OpenZeppelin `Initializable`, everything else the upgradeable one. Both
  cannot be imported into one compilation unit, so helpers deploy those two through
  `vm.getCode` and talk to them through `IMultiSig` / `IRegistry`.

## Helper hierarchy

```
CeloTestHelper            constants, named accounts, epoch/time utils, strategy helpers (utils.ts)
└── MultiSigHelper        submitAndExecuteMultiSigProposal (utils-multisig.ts)
    ├── ValidatorHelper   validator registration against the *mock* Celo contracts
    └── DevchainHelper    validator registration, voting, rewards against the *real* Celo contracts
TestAccountDeployHelper   fixtures of legacy/deploy/test/*.ts (TestPausable, TestAccount, TestVote, ...)
FullTestManagerDeployHelper  the FullTestManager fixture (Manager + strategies + Account + StakedCelo + Vote)
CoreDeployHelper          the production deployment sequence (MultiSig, all proxies, setDependencies, ownership)
```

Every deploy fixture exists in two flavours: the no-argument version deploys a `MockRegistry`
with mock Celo contracts, the `(address registry, ...)` version deploys against a given
registry, normally the devchain registry at `0x000000000000000000000000000000000000ce10`.

## The devchain fixture

The Hardhat tests forked a ganache based Celo devchain and used ContractKit against the
real `Election`, `LockedGold`, `Validators`, `Accounts` and `Governance` contracts. The
Foundry suite loads the state of the [`@celo/devchain-anvil`](https://www.npmjs.com/package/@celo/devchain-anvil)
package (a Celo L2 devchain) into the test EVM with `vm.loadAllocs`:

```
scripts/prepare-devchain.sh      # writes test/devchain/allocs.json + meta.json (git-ignored)
forge test
```

`DevchainHelper.loadDevchain()` loads the allocs, sets block number and timestamp, resolves
the core contracts from the Registry and pins the epoch number. Notable differences to the
ganache devchain the TypeScript suite was written for:

| Topic | ganache devchain (Hardhat) | anvil devchain (Foundry) |
| --- | --- | --- |
| Epochs | 100 blocks, read from a precompile | tracked by `EpochManager`; `mineToNextEpoch()` bumps a mocked epoch number and mines 100 blocks |
| Epoch rewards | `Election.distributeEpochRewards` from `address(0)` | pranked as `EpochManager` by `distributeEpochRewards(group, amount)` |
| Validator registration | `registerValidator(ecdsa, bls, pop)` | `registerValidatorNoBls(ecdsa)`; validators must be created with `createWallet()` so the public key is known |
| Locked gold requirement | 10 000 CELO hardcoded | read from `Validators` at load time (also 10 000 CELO) |
| `LockedGold.unlockingPeriod` | 3 days | 6 hours; use `celoLockedGold.unlockingPeriod()` rather than `LOCKED_GOLD_UNLOCKING_PERIOD` when the exact value matters |
| `prepareOverflow` vote amounts | hardcoded (95 824 / 143 697 / 95 664 CELO) | solved from the chain state so that 40 / 100 / 200 CELO stay receivable |
| Registry / core contract owner | ganache account 0 | governance owner address; use `celoRegistry.owner()` etc. |
| GroupHealth in E2E | upgraded to `MockGroupHealth` (no precompiles on ganache) | same, via `upgradeToMockGroupHealthE2E()` |

`test/devchain/DevchainSmoke.t.sol` exercises each of these flows and is the reference for
how to use the helper.

## Conventions for ported tests

- Keep the assertions of the original test; do not add or drop cases. When a TypeScript
  assertion depended on ganache specific numbers, derive the expected value from the chain
  state the same way the original computed it.
- `setUp()` runs before every test, which matches the `before()` + `beforeEach()` pair with
  `evm_snapshot` / `evm_revert` used by the original suite.
- Use `vm.expectRevert(Contract.Error.selector)` / `abi.encodeWithSelector(...)` for custom
  errors and `vm.expectRevert(bytes("..."))` for string reverts.
- Prank ordering: `vm.prank` applies to the *next* external call, including view calls. Resolve
  arguments (lesser/greater, owners, balances) before pranking.
- Do not modify anything under `contracts/`. The production bytecode must stay byte-identical
  to the Hardhat build (`scripts/bytecode-compat-check.py`).
