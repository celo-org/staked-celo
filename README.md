# StakedCelo

StakedCelo is a liquid staking derivative of CELO, the native token on the Celo
blockchain.

Users can deposit CELO to the Staked Celo smart contract and receive stCelo tokens in return, allowing them to earn staking rewards.

## Testing

To run tests first fire up a terminal and start the `devchain`, this will need to be run only once and you should keep it running.  

```bash
yarn devchain
```

Then in another terminal run tests:

```bash
yarn test # run all tests
yarn test <path to file> # run a specific file
```

Run prettier to lint and write - this is also done automatically in a pre-commit hook.

```bash
yarn lint
```

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
yarn verify --network alfajores
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


## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for style and how to contribute.
