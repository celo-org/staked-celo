# Legacy Hardhat toolchain

Everything in this directory is the Hardhat/TypeScript toolchain the project used before
the Foundry migration. It is **frozen**: it is not built, not linted, not run in CI, and
its dependencies are no longer in `package.json`, so it will not install or execute as-is.
It is kept because it is the source the Foundry code was ported from, and the most precise
answer to "what did the old command actually do?" is still the old code.

Do not add to it and do not fix it. Change the Foundry equivalent instead.

## What is here, and what replaced it

| Legacy | Replaced by |
| --- | --- |
| `test-ts/` - the Mocha/Chai/ethers test-suite | `test/` - the Foundry suite, a 1:1 port (see [test/README.md](../test/README.md)) |
| `deploy/00_*.ts` .. `deploy/13_*.ts` - hardhat-deploy scripts | `script/deploy/DeployCore.s.sol` and `UpgradeImplementation.s.sol` (see [script/deploy/README.md](../script/deploy/README.md)) |
| `deploy/test/*.ts` - test deployment fixtures | `test/helpers/deploy/*.sol` |
| `lib/account-tasks/`, `lib/manager-tasks/`, `lib/multiSig-tasks/` - the `yarn hardhat stakedCelo:*` tasks | `script/tasks/**` (see [script/tasks/README.md](../script/tasks/README.md)), which lists every task and its forge counterpart |
| `lib/helpers/`, `lib/task-utils.ts`, `lib/deployTask.ts`, `lib/logger.ts` and the other loose `lib/*.ts` | `script/tasks/lib/*.sol` |
| `hardhat.config.ts` - networks, solc settings, plugins | `foundry.toml` (the solc settings are reproduced there exactly, see below) |
| `.mocharc.json`, `tsconfig.json`, `.eslintrc.json` - the TypeScript toolchain config | nothing; the repository has no TypeScript any more |
| `scripts/run-tests.ci.sh` - start ganache, compile, test | `.github/workflows/solidity.yml` plus `scripts/prepare-devchain.sh` |
| `scripts/standardize-artifacts.ts`, `scripts/standardize-artifacts-interface.ts` - input for `@celo/contract-compatibility-check` | `scripts/abi-compat-check.py`, run by the `compatibility` CI job |
| `scripts/mineBlocks.ts` - mine blocks after a devchain deploy | nothing; the Foundry tests control block progression with cheatcodes |
| `scripts/tarchain.ts`, `chainData/`, `devChain/stCeloV1.tar.gz` - the ganache devchain tarballs | `scripts/prepare-devchain.sh`, which extracts the `@celo/devchain-anvil` state into `test/devchain/` |
| `scripts/test/devchain.test.ts` - smoke test of the devchain tarball | `test/devchain/DevchainSmoke.t.sol` |

## Why the old compiler settings still matter

The deployed contracts were compiled by this toolchain. `foundry.toml` therefore pins the
exact settings `hardhat.config.ts` used (solc 0.8.11, evm `istanbul`, optimizer off,
literal metadata content, ipfs metadata hash), and `scripts/bytecode-compat-check.py`
fails if the build ever drifts from the pinned digests. `hardhat.config.ts` is the primary
evidence for what those settings were.

## Running it anyway

Not supported. If you really need to, restore the `devDependencies` and `scripts` of
`package.json` from a commit before the migration, move this directory's contents back to
the repository root (the relative paths in the TypeScript sources assume the root), and
use node 14 - the pinned dependency tree does not install on newer runtimes.
