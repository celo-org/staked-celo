import { electionABI, epochManagerABI, scoreManagerABI } from "@celo/abis";
import { Anvil, createAnvil, CreateAnvilOptions } from "@viem/anvil";
import { BigNumber } from "bignumber.js";
import hre from "hardhat";
import { JsonRpcResponse } from "hardhat/types";
import Web3 from "web3";
import { ValidatorGroupVote } from "./utils-interfaces";

export const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

export const TEST_MNEMONIC = "test test test test test test test test test test test junk";
export const TEST_BALANCE = 1000000;
export const TEST_GAS_PRICE = 0;
export const TEST_GAS_LIMIT = 50000000;
export const CODE_SIZE_LIMIT = 50000000;

const ANVIL_PORT = 8546;
let instance: null | Anvil = null;

// eslint-disable-next-line no-unused-vars
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function jsonRpcCall<O>(web3: Web3, method: string, params: any[]): Promise<O> {
  return new Promise<O>((resolve, reject) => {
    if (web3.currentProvider && typeof web3.currentProvider !== "string") {
      hre.network.provider.sendAsync(
        {
          id: new Date().getTime(),
          jsonrpc: "2.0",
          method,
          params,
        },
        (err: Error | null, res?: JsonRpcResponse) => {
          if (err) {
            reject(err);
          } else if (!res) {
            reject(new Error("no response"));
          } else if (res.error) {
            reject(
              new Error(
                `Failed JsonRpcResponse: method: ${method} params: ${JSON.stringify(
                  params
                )} error: ${JSON.stringify(res.error)}`
              )
            );
          } else {
            // eslint-disable-next-line  @typescript-eslint/no-unsafe-argument
            resolve(res.result);
          }
        }
      );
    } else {
      reject(new Error("Invalid provider"));
    }
  });
}

export function evmRevert(web3: Web3, snapId: string): Promise<void> {
  return jsonRpcCall(web3, "evm_revert", [snapId]);
}

export function evmSnapshot(web3: Web3) {
  return jsonRpcCall<string>(web3, "evm_snapshot", []);
}

type TestWithWeb3Hooks = {
  before?: () => Promise<void>;
  after?: () => Promise<void>;
};

/**
 * Creates a test suite with a given name and provides a function with a web3 instance connected to the given rpcUrl.
 *
 * It is an equivalent of Mocha's `describe` with the web3 addition. It also provides hooks for `before` and `after`.
 *
 * Optionally, if a runIf flag is set to false, the test suite will be skipped (useful for conditional test suites).
 * By default, all test suites are run normally, but if the runIf flag is set to false, the test suite will be skipped
 * using Mocha's `describe.skip`. It will be reported in the summary as "skipped".
 */
export function testWithWeb3(
  name: string,
  rpcUrl: string,
  fn: (web3: Web3) => void, // eslint-disable-line no-unused-vars
  options: {
    hooks?: TestWithWeb3Hooks;
    runIf?: boolean;
  } = {}
) {
  const web3 = new Web3(rpcUrl);

  // @ts-ignore with anvil setup, the tx receipt is apparently not immediately
  // available after the tx is sent, so by default it was waiting for 1000 ms
  // before polling again, making the tests slow
  web3.eth.transactionPollingInterval = 10;

  // By default, we run all the tests
  let describeFn: Mocha.SuiteFunction = describe;

  // Only skip if explicitly stated
  if (options.runIf === false) {
    describeFn = describe.skip as Mocha.SuiteFunction;
  }

  describeFn(name, function () {
    let snapId: string | null = null;

    if (options.hooks?.before) {
      before(options.hooks.before);
    }

    beforeEach(async function () {
      if (snapId != null) {
        await evmRevert(web3, snapId);
      }
      snapId = await evmSnapshot(web3);
    });

    after(async function () {
      if (snapId != null) {
        await evmRevert(web3, snapId);
      }
      if (options.hooks?.after) {
        // hook must be awaited here or Mocha will not wait, potentially leaving open handles
        await options.hooks.after();
      }
    });

    fn(web3);
  });
}

