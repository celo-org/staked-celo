// End-to-end regression test for the "stuck withdrawal" root cause.
//
// REAL contracts only - no mocks. Reproduces the production scenario where
// a validator group's scheduled votes can no longer be voted because an
// external voter saturated the Election cap. The activate-bot silently
// skips the group, scheduledVotes.toVote stays bloated, and `getCeloForGroup`
// reports inflated capacity. Pre-fix this caused `Manager.withdraw` to
// schedule a withdrawal that the bot's `Account.withdraw` would later revert
// with `InsufficientRevokableVotes`, permanently pinning user CELO.
//
// Verifies the load-bearing mitigations end-to-end:
//   1. PREVENTION - `Account.scheduleWithdrawals` rejects pins above
//      realisable capacity (via `getRealisableCeloForGroup`), so the user's
//      stCELO is NEVER burned into an unfulfillable pin.
//   2. RESCUE - `Account.rescueScheduledWithdrawal` (permissionless) re-routes
//      any pre-existing pin to groups with capacity when the source group is
//      provably in deficit for the beneficiary.
//   3. CLEANUP - `DefaultStrategy.rebalanceOverallocatedGroup` drains a
//      bloated group's stCELO allocation back to other active groups.

import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import BigNumberJs from "bignumber.js";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import { StakedCelo } from "../typechain-types/StakedCelo";
import {
  activateAndVoteTest,
  prepareOverflow,
  randomSigner,
  resetNetwork,
  upgradeToMockGroupHealthE2E,
} from "./utils";
import {
  activateValidators,
  electMockValidatorGroupsAndUpdate,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
} from "./utils-validators";

after(() => {
  hre.kit.stop();
});

