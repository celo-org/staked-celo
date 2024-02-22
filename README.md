# StakedCelo

StakedCelo is a liquid staking derivative of CELO, the native token on the Celo
blockchain.

Users can deposit CELO to the Staked Celo smart contract and receive stCELO tokens in return, allowing them to earn staking rewards.

## Testing

To run tests first fire up a terminal and start the `devchain`, this will need to be run only once and you should keep it running.  

```bash

nvm use 18
yarn devchain
```

Then in another terminal run tests:

```bash
nvm use 14
yarn test # run all tests
yarn test <path to file> # run a specific file
```

Run prettier to lint and write - this is also done automatically in a pre-commit hook.

```bash
yarn lint
```

## Test debugging
For visualizing and debugging tests in VS code install following two extensions:

[Test Explorer UI](https://marketplace.visualstudio.com/items?itemName=hbenl.vscode-test-explorer)

[Mocha Test Explorer](https://marketplace.visualstudio.com/items?itemName=hbenl.vscode-mocha-test-adapter)


## Deploying to remote networks
Requirement: `gcloud` must be set up and user account must have access staked-celo-alfajores and staked-celo-staging on GCP. 
Next, ensure the environment variables have been decrypted, using `yarn keys:decrypt`.
Then use the following commands to deploy depending on the desired target environment.
For example, the below command will deploy to the Alfajores network, using the decrypted private key, the default Alfajores rpc url and the other variables in `.env.alfajores`. 

Alfajores : 
```
yarn deploy --network alfajores
```

You may immediately verify the deployment, with the following commands.

Alfajores : 
```
yarn verify:deploy --network alfajores
```

## Verify on CeloScan
1. Get CeloScan api key
1. Update api key in hardhat.config.ts (etherscan.apiKey)
1. Get constructor arguments of deployed smart contract
  * Find contract in `deployments/[network]` (example deployments/celo/MultiSig_Proxy.json)
  * In root level there are constructur arguments in `args`
4. Save constructor arguments into js file
```
module.exports = [
    "0xb78AB3f89C97C0291B747C3Ba8814b5AA47AEcF1",
    "4814d6b8a8394fe8b363a892b6618b21",
  ];
```
5. Verify smart contract
```
yarn hardhat verify --network [network] --constructor-args [path_to_js_file] [contract_address]
```
example
```
yarn hardhat verify --network celo --constructor-args arguments.js 0x78daa21fce4d30e74ff745da3204764a0ad40179
```

## Deploying to local CELO node
You may desire to deploy using an unlocked account in a private node. In that case, you can use the following commands :

```
yarn hardhat [GLOBAL OPTIONS] stakedCelo:deploy --from <STRING> --tags <STRING> --url <STRING> [--use-private-key]
```

example
```
yarn hardhat stakedCelo:deploy  --network alfajores --show-stack-traces --tags core  --url "http://localhost:8545" --from "0xff2694d968246F27093D095D8160E005D5f31e5f" --use-private-key
```
 
Run `yarn hardhat help stakedCelo:deploy` for more information.

### Steps to Run a light node:

Step 1: Create and fund an account.
In your terminal, run the below command

```
export ALFAJORES_CELO_IMAGE=us.gcr.io/celo-org/geth:alfajores
```

Then create a directory called `celo-data-dir` , cd into it and run the below command:

```
docker run -v $PWD:/root/.celo --rm -it $ALFAJORES_CELO_IMAGE account new
```

Choose a passphrase or hit enter twice to choose an empty phrase. Once done, it should output the address of the newly created account. Copy this address and export it to your shell as `$CELO_ACCOUNT_ADDRESS`.

i.e 

```
export CELO_ACCOUNT_ADDRESS=<YOUR-ACCOUNT-ADDRESS>
```

Step 2: Run the light node.

From within the `celo-data-dir` created above, run:

```
docker run --name celo-node -it -v $(pwd):/root/.celo -p 8545:8545 $ALFAJORES_CELO_IMAGE --syncmode lightest --rpc --rpcaddr 0.0.0.0 --rpcapi personal,eth,net --unlock $CELO_ACCOUNT_ADDRESS --allow-insecure-unlock --alfajores --datadir /root/.celo
```
Observe the command line output for the prompt to specify the passphrase chosen in step 1. Enter your passphrase and hit enter to continue, if everything goes well, you should observe the node running and mining blocks successfully.

Now if you point any network URL to `:8545`, it should route RPC calls to your port-forwarded light node, using the unlocked account you created in step 1 to sign transactions.

## Using local node to interact with multiSig contract

Once your local node is running with an unlocked account, in your terminal, run the `stakedCelo:multiSig:<function_name>` task.

If you are signing a transaction, make sure to pass the `--account` flag with the account name or address.

Examples:

```bash
$ yarn run hardhat stakedCelo:multiSig:submitProposal --help

$ yarn run hardhat --network local stakedCelo:multiSig:submitProposal --destinations '0xFC88f1406af22D522A74E922E8AaB170D723a665' --values '0' --payloads '0x7065cb480000000000000000000000006ecbe1db9ef729cbe972c83fb886247691fb6beb' --account '<YOUR_ACCOUNT_ADDRESS>'
```

### Signing transactions with Ledger wallet

Follow the [steps to install the Ethereum app & create an account](https://support.ledger.com/hc/en-us/articles/360009576554-Ethereum-ETH-?docs=true) on the ledger device. Make sure to enable **Blind signing**.

<span style="color:yellow">**Warning:**</span> It is important to install the ***Ethereum app***, as the CELO app is not fully supported.

Close the ledger live app once installation is complete.

Run a local node with the `--usb` flag.

Example:

```bash
docker run --name celo-node -it -v $(pwd):/root/.celo -p 8545:8545 $ALFAJORES_CELO_IMAGE --syncmode lightest --rpc --rpcaddr 0.0.0.0 --rpcapi personal,eth,net --unlock $CELO_ACCOUNT_ADDRESS --allow-insecure-unlock --alfajores --datadir /root/.celo --usb
```

Once the local node is running, in a separate terminal, you can run the `stakedCelo:multiSig:<function_name>` task with the `--use-ledger` flag.

Example:

```bash
yarn run hardhat --network local stakedCelo:multiSig:submitProposal --destinations '0xFC88f1406af22D522A74E922E8AaB170D723a665' --values '0' --payloads '0x7065cb480000000000000000000000006ecbe1db9ef729cbe972c83fb886247691fb6beb' --use-ledger
```

## Contracts

### StakedCelo.sol

An ERC-20 token (ticker: stCELO) representing a share of the staked pool of
CELO. Over time, a unit of stCELO becomes withdrawable for more and more CELO,
as staking yield accrues to the pool.

### Manager.sol

The main control center of the system. Defines exchange rate between CELO and
stCELO, has ability to mint and burn stCELO, is the main point of interaction
for depositing and withdrawing CELO from the pool, and defines the system's
voting strategy.

#### Voting strategy

An account can vote for up to 10 different validator groups (based on the
`maxNumGroupsVotedFor` parameter of the Elections core contract). Thus the
manager is limited to actively voting for up to 10 validator groups. Given the
list of validator groups to vote for, Manager uses incoming deposits or
withdrawals to approach as even a distribution between the groups as possible.

### Account.sol

This contract sets up an account in the core Accounts contract, enabling it to
lock CELO and vote in validator elections. The system's pool of CELO is held by
this contract. This contract needs to be interacted with to lock/vote/activate
votes, as assigned to validator groups according to Manager's strategy, and to
finalize withdrawals of CELO, after the unlocking period of LockedGold has
elapsed.

### RebasedStakedCelo.sol

This is a wrapper token (ticker: rstCELO) around stCELO that, instead of
accruing value to each token as staking yield accrues in the pool, rebases
balances, such that an account's balance always represents the amount of CELO
that could be withdrawn for the underlying stCELO. Thus, the value of one unit
of rstCELO and one unit of CELO should be approximately equivalent.

## Deposit/withdrawal flows

These are the full flows of how CELO is deposited and withdrawn from the system,
including specific contract functions that need to be called.

Deposit flow:

1. Call `Manager.deposit`, setting `msg.value` to the amount of CELO one wants
   to deposit. stCELO is minted to the user, and Manager schedules votes
   according to the voting strategy.
2. At some point, `Account.activateAndVote` should be called for each validator
   group that has had votes scheduled recently. Note that this does not need to
   be called for every `deposit` call, but ideally should be called before the
   epoch during which the deposit was made ends. This is because voting CELO
   doesn't start generating yield until the next epoch after it was used for
   voting. The function can be called by any address, whether or not it had
   previously deposited into the system (in particular, there could be a bot
   that calls it once a day per validator group).

Withdrawal flow:

1. Call `Manager.withdraw`. stCELO is burned from the user, and Manager
   schedules withdrawals according to the voting strategy. The following steps
   are necessary to unlock Account's CELO from the LockedGold contract and
   actually distribute them to the user.
2. Call `Account.withdraw` for each group that was scheduled to be withdrawn
   from in the previous step. Some CELO might be available for immediate
   withdrawal, if it hadn't been yet locked and used for voting, and will be
   transferred to the user. For the rest of the withdrawal amount, it will be
   unvoted from the specified group and the LockedGold unlocking process will
   begin.
3. After the 3 day unlocking period has passed,
   `Account.finishPendingWithdrawal` should be called, specifying the pending
   withdrawal that was created in the previous step. This will finalize the
   LockedGold withdrawal and return the remaining CELO to the user.


## Updating Devchain Chain Data with Staked CELO Contracts

This section will walk you through how to generate a new devchain tarball containing deployed staked CELO contracts.

### Deploying Staked CELO Contracts to Local Devchain

First open a terminal and run the `devchain` and specify the path to store the chain data. This will need to stay running until we have generated the new tarball.

```bash
yarn devchain --db db/
```

In a separate terminal, deploy all staked CELO contracts to the current local network.

```bash
yarn deploy:devchain
```

This will create `deployments/devchain/` directory that contains functions to easily access deployments using hardhat-deploy. 

See [hardhat-deploy](https://github.com/wighawag/hardhat-deploy#migrating-existing-deployment-to-hardhat-deploy) for more details on how to use existing deployments.

Once deployed, devchain can safely be stopped.

### Generating New Chain Data Tar

Once the contracts are successfully deployed to the network, compress the chain data. 

**NB:** This next part assumes that you already have a local copy of [celo-monorepo](https://github.com/celo-org/celo-monorepo) on your machine. If not, follow the instructions on how to get setup [here](https://github.com/celo-org/celo-monorepo/blob/master/SETUP.md).

```bash
> yarn tarchain run --datadir <path_to_datadir> --monorepo <path_to_monorepo>
```

### Testing the New Devchain Tarball

Run devchain using staked CELO devchain.

```bash
yarn run celo-devchain --port 7545 --file <path_to_tarball>
```

Once ganache has started, run the test script to ensure all contracts were deployed properly.

```bash
yarn test scripts/test/devchain.test.ts
```

## Develop Against Unreleased Staked CELO Contracts.

**NB:** The following assumes that you are using [celo-devchain](https://www.npmjs.com/package/@terminal-fi/celo-devchain) & [hardhat-deploy](https://www.npmjs.com/package/hardhat-deploy) packages.

In order to use the tarball containing the staked CELO contracts, you will need to add the external deployments files and configure the hardhat network  in `hardhat.config.ts` accordingly.

``` ts 
external: {
    deployments: {
      // Specify path to deployment data
      hardhat: ["chainData/deployments/devchain"],
    }
  },

namedAccounts: {
    deployer: {
      default: 0,
    },
    multisigOwner0: {
      default: 3,
    },
    multisigOwner1: {
      default: 4,
    },
    multisigOwner2: {
      default: 5,
    },
  },

networks: {
    hardhat: {
      forking: {
        // Local devchain
        url: "http://localhost:7545",
        blockNumber: 780,
      },
      // Mnemonic used to access multisig owner accounts.
      accounts: { mnemonic: "concert load couple harbor equip island argue ramp clarify fence smart topic" },
    },
  },
```
## Upgrade contract
1. Make your changes to smart contract (eg Manager.sol)
2. Run command
``` bash
yarn hardhat stakedCelo:deploy  --network [network] --show-stack-traces --tags [tag of deploy script] --from "[deployer address]" --use-private-key
``` 
Example
``` bash
> yarn hardhat stakedCelo:deploy  --network alfajores --show-stack-traces --tags proxy --from "0x5bC1C4C1D67C5E4384189302BC653A611568a788" --use-private-key
```
Since contracts are owned by MultiSig, proxy implementations will be deployed but upgrade itself will not go through (see example below).

Example of change in Manager.sol deployment

``` bash
reusing "MultiSig_Implementation" at 0xF2549E83Fdb86bebe7e1E2c64FB3a2BB2bBeb333
deploying "Manager_Implementation" (tx: 0xf0e99332761b1c4cf52f2280b14adcf873535e4a2b735918b2dd78707db19cd1)...: deployed at 0x1B8Ee2E0A7fC6d880BA86eD7925a473eA7C28000 with 3825742 gas
Transaction was reverted since caller is not an owner. Please make sure to update the proxy implementation manually.
```

From above example we can see that our new implementation address is `0x1B8Ee2E0A7fC6d880BA86eD7925a473eA7C28000`

3. Verify deployed smart contracts (It will verify whatever is in deployments/[network] folder)
``` bash
> yarn verify:deploy --network [network]
```
4. Generate payload for proposal

Please note that this script expects to have particular contract present in deployments/[network] folder

``` bash
> yarn hardhat stakedCelo:multiSig:encode:proposal:payload --contract [contract name] --function [function name] --args [arguments separated by ,] --network [network]

# example
> yarn hardhat stakedCelo:multiSig:encode:proposal:payload --contract Manager --function upgradeTo --args 0x1B8Ee2E0A7fC6d880BA86eD7925a473eA7C28000 --network alfajores
```

Please note that args are from step 2

Example of encoded proposal payload
``` bash
encoded payload:
0x3659cfe60000000000000000000000007e71fb21d0b30f5669f8f387d4a1114294f8e418
```

5. Submit multisig proposal to change implementation of proxy
``` bash
> yarn hardhat stakedCelo:multiSig:submitProposal --destinations [destinations separated by ,] --values [transaction values separated by ,] --payloads [payloads separated by , from previous step] --account [address] --network [network]

# example
> yarn hardhat stakedCelo:multiSig:submitProposal --destinations 0xf68665Ad492065d7d6f2ea26d180f86A585455Ab --values 0 --payloads 0x3659cfe60000000000000000000000007e71fb21d0b30f5669f8f387d4a1114294f8e418 --account 0x5bC1C4C1D67C5E4384189302BC653A611568a788 --network alfajores
```

Note: `--destinations` is the target proxy contract whose implementation is being upgraded.

6. Execute proposal once it is approved

``` bash
> yarn hardhat stakedCelo:multiSig:executeProposal --network [network] --proposal-id [index of proposal] --account [address]

# example
> yarn hardhat stakedCelo:multiSig:executeProposal --network alfajores --proposal-id 0 --account 0x5bC1C4C1D67C5E4384189302BC653A611568a788
```

## Vote deploy when rest of contracts is already deployed
1. Run only deploy scripts related to Vote contract
``` bash
> yarn hardhat stakedCelo:deploy --show-stack-traces --network alfajores --tags core
```
2. Run task to set Vote address in Manager contract
``` bash
> yarn hardhat stakedCelo:multisig:encode:managerSetDependencies --network alfajores
```
3. Insert returned values into submitProposal task (it can be found few lines above)

## Vote for governance proposal

``` bash
>  yarn hardhat stakedCelo:manager:voteProposal --network [network] --proposal-id [governance proposal id] --yes [# of votes] --account [address]

# example
>  yarn hardhat stakedCelo:manager:voteProposal --network alfajores --proposal-id 10 --yes 100 --no 0 --abstain 0 --account 0x456f41406B32c45D59E539e4BBA3D7898c3584dA
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for style and how to contribute.
All communication and contributions to this project are subject to the [Celo Code of Conduct](code-of-conduct.md).