function createInstance(stateFilePath: string): Anvil {
  const port = ANVIL_PORT; //+ (process.pid - process.ppid)
  const options: CreateAnvilOptions = {
    port,
    loadState: stateFilePath,
    mnemonic: TEST_MNEMONIC,
    balance: TEST_BALANCE,
    gasPrice: TEST_GAS_PRICE,
    gasLimit: TEST_GAS_LIMIT,
    codeSizeLimit: CODE_SIZE_LIMIT,
    blockBaseFeePerGas: 0,
    stopTimeout: 1000,
    silent: false,
  };
  console.log("stateFilePath", stateFilePath);
  console.log("options", options);

  instance = createAnvil(options);

  return instance;
}

// eslint-disable-next-line no-unused-vars
function testWithAnvil(stateFilePath: string, name: string, fn: (web3: Web3) => void) {
  const anvil = createInstance(stateFilePath);

  // for each test suite, we start and stop a new anvil instance
  return testWithWeb3(name, `http://127.0.0.1:${anvil.port}`, fn, {
    runIf: process.env.RUN_ANVIL_TESTS === "true",
    hooks: {
      before: async () => {
        console.log("starting anvil");
        await anvil.start();
        console.log("anvil started");
      },
      after: async () => {
        console.log("stopping anvil");
        await anvil.stop();
      },
    },
  });
}

// eslint-disable-next-line no-unused-vars
export function testWithAnvilL2(name: string, fn: (web3: Web3) => void) {
  return testWithAnvil(require.resolve("@celo/devchain-anvil/l2-devchain.json"), name, fn);
}

const getEpochProcessingStatus = async () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const epochManagerAddress = await hre.kit.registry.addressFor("EpochManager" as any);
  const epochMangerContract = new hre.kit.web3.eth.Contract(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    epochManagerABI as any,
    epochManagerAddress
  );
  const state = await epochMangerContract.methods.getEpochProcessingState().call();
  return { totalRewardsVoter: state[2] };
};

export const getLessersAndGreaters = async (groups: string[]) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const scoreMangerAddress = await hre.kit.registry.addressFor("ScoreManager" as any);
  const scoreManager = new hre.kit.web3.eth.Contract(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    scoreManagerABI as any,
    scoreMangerAddress
  );
  const election = await hre.kit.contracts.getElection();
  const electionContract = new hre.kit.web3.eth.Contract(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    electionABI as any,
    election.address
  );

  const processingStatusPromise = getEpochProcessingStatus();
  const groupWithVotesPromise = election.getEligibleValidatorGroupsVotes();

  const lessers: string[] = new Array(groups.length);
  const greaters: string[] = new Array(groups.length);
  const rewards = await Promise.all(
    groups.map(async (group) => {
      const groupScore = await scoreManager.methods.getGroupScore(group).call();
      const status = await processingStatusPromise;
      const reward = await electionContract.methods
        .getGroupEpochRewardsBasedOnScore(group, status.totalRewardsVoter, groupScore)
        .call();
      return new BigNumber(reward);
    })
  );

  const groupWithVotes: ValidatorGroupVote[] = await groupWithVotesPromise;
  const groupWithVotesMap = new Map<string, ValidatorGroupVote>(
    groupWithVotes.map((group) => [group.address, group])
  );

  const missingGroups = groups.filter((group) => !groupWithVotesMap.has(group));

  const missingGroupsLoaded = await Promise.all(
    missingGroups.map(async (group) => {
      const votes = await election.getTotalVotesForGroup(group);
      return { group, votes };
    })
  );

  for (const group of missingGroupsLoaded) {
    groupWithVotes.push({ address: group.group, votes: group.votes } as ValidatorGroupVote);
  }

  for (let i = 0; i < groups.length; i++) {
    const reward = rewards[i];

    for (let j = 0; j < groupWithVotes.length; j++) {
      if (groupWithVotes[j].address === groups[i]) {
        groupWithVotes[j].votes = groupWithVotes[j].votes.plus(reward);
        break;
      }
    }

    groupWithVotes.sort((a, b) => (b.votes.gt(a.votes) ? 1 : b.votes.lt(a.votes) ? -1 : 0));

    for (let j = 0; j < groupWithVotes.length; j++) {
      if (groupWithVotes[j].address === groups[i]) {
        greaters[i] = j === 0 ? ADDRESS_ZERO : groupWithVotes[j - 1].address;
        lessers[i] = j === groupWithVotes.length - 1 ? ADDRESS_ZERO : groupWithVotes[j + 1].address;
        break;
      }
    }
  }

  return [lessers, greaters];
};