describe("e2e stuck-withdrawal regression", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let groupHealthContract: MockGroupHealth;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategy: DefaultStrategy;
  let stakedCelo: StakedCelo;
  let election: ElectionWrapper;
  let lockedGold: LockedGoldWrapper;

  let depositor: SignerWithAddress;
  let secondDepositor: SignerWithAddress;
  let voter: SignerWithAddress;
  let randomCaller: SignerWithAddress;
  let multisigOwner0: SignerWithAddress;

  let groups: SignerWithAddress[];
  let activatedGroupAddresses: string[];

  // eslint-disable-next-line no-unused-vars, @typescript-eslint/no-explicit-any
  before(async function (this: any) {
    this.timeout(0);
    await resetNetwork();

    process.env = {
      ...process.env,
      TIME_LOCK_MIN_DELAY: "1",
      TIME_LOCK_DELAY: "1",
      MULTISIG_REQUIRED_CONFIRMATIONS: "1",
      VALIDATOR_GROUPS: "",
    };

    [depositor] = await randomSigner(parseUnits("10000"));
    [secondDepositor] = await randomSigner(parseUnits("10000"));
    [voter] = await randomSigner(parseUnits("10000000000"));
    [randomCaller] = await randomSigner(parseUnits("100"));

    const accounts = await hre.kit.contracts.getAccounts();
    await accounts.createAccount().sendAndWaitForReceipt({ from: voter.address });

    groups = [];
    activatedGroupAddresses = [];
    for (let i = 0; i < 11; i++) {
      const [g] = await randomSigner(parseUnits("21000"));
      groups.push(g);
    }
    for (let i = 0; i < 11; i++) {
      if (i === 1) {
        await registerValidatorGroup(groups[i], 2);
        const [v, w] = await randomSigner(parseUnits("11000"));
        await registerValidatorAndAddToGroupMembers(groups[i], v, w);
      } else {
        await registerValidatorGroup(groups[i], 1);
      }
      if (i < 3) activatedGroupAddresses.push(groups[i].address);
      const [v, w] = await randomSigner(parseUnits("11000"));
      await registerValidatorAndAddToGroupMembers(groups[i], v, w);
    }
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    groupHealthContract = await hre.ethers.getContract("GroupHealth");
    specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");
    defaultStrategy = await hre.ethers.getContract("DefaultStrategy");
    stakedCelo = await hre.ethers.getContract("StakedCelo");
    lockedGold = await hre.kit.contracts.getLockedGold();
    election = await hre.kit.contracts.getElection();

    multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");

    groupHealthContract = await upgradeToMockGroupHealthE2E(
      multisigOwner0,
      groupHealthContract as unknown as GroupHealth
    );
    const validatorWrapper = await hre.kit.contracts.getValidators();
    await electMockValidatorGroupsAndUpdate(validatorWrapper, groupHealthContract, [
      ...activatedGroupAddresses,
      groups[5].address,
    ]);

    await activateValidators(
      defaultStrategy,
      groupHealthContract as unknown as GroupHealth,
      multisigOwner0,
      activatedGroupAddresses
    );

    // Burn through Election cap on groups[0..2] so the per-group voting
    // limit is small (~40-200 CELO). This is the same setup the existing
    // e2e overflow test uses to deterministically trigger "scheduled votes
    // not activatable" via a follow-up external vote.
    await prepareOverflow(
      defaultStrategy,
      election,
      lockedGold,
      voter,
      activatedGroupAddresses,
      false
    );

    // Pre-lock a big chunk of voter CELO so per-test `externalVoterSaturates`
    // calls don't move `numVotesReceivable` (the cap formula scales with
    // total locked gold). Locking up-front keeps the cap stable for the
    // subsequent vote.
    await lockedGold.lock().sendAndWaitForReceipt({
      from: voter.address,
      value: parseUnits("100000").toString(),
    });
  });

  /**
   * Trigger the bug condition: external voter votes the remaining cap PLUS
   * the protocol's current scheduledToVote for `group`. After this call,
   * `Election.canReceiveVotes(group, X)` returns false for any positive X,
   * so the activate-bot silently skips the group and `scheduledVotes.toVote`
   * accumulates without ever becoming active votes. This is the exact
   * mechanism that bloated `0x81AE...` on mainnet.
   */
  async function externalVoterSaturatesGroup(group: string): Promise<void> {
    // Voter already has 100k CELO locked (from beforeEach). Measure the
    // current receivable + protocol-scheduled and vote that exact amount;
    // voting won't change `numVotesReceivable` (only locking does), so
    // headroom drops to zero and stays there.
    const receivable = await managerContract.getReceivableVotesForGroup(group);
    const scheduled = await accountContract.scheduledVotesForGroup(group);
    const total = receivable.add(scheduled);
    if (total.lte(0)) return;
    const voteTx = await election.vote(group, new BigNumberJs(total.toString()));
    await voteTx.sendAndWaitForReceipt({ from: voter.address });
  }

  // EXACT mainnet 0x81AE shape reproduction. Uses scheduleTransfer (not
  // scheduleVotes) to inject the UNBACKED toVote that mainnet reached via
  // accumulated transfer / cap-exhaustion history: target group has toVote
  // bookkeeping with no matching Account.balance and no revokable Election
  // votes. scheduleWithdrawals validates against getRealisableCeloForGroup
  // which excludes unbacked toVote (balance cap = 0) -> reverts with
  // WithdrawalAmountTooHigh, preventing the stuck pin at the boundary.
  it("PREVENTION (EXACT root-cause shape, forum.celo.org/t/.../13333): scheduleWithdrawals reverts when group's toVote is not backed by Account.balance", async () => {
    // a. depositor default-deposits enough to spread allocation across
    //    multiple default groups, then activate-bot votes -> real active
    //    votes on each. Account.balance drained into LockedGold.
    await managerContract.connect(depositor).deposit({ value: parseUnits("60") });
    await managerContract.connect(secondDepositor).deposit({ value: parseUnits("60") });
    await activateAndVoteTest();

    const balancePostActivate = await hre.ethers.provider.getBalance(accountContract.address);
    expect(balancePostActivate.eq(0)).to.equal(
      true,
      "test setup: Account.balance must be drained by activate so toVote injection stays unbacked"
    );

    // Find a default group (NOT groups[2], which is the destination) with
    // positive active votes to be the scheduleTransfer source. Use the
    // smallest viable amount to fit any single group's allocation.
    let sourceGroup: string | undefined;
    let sourceCelo = hre.ethers.BigNumber.from(0);
    for (const g of activatedGroupAddresses) {
      if (g === groups[5].address) continue;
      const celoForG = await accountContract.getCeloForGroup(g);
      if (celoForG.gt(sourceCelo)) {
        sourceGroup = g;
        sourceCelo = celoForG;
      }
    }
    expect(sourceCelo.gt(0)).to.equal(
      true,
      "test setup: no default group (excluding dest) has any active capacity to serve as transfer source"
    );
    const staleToVote = sourceCelo.lt(parseUnits("20")) ? sourceCelo : parseUnits("20");

    // b. Manager-impersonate scheduleTransfer to move toVote bookkeeping
    //    onto groups[2] (destination) WITHOUT touching Account.balance.
    //    This matches the in-flight-transfer shape mainnet 0x81AE reached
    //    organically.
    const managerSigner = await asManager();
    await accountContract
      .connect(managerSigner)
      .scheduleTransfer([sourceGroup as string], [staleToVote], [groups[5].address], [staleToVote]);

    // c. SANITY: groups[2] has toVote bookkeeping but no balance and no
    //    revokable Election votes. getCeloForGroup inflated by stale
    //    toVote; getRealisableCeloForGroup discards it via balance cap.
    expect(await accountContract.scheduledVotesForGroup(groups[5].address)).to.equal(staleToVote);
    const inflated = await accountContract.getCeloForGroup(groups[5].address);
    const realisable = await accountContract.getRealisableCeloForGroup(groups[5].address);
    expect(inflated.gte(staleToVote)).to.equal(true, "inflated must include stale toVote");
    expect(realisable.eq(0)).to.equal(
      true,
      `realisable must be 0 for unbacked toVote, got ${realisable}`
    );

    // d. Manager-impersonate scheduleWithdrawals against the unbacked pin.
    //    Pre-fix: validation against getCeloForGroup PASSES, stCELO burned,
    //    bot later stuck. Post-fix: validation uses getRealisableCeloForGroup,
    //    sees 0 capacity, reverts WithdrawalAmountTooHigh. stCELO never
    //    burned, user never pinned.
    await expect(
      accountContract
        .connect(managerSigner)
        .scheduleWithdrawals(depositor.address, [groups[5].address], [staleToVote])
    ).revertedWith(`WithdrawalAmountTooHigh("${groups[5].address}", 0, ${staleToVote})`);

    // e. No pin was created.
    expect(
      await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(
        groups[5].address,
        depositor.address
      )
    ).to.equal(0);
  });

  /**
   * Helper: impersonate Manager to call onlyManager Account functions.
   * Lets tests set up exact Account state (toVote inflation, earmarks)
   * that would normally require many natural deposit/strategy events.
   */
  async function asManager() {
    const managerAddr = managerContract.address;
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [managerAddr],
    });
    await hre.network.provider.send("hardhat_setBalance", [
      managerAddr,
      "0x10000000000000000000000",
    ]);
    return await hre.ethers.getSigner(managerAddr);
  }

  it("STRATEGY-SWAP (SpecificGroupStrategy:364): SGS reverts GroupNotBalanced (NOT WithdrawalAmountTooHigh) when overflow remainder exceeds realisable", async () => {
    // SGS line 364 uses getRealisableCeloForGroup (post-swap) to check
    // the overflow remainder. Without the swap, SGS would use the
    // inflated getCeloForGroup, pass through to Account.scheduleWithdrawals
    // which fires WithdrawalAmountTooHigh - different error. The asserted
    // GroupNotBalanced revert is what only the swap produces.

    // a0. secondDepositor builds active votes on multiple default groups
    //     so DS overflow distribution (called from SGS later) has capacity
    //     to absorb the overflow withdrawal portion.
    await managerContract.connect(secondDepositor).deposit({ value: parseUnits("50") });
    await activateAndVoteTest();

    // a. Build active votes on groups[1] BEFORE saturation.
    await managerContract.connect(depositor).changeStrategy(groups[1].address);
    await managerContract.connect(depositor).deposit({ value: parseUnits("50") });
    await activateAndVoteTest();

    // b. Saturate groups[1] cap so subsequent deposit overflows.
    await externalVoterSaturatesGroup(groups[1].address);

    // c. Tiny extra deposit overflows to default, recording
    //    stCeloInGroupOverflowed[g[1]] > 0. Keep small so DS overflow
    //    distribution can satisfy the matching withdrawal.
    await managerContract.connect(depositor).deposit({ value: parseUnits("10") });
    const [, overflowStCelo] = await specificGroupStrategyContract.getStCeloInGroup(
      groups[1].address
    );
    expect(overflowStCelo.gt(0)).to.equal(true, "test setup invalid: SGS overflow not recorded");

    // d. Earmark a separate scheduled withdrawal on g[1] so realisable
    //    drops BELOW the post-overflow remainder. Earmark 30 fits within
    //    current realisable (~50 active) so the load-bearing Account
    //    check at scheduleWithdrawals doesn't revert here.
    const managerSigner = await asManager();
    await accountContract
      .connect(managerSigner)
      .scheduleWithdrawals(voter.address, [groups[1].address], [parseUnits("30")]);

    const realisable = await accountContract.getRealisableCeloForGroup(groups[1].address);
    expect(realisable.lt(parseUnits("50"))).to.equal(
      true,
      "test setup invalid: realisable must be < remainder for SGS swap to fire"
    );

    // e. depositor.withdraw the full position (~60 CELO).
    //    SGS overflow branch:
    //      - celoToBeMovedFromDefaultStrategy ≈ 10 (overflow portion)
    //      - celoWithdrawalAmount remainder ≈ 50 (specific portion)
    //    realisable(g[1]) after earmark ≈ 20.
    //    Remainder(50) > realisable(20) -> SGS line 364 fires
    //    GroupNotBalanced (with swap). Without swap: SGS passes,
    //    Account.scheduleWithdrawals fires WithdrawalAmountTooHigh.
    const stCeloBefore = await stakedCelo.balanceOf(depositor.address);
    await expect(managerContract.connect(depositor).withdraw(stCeloBefore)).revertedWith(
      `GroupNotBalanced("${groups[1].address}")`
    );
  });

  it("STRATEGY-SWAP (DefaultStrategy:530): DS distribution caps allocation by realisable, splitting withdrawal across groups instead of pinning to over-allocated HEAD", async () => {
    // With swap: DS distribution caps per-group allocation by realisable;
    // spillover routed to siblings; Manager.withdraw succeeds.
    // Without swap: DS allocates inflated amount to HEAD; Account swap at
    // scheduleWithdrawals rejects with WithdrawalAmountTooHigh.

    // a. Build allocation across multiple groups so siblings can absorb
    //    spillover.
    await managerContract.connect(depositor).deposit({ value: parseUnits("30") });
    await managerContract.connect(depositor).deposit({ value: parseUnits("30") });
    await activateAndVoteTest();
    const [headGroup] = await defaultStrategy.getGroupsHead();

    // b. Earmark some HEAD capacity for another beneficiary so realisable
    //    < toCelo(stCeloInGroup) - the swap binding term.
    const managerSigner = await asManager();
    await accountContract
      .connect(managerSigner)
      .scheduleWithdrawals(voter.address, [headGroup], [parseUnits("10")]);

    const realisableBefore = await accountContract.getRealisableCeloForGroup(headGroup);
    const stCeloAlloc = await defaultStrategy.stCeloInGroup(headGroup);
    const toCeloAlloc = await managerContract.toCelo(stCeloAlloc);
    expect(toCeloAlloc.gt(realisableBefore)).to.equal(
      true,
      "test setup invalid: toCelo(stCeloInGroup) must exceed realisable for swap to matter"
    );

    // c. Withdraw a SMALL amount just over realisable so spillover fits
    //    sibling groups. With swap: distribution caps HEAD at realisable
    //    and routes spillover. Without swap: HEAD over-allocated, Account
    //    validation reverts.
    const withdrawCelo = realisableBefore.add(parseUnits("2"));
    const withdrawStCelo = await managerContract.toStakedCelo(withdrawCelo);
    await managerContract.connect(depositor).withdraw(withdrawStCelo);

    // d. Per-group cap on HEAD <= pre-call realisable. Without DS swap,
    //    HEAD would have been allocated more (or Manager.withdraw would
    //    have reverted upstream, failing the line above).
    const scheduledOnHead = await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(
      headGroup,
      depositor.address
    );
    expect(scheduledOnHead.lte(realisableBefore)).to.equal(
      true,
      `scheduledOnHead(${scheduledOnHead}) > realisable(${realisableBefore}) - DS swap not enforced`
    );
  });

  it("REGRESSION P1: scheduleWithdrawals must reject unbacked toVote from in-flight transfer", async () => {
    // Codex P1 finding. After Account.scheduleTransfer(A -> B, X) the protocol
    // sets toRevoke[A] = X and toVote[B] = X but the matching CELO is still
    // locked under A in LockedGold (Account.balance ≈ 0). Until the activate-bot
    // executes the revoke on A AND the new vote on B, B's toVote is "unbacked":
    // no Account.balance, no revokable(B), only future-intent bookkeeping.
    //
    // Current getRealisableCeloForGroup formula:
    //   revokable + min(toVote, electionHeadroom)
    // For B: 0 + min(X, big_headroom) = X. So scheduleWithdrawals(B, X) PASSES.
    // Bot's Account.withdraw(B):
    //   immediateWithdrawalAmount = min(balance=0, toVote_B) = 0
    //   revokeAmount = X
    //   _revokeVotes(B, X) -> revokable(B)=0 -> InsufficientRevokableVotes
    // -> new stuck pin in the rebalance window. Same class of bug as the
    // 0x81AE forum case, just triggered via scheduleTransfer instead of
    // deposit + cap-exhaustion.
    //
    // Required behavior: scheduleWithdrawals MUST reject at the boundary so
    // no pin is created. Test asserts the revert.

    // a. Build real active votes on groups[0] so scheduleTransfer's
    //    getCeloForGroup(A) validation passes and CELO is locked in LockedGold.
    await managerContract.connect(depositor).changeStrategy(groups[0].address);
    await managerContract.connect(depositor).deposit({ value: parseUnits("30") });
    await activateAndVoteTest();

    const celoForA = await accountContract.getCeloForGroup(groups[0].address);
    expect(celoForA.gte(parseUnits("20"))).to.equal(
      true,
      "test setup: A must have enough active votes for transfer"
    );

    // b. Pick B = groups[5] (registered + elected via electMockValidatorGroupsAndUpdate,
    //    but NOT pre-saturated by prepareOverflow). Full headroom, zero protocol votes.
    const groupB = groups[5].address;
    const headroomB = await managerContract.getReceivableVotesForGroup(groupB);
    expect(headroomB.gte(parseUnits("20"))).to.equal(true, "test setup: B must have headroom");

    // c. Impersonate Manager to call Account.scheduleTransfer(A -> B, X).
    //    Pure bookkeeping move. CELO does NOT move - stays locked under A
    //    awaiting revoke.
    const managerSigner = await asManager();
    const transferAmt = parseUnits("20");
    await accountContract
      .connect(managerSigner)
      .scheduleTransfer([groups[0].address], [transferAmt], [groupB], [transferAmt]);

    // d. Confirm bug shape on B via the ethers-typed read paths.
    const electionAbi = [
      "function getTotalVotesForGroupByAccount(address,address) view returns (uint256)",
    ];
    const electionAddr = await hre.kit.registry.addressFor("Election" as never);
    const electionEthers = new hre.ethers.Contract(electionAddr, electionAbi, hre.ethers.provider);
    const revokableB = await electionEthers.getTotalVotesForGroupByAccount(
      groupB,
      accountContract.address
    );
    expect(revokableB.eq(0)).to.equal(true, "B has no revokable Election votes");

    const balanceBefore = await hre.ethers.provider.getBalance(accountContract.address);
    expect(balanceBefore.lt(transferAmt)).to.equal(
      true,
      `test setup: Account.balance (${balanceBefore}) must be insufficient to back the unbacked toVote (${transferAmt})`
    );

    const realisableB = await accountContract.getRealisableCeloForGroup(groupB);
    // CURRENT (buggy) code reports realisableB ≈ transferAmt. POST-FIX
    // (drop unbacked toVote contribution) reports 0. Either way, the next
    // assertion - that scheduleWithdrawals reverts - is the load-bearing one.

    // e. scheduleWithdrawals(beneficiary, B, transferAmt). Bot's later
    //    Account.withdraw(B) would revert InsufficientRevokableVotes since
    //    revokable(B)=0 and balance≈0. Required: revert at boundary so no
    //    pin is ever created.
    await expect(
      accountContract
        .connect(managerSigner)
        .scheduleWithdrawals(depositor.address, [groupB], [transferAmt])
    ).reverted;

    // f. No pin created.
    expect(
      await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(groupB, depositor.address)
    ).to.equal(0);

    // g. Diagnostic surface for the PR conversation.
    // eslint-disable-next-line no-console
    console.log(
      `[P1] realisable(B)=${realisableB} revokable(B)=${revokableB} balance=${balanceBefore} transferAmt=${transferAmt}`
    );
  });

  it("REGRESSION P2: distribution loop must skip zero-realisable HEAD instead of wedging", async () => {
    // Codex P2 finding. When sorted HEAD has stCeloInGroup > 0 but
    // getRealisableCeloForGroup returns 0:
    //   votes[i] = min(min(0, toCelo(stCelo)), celoAmount) = 0
    //   _updateGroupStCelo(HEAD, toStakedCelo(0)=0, false) - no-op
    //   trySort(HEAD, unchanged, false) - position unchanged, sorted stays true
    //   sorted -> votedGroup = activeGroups.getHead() (SAME)
    //   groupsIndex++ - slot burned
    // After maxGroupsToWithdrawFrom iterations: celoAmount != 0 ->
    // NotAbleToDistributeVotes. Distribution wedges even when tail groups
    // have plenty of capacity. Regression introduced by this PR - pre-fix
    // getCeloForGroup almost never returned 0 because toVote padded it.
    //
    // Required behavior: skip zero-realisable group without consuming a
    // slot or re-selecting HEAD; allocate remainder from tail groups.

    // a. Spread stCELO across all three active groups via two depositors.
    await managerContract.connect(depositor).deposit({ value: parseUnits("30") });
    await managerContract.connect(secondDepositor).deposit({ value: parseUnits("30") });
    await activateAndVoteTest();

    const [headGroup] = await defaultStrategy.getGroupsHead();
    const headStCeloBefore = await defaultStrategy.stCeloInGroup(headGroup);
    expect(headStCeloBefore.gt(0)).to.equal(true);

    // b. Drain HEAD's realisable to 0 by earmarking the full revokable to a
    //    separate beneficiary. stCeloInGroup[HEAD] is UNCHANGED so HEAD
    //    remains HEAD of the sorted list.
    const realisableHeadBefore = await accountContract.getRealisableCeloForGroup(headGroup);
    expect(realisableHeadBefore.gt(0)).to.equal(true, "test setup: HEAD must have realisable");
    const managerSigner = await asManager();
    await accountContract
      .connect(managerSigner)
      .scheduleWithdrawals(voter.address, [headGroup], [realisableHeadBefore]);

    expect(await accountContract.getRealisableCeloForGroup(headGroup)).to.equal(
      0,
      "test setup: HEAD realisable must be drained to 0"
    );
    expect(await defaultStrategy.stCeloInGroup(headGroup)).to.equal(
      headStCeloBefore,
      "test setup: HEAD stCelo allocation must be unchanged"
    );

    // c. Confirm HEAD is still the sorted HEAD. Otherwise the test doesn't
    //    exercise the wedge.
    const [headStill] = await defaultStrategy.getGroupsHead();
    expect(headStill).to.equal(headGroup, "test setup: HEAD must still be HEAD");

    // d. depositor.withdraw small amount that tail groups can satisfy.
    //    Pre-fix: distribution loop wedges on HEAD, reverts
    //    NotAbleToDistributeVotes. Post-fix: skips HEAD, allocates from tail.
    const smallStCelo = parseUnits("5");
    await managerContract.connect(depositor).withdraw(smallStCelo);

    // e. HEAD must have received 0 allocation.
    const headAlloc = await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(
      headGroup,
      depositor.address
    );
    expect(headAlloc).to.equal(0, "HEAD should have been skipped (zero realisable)");

    // f. At least one tail group must have absorbed the withdrawal.
    let tailAbsorbed = hre.ethers.BigNumber.from(0);
    for (const g of activatedGroupAddresses) {
      if (g === headGroup) continue;
      tailAbsorbed = tailAbsorbed.add(
        await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(g, depositor.address)
      );
    }
    expect(tailAbsorbed.gt(0)).to.equal(true, "tail groups must have absorbed the withdrawal");
  });

  it("REGRESSION P2 #4: distribution must not return same group twice when over-allocated HEAD has stCelo > realisable", async () => {
    // Codex follow-up finding. When realisable < stCelo for the sorted HEAD,
    // the loop picks `capacity = realisable`, decrements stCelo, trySort
    // keeps HEAD as HEAD (still largest), `sorted == true` re-selects
    // getHead() = same group. realisable hasn't changed (Account state is
    // not mutated until scheduleWithdrawals runs after distribution returns).
    // Result: same group appears twice in (groups, votes). scheduleWithdrawals
    // accepts the first entry (earmarks realisable), then on the second
    // entry sees `revokable - earmarked = 0` and reverts WithdrawalAmountTooHigh.
    // Required: each group appears at most once per distribution; spill to
    // tail groups when HEAD's physical capacity is exhausted.

    // a. Spread baseline deposit across all three active groups via three
    //    separate small deposits. Each goes to the current TAIL (smallest
    //    stCelo) so allocation spreads round-robin instead of all landing
    //    on one group. After three deposits + activate, each group has
    //    revokable Election votes (positive realisable on g0, g1, g2).
    await managerContract.connect(depositor).deposit({ value: parseUnits("15") });
    await managerContract.connect(depositor).deposit({ value: parseUnits("15") });
    await managerContract.connect(depositor).deposit({ value: parseUnits("15") });
    await activateAndVoteTest();

    // b. Bloat HEAD's DefaultStrategy allocation via owner-only
    //    updateGroupStCelo (simulates the over-allocated state from
    //    accumulated rebalance / transferWithoutChecks events on mainnet).
    //    Impersonate the MultiSig contract which owns DefaultStrategy.
    const multisigAddr = (await hre.deployments.get("MultiSig")).address;
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [multisigAddr],
    });
    await hre.network.provider.send("hardhat_setBalance", [multisigAddr, "0x1000000000000000000"]);
    const multisigSigner = await hre.ethers.getSigner(multisigAddr);
    const [headGroupPre] = await defaultStrategy.getGroupsHead();
    // Bloat the current HEAD with 500 stCELO so it stays HEAD across many
    // decrement iterations during withdrawal distribution.
    await defaultStrategy
      .connect(multisigSigner)
      .updateGroupStCelo(headGroupPre, parseUnits("500"), true);

    const [headGroup] = await defaultStrategy.getGroupsHead();
    const headStCelo = await defaultStrategy.stCeloInGroup(headGroup);
    const headStCeloAsCelo = await managerContract.toCelo(headStCelo);

    // b. Earmark almost all of HEAD's revokable so realisable drops to 1 CELO
    //    while stCelo allocation remains huge (200 CELO equivalent).
    const realisableBefore = await accountContract.getRealisableCeloForGroup(headGroup);
    expect(realisableBefore.gt(parseUnits("10"))).to.equal(
      true,
      "test setup: HEAD needs enough realisable for partial earmark"
    );
    const earmarkAmount = realisableBefore.sub(parseUnits("1"));
    const managerSigner = await asManager();
    await accountContract
      .connect(managerSigner)
      .scheduleWithdrawals(voter.address, [headGroup], [earmarkAmount]);

    const realisable = await accountContract.getRealisableCeloForGroup(headGroup);
    expect(realisable.eq(parseUnits("1"))).to.equal(
      true,
      `test setup: realisable must be exactly 1 CELO, got ${realisable}`
    );
    expect(headStCeloAsCelo.gt(realisable.mul(50))).to.equal(
      true,
      `test setup: HEAD must dominate (stCeloAsCelo ${headStCeloAsCelo} >> realisable*50 ${realisable.mul(
        50
      )})`
    );

    const [headStill] = await defaultStrategy.getGroupsHead();
    expect(headStill).to.equal(headGroup, "test setup: HEAD must still be HEAD");

    // c. depositor withdraws 5 CELO. Pre-fix: distribution returns HEAD 5
    //    times (HEAD stays HEAD across decrements, realisable doesn't shrink
    //    in distribution), then scheduleWithdrawals reverts on the second
    //    entry because earmarked exceeds revokable. Post-fix: HEAD allocated
    //    once at its 1 CELO cap, remaining 4 CELO routed to tail groups.
    const withdrawStCelo = await managerContract.toStakedCelo(parseUnits("5"));
    await managerContract.connect(depositor).withdraw(withdrawStCelo);

    // d. HEAD allocated at most its realisable cap.
    const headPin = await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(
      headGroup,
      depositor.address
    );
    expect(headPin.lte(realisable)).to.equal(
      true,
      `HEAD pin ${headPin} exceeded realisable ${realisable}`
    );

    // e. Some tail group absorbed the spill.
    let tailAbsorbed = hre.ethers.BigNumber.from(0);
    for (const g of activatedGroupAddresses) {
      if (g === headGroup) continue;
      tailAbsorbed = tailAbsorbed.add(
        await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(g, depositor.address)
      );
    }
    expect(tailAbsorbed.gt(0)).to.equal(
      true,
      "tail groups must have absorbed the spill over HEAD's realisable"
    );
  });

  it("REGRESSION P1 #2: scheduleWithdrawals must accept balance-backed toVote even when Election cap is full", async () => {
    // Codex P1 #2: Account.withdraw's immediate path serves
    // min(balance, toVote) via getGoldToken().transfer - it does NOT
    // call Election.vote and so does not need headroom. A previous
    // over-restrictive realisable that gated toVote on
    // electionHeadroom blocked legitimate withdrawals where the
    // immediate path could have served them right away.
    //
    // Setup: deposit via specific strategy, saturate cap BEFORE
    // activate-bot runs. balance still backs the un-activated toVote
    // because the bot's activateAndVote silently reverts on cap-full.
    // Withdraw must SUCCEED via the immediate path (no headroom
    // required) - assert no revert, full amount delivered.

    await managerContract.connect(depositor).changeStrategy(groups[1].address);
    await managerContract.connect(depositor).deposit({ value: parseUnits("50") });

    await externalVoterSaturatesGroup(groups[1].address);
    await activateAndVoteTest();

    const balance = await hre.ethers.provider.getBalance(accountContract.address);
    const toVote = await accountContract.scheduledVotesForGroup(groups[1].address);
    expect(balance.gte(parseUnits("50"))).to.equal(
      true,
      `test setup: balance must back toVote (got balance=${balance})`
    );
    expect(toVote.gte(parseUnits("50"))).to.equal(
      true,
      `test setup: toVote must be set (got ${toVote})`
    );

    // Realisable must include balance-backed toVote even with headroom=0.
    const realisable = await accountContract.getRealisableCeloForGroup(groups[1].address);
    expect(realisable.gte(parseUnits("50"))).to.equal(
      true,
      `realisable must include balance-backed toVote, got ${realisable}`
    );

    // Manager.withdraw must succeed - Account.withdraw's immediate path
    // delivers from balance without needing Election headroom.
    const stCeloBefore = await stakedCelo.balanceOf(depositor.address);
    await managerContract.connect(depositor).withdraw(stCeloBefore);
    expect(await stakedCelo.balanceOf(depositor.address)).to.equal(0);
  });

  it("REGRESSION P2 #1: rescue must reject when liquid toVote+balance covers user's claim", async () => {
    // Codex P2 #1: per-beneficiary deficit check must count
    // min(balance, toVote) + revokable. Without this, a griefer could
    // call rescueScheduledWithdrawal on a group whose immediate path
    // would have paid the beneficiary, rerouting them to slower-unbond
    // groups.
    //
    // Setup: depositor specific-strategy on g[1] backed by balance
    // (cap saturated, no active votes). Then asManager.scheduleWithdrawals
    // pins a small amount that immediate path could serve. random caller
    // tries rescue. Must revert GroupNotInDeficit.

    await managerContract.connect(depositor).changeStrategy(groups[1].address);
    await managerContract.connect(depositor).deposit({ value: parseUnits("50") });
    await externalVoterSaturatesGroup(groups[1].address);
    await activateAndVoteTest(); // silently skips g[1] - balance still backs toVote

    const balance = await hre.ethers.provider.getBalance(accountContract.address);
    const toVote = await accountContract.scheduledVotesForGroup(groups[1].address);
    expect(balance.gte(toVote)).to.equal(true, "balance must cover toVote");

    // secondDepositor builds active votes on another default group to
    // serve as a viable rescue destination. Without this, a broken
    // rescue would revert at _addBeneficiaryWithdrawal due to no
    // capacity on the destination - obscuring whether the deficit
    // check passed or failed.
    await managerContract.connect(secondDepositor).deposit({ value: parseUnits("100") });
    await activateAndVoteTest();
    let destGroup: string | undefined;
    for (const g of activatedGroupAddresses) {
      if (g === groups[1].address) continue;
      const celoForG = await accountContract.getCeloForGroup(g);
      if (celoForG.gte(parseUnits("10"))) {
        destGroup = g;
        break;
      }
    }
    expect(destGroup).to.not.equal(undefined, "test setup: need viable rescue destination");

    // Pin a small amount that immediate path can deliver.
    const managerSigner = await asManager();
    const pinAmount = parseUnits("10");
    await accountContract
      .connect(managerSigner)
      .scheduleWithdrawals(depositor.address, [groups[1].address], [pinAmount]);

    // Permissionless rescue must revert with GroupNotInDeficit - this
    // beneficiary's claim is covered by immediate path
    // (min(balance, toVote)) even though revokable(g[1]) ≈ 0.
    // Destination has capacity, so a broken rescue would succeed past
    // _addBeneficiaryWithdrawal.
    await expect(
      accountContract
        .connect(randomCaller)
        .rescueScheduledWithdrawal(
          depositor.address,
          groups[1].address,
          [destGroup as string],
          [pinAmount]
        )
    ).revertedWith("GroupNotInDeficit");

    // Pin still intact.
    expect(
      await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(
        groups[1].address,
        depositor.address
      )
    ).to.equal(pinAmount);
  });

  it("REGRESSION P2 #2: rescue must reject when revokable covers user's claim even if group has high toRevoke", async () => {
    // Codex P2 #2: per-beneficiary deficit check must NOT count
    // toRevoke. A transfer-accounting deficit (toRevoke > revokable
    // from queued scheduleTransfer) should not let a griefer rescue
    // individual beneficiaries whose toWithdrawFor is fully revokable.
    // Account.withdraw(beneficiary, group) does not consume toRevoke
    // along the way.
    //
    // Setup: depositor specific-strategy, gets active votes. Inject
    // huge toRevoke via asManager.scheduleTransfer (uses up
    // bookkeeping revokable headroom). Pin a small toWithdrawFor that
    // active alone covers. random caller tries rescue. Must revert.

    // secondDepositor default-deposits enough to spread allocation across
    // other DS groups. Then depositor specific strategy on g[1].
    await managerContract.connect(secondDepositor).deposit({ value: parseUnits("100") });
    await managerContract.connect(depositor).changeStrategy(groups[1].address);
    await managerContract.connect(depositor).deposit({ value: parseUnits("50") });
    await activateAndVoteTest(); // active(g[1]) = 50, others have some active

    const balancePostActivate = await hre.ethers.provider.getBalance(accountContract.address);
    expect(balancePostActivate.eq(0)).to.equal(
      true,
      "test setup: balance must be drained by activate so toRevoke injection works"
    );

    // Pick a transfer destination with active to feed the transfer. We
    // queue toRevoke ON g[1] (source) so g[1]'s books look deficit-prone.
    let destGroup: string | undefined;
    for (const g of activatedGroupAddresses) {
      if (g === groups[1].address) continue;
      const celoForG = await accountContract.getCeloForGroup(g);
      if (celoForG.gt(0)) {
        destGroup = g;
        break;
      }
    }
    expect(destGroup).to.not.equal(undefined, "test setup: need a destination group");

    // ORDER MATTERS. Pin BEFORE injecting toRevoke. scheduleWithdrawals
    // is gated by realisable so it must run while realisable still
    // covers the pin. scheduleTransfer has no such gate so toRevoke can
    // be inflated afterwards.

    // 1. Pin a small toWithdrawFor that the unmodified revokable easily covers.
    const managerSigner = await asManager();
    const pinAmount = parseUnits("5");
    await accountContract
      .connect(managerSigner)
      .scheduleWithdrawals(depositor.address, [groups[1].address], [pinAmount]);

    // 2. Inject toRevoke onto g[1] via scheduleTransfer FROM g[1] TO
    //    destGroup. Query getCeloForGroup(g[1]) for the max transfer
    //    amount the scheduleTransfer source check allows. The resulting
    //    toRevoke + pin > revokable triggers the BROKEN group-wide
    //    deficit check, even though revokable still covers THIS
    //    beneficiary's individual pinAmount.
    const celoAvailable = await accountContract.getCeloForGroup(groups[1].address);
    const bigToRevoke = celoAvailable;
    await accountContract
      .connect(managerSigner)
      .scheduleTransfer([groups[1].address], [bigToRevoke], [destGroup as string], [bigToRevoke]);

    // Permissionless rescue must revert with GroupNotInDeficit -
    // per-beneficiary capacity (revokable + immediate) >= pin, so this
    // beneficiary is NOT in deficit even though group-wide
    // toRevoke + toWithdraw > revokable. Destination is destGroup which
    // HAS capacity, so a broken rescue would succeed past
    // _addBeneficiaryWithdrawal - the only way it reverts is the
    // per-beneficiary deficit check itself.
    await expect(
      accountContract
        .connect(randomCaller)
        .rescueScheduledWithdrawal(
          depositor.address,
          groups[1].address,
          [destGroup as string],
          [pinAmount]
        )
    ).revertedWith("GroupNotInDeficit");

    expect(
      await accountContract.scheduledWithdrawalsForGroupAndBeneficiary(
        groups[1].address,
        depositor.address
      )
    ).to.equal(pinAmount);
  });

  it("REGRESSION P2 #6: scheduleWithdrawals must reject multi-group call summing more balance demand than Account holds", async () => {
    // Codex P2 #6: per-group min(toVote, balance) lets multiple groups
    // each independently claim the full unlocked Account balance. A
    // multi-group scheduleWithdrawals call where the sum of
    // immediate-balance demands exceeds the actual balance could pass
    // validation pre-fix; the bot's Account.withdraw on the second group
    // would then revert InsufficientRevokableVotes after the first drained
    // the shared balance.
    //
    // Setup: g[1] has toVote=30 backed by balance=30 (cap saturated, bot
    // couldn't activate). g[5] has toVote=30 unbacked (via scheduleTransfer
    // from a healthy source). Multi-group call demands 30+30=60 from
    // balance which is only 30.

    // a. SGS deposit on g[1]. Saturate cap BEFORE activate so balance
    //    stays put.
    await managerContract.connect(depositor).changeStrategy(groups[1].address);
    await managerContract.connect(depositor).deposit({ value: parseUnits("30") });
    await externalVoterSaturatesGroup(groups[1].address);
    await activateAndVoteTest(); // silently skips g[1]; balance stays 30

    const balanceAfterFirst = await hre.ethers.provider.getBalance(accountContract.address);
    expect(balanceAfterFirst).to.equal(
      parseUnits("30"),
      "test setup: balance must be 30 (not activated due to cap)"
    );

    // b. Build a source group with active votes via secondDepositor
    //    default deposit. Cannot use g[1] (saturated) as source.
    await managerContract.connect(secondDepositor).deposit({ value: parseUnits("60") });
    await activateAndVoteTest();

    // Source must have getCeloForGroup >= 30 for scheduleTransfer.
    let sourceGroup: string | undefined;
    for (const g of activatedGroupAddresses) {
      if (g === groups[1].address) continue;
      const celoForG = await accountContract.getCeloForGroup(g);
      if (celoForG.gte(parseUnits("30"))) {
        sourceGroup = g;
        break;
      }
    }
    expect(sourceGroup).to.not.equal(
      undefined,
      "test setup: need a source group with 30+ getCeloForGroup"
    );

    // c. asManager.scheduleTransfer injects toVote=30 onto g[5] without
    //    increasing balance. Now g[5].toVote=30 is unbacked.
    const managerSigner = await asManager();
    await accountContract
      .connect(managerSigner)
      .scheduleTransfer(
        [sourceGroup as string],
        [parseUnits("30")],
        [groups[5].address],
        [parseUnits("30")]
      );

    // d. Multi-group scheduleWithdrawals([g[1], g[5]], [30, 30]).
    //    Per-group view: g[1] realisable=30 (balance-backed toVote),
    //    g[5] realisable=30 (balance-backed via same global balance).
    //    Sum demand 60 > actual balance ~ 30 (modulo secondDepositor
    //    activated portion). Pre-fix: passes both. Post-fix: shared
    //    balance budget exhausted on iter 1 -> revert.
    await expect(
      accountContract
        .connect(managerSigner)
        .scheduleWithdrawals(
          depositor.address,
          [groups[1].address, groups[5].address],
          [parseUnits("30"), parseUnits("30")]
        )
    ).reverted;
  });

  it("REGRESSION P2 #9: scheduleWithdrawals must reserve balance for a group even when revokable alone would cover the withdrawal", async () => {
    // Codex P2 #9: Account.withdraw line ~424 ALWAYS charges
    // min(balance, toVote, amount) immediately before falling back to
    // revoke. A previous fix that only charged the shared budget for the
    // post-revoke remainder underestimated balance consumption: a group
    // with both enough revokable votes AND positive toVote actually
    // drains balance first at withdraw time, so a second group relying
    // on that same balance was left unfulfillable.
    //
    // Setup: g[1] specific-strategy with both balance-backed toVote AND
    // revokable Election votes; g[5] has unbacked toVote (via
    // scheduleTransfer). Multi-group call sized so revokable on g[1]
    // could cover g[1]'s withdrawal entirely, yet Account.withdraw will
    // still charge balance and starve g[5].

    // a. SGS deposit on g[1] WITH activate (gets revokable=30).
    await managerContract.connect(depositor).changeStrategy(groups[1].address);
    await managerContract.connect(depositor).deposit({ value: parseUnits("30") });
    await activateAndVoteTest(); // active(g[1]) ≈ 30, balance drained

    // b. secondDepositor default deposit to build a source group with
    //    active votes for the scheduleTransfer below.
    await managerContract.connect(secondDepositor).deposit({ value: parseUnits("60") });
    await activateAndVoteTest();

    let sourceGroup: string | undefined;
    for (const g of activatedGroupAddresses) {
      if (g === groups[1].address) continue;
      const celoForG = await accountContract.getCeloForGroup(g);
      if (celoForG.gte(parseUnits("20"))) {
        sourceGroup = g;
        break;
      }
    }
    expect(sourceGroup).to.not.equal(undefined);

    // c. asManager directly injects balance-backed toVote=20 on g[1] via
    //    scheduleVotes (msg.value=20). Now g[1]: active=30, toVote=20,
    //    balance contribution=20.
    const managerSigner = await asManager();
    await accountContract
      .connect(managerSigner)
      .scheduleVotes([groups[1].address], [parseUnits("20")], { value: parseUnits("20") });

    const balanceMid = await hre.ethers.provider.getBalance(accountContract.address);
    expect(balanceMid).to.equal(
      parseUnits("20"),
      "test setup: balance must be 20 (un-activated scheduleVotes injection)"
    );

    // d. asManager.scheduleTransfer injects toVote=20 onto g[5] without
    //    increasing balance. g[5].toVote=20 needs the shared balance to
    //    be paid via immediate path.
    await accountContract
      .connect(managerSigner)
      .scheduleTransfer(
        [sourceGroup as string],
        [parseUnits("20")],
        [groups[5].address],
        [parseUnits("20")]
      );

    // d. Multi-group call: [g[1], g[5]], [25, 20]. g[1]'s 25 fits in
    //    revokable=30 BUT g[1] has toVote=20 + balance=20 so
    //    Account.withdraw will charge min(20, 20, 25) = 20 from balance
    //    first. After g[1]: balance=0. g[5] then can't deliver 20 via
    //    immediate (balance=0) and has revokable=0 -> stuck pin.
    // Pre-this-fix: per-group passes (g[1] revokable covers 25, g[5]
    // balance-backed toVote covers 20). Post-fix: shared budget tracks
    // that g[1] consumed 20 of balance, leaving 0 for g[5] -> revert.
    await expect(
      accountContract
        .connect(managerSigner)
        .scheduleWithdrawals(
          depositor.address,
          [groups[1].address, groups[5].address],
          [parseUnits("25"), parseUnits("20")]
        )
    ).reverted;
  });

  // Silence unused-import lint on contracts referenced only for typing.
  it("smoke - contracts deployed", () => {
    expect(specificGroupStrategyContract.address).to.not.equal("");
  });
});
