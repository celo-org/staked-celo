# StakedCelo

NOTE: audit in progress, not for production use.

StakedCelo is a liquid staking derivative of CELO, the native token on the Celo
blockchain.

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for style and how to contribute.
