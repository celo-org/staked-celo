// Regression tests for the "stuck-withdrawal" root cause:
//
// Previously `Account.scheduleWithdrawals` validated capacity via
// `getCeloForGroup`, which includes `scheduledVotes.toVote` even when that
// CELO can never be voted (Election cap exhausted by external voters). A
// withdrawal scheduled against such stale `toVote` could not be revoked, so
// `Account.withdraw` reverted with `InsufficientRevokableVotes`, pinning the
// user's CELO to an unfulfillable group.
//
// Fix introduces `getRealisableCeloForGroup` (Election active + activatable
// `toVote` net of earmarked) and switches all withdrawal-capacity checks to
// it. These tests prove the bug class is dead.

import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { default as BigNumberJs } from "bignumber.js";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { MockRegistry__factory } from "../typechain-types/factories/MockRegistry__factory";
import {
  ADDRESS_ZERO,
  mineToNextEpoch,
  randomSigner,
  REGISTRY_ADDRESS,
  resetNetwork,
} from "./utils";
import { registerValidatorAndAddToGroupMembers, registerValidatorGroup } from "./utils-validators";

after(() => {
  hre.kit.stop();
});

describe("Account - realisable capacity & rescue", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let snapshotId: any;

  let election: ElectionWrapper;

  let account: Account;

  let owner: SignerWithAddress;
  let manager: SignerWithAddress;
  let beneficiary: SignerWithAddress;
  let nonOwner: SignerWithAddress;
  let groups: SignerWithAddress[];
  let groupAddresses: string[];

  before(async () => {
    await resetNetwork();

    [manager] = await randomSigner(parseUnits("11000000"));
    [beneficiary] = await randomSigner(parseUnits("100"));
    [nonOwner] = await randomSigner(parseUnits("100"));

    // Attach to MockRegistry so subsequent contractkit calls resolve against
    // the test network registry. Reference itself isn't used directly.
    const registryFactory: MockRegistry__factory = (
      await hre.ethers.getContractFactory("MockRegistry")
    ).connect(manager) as MockRegistry__factory;
    registryFactory.attach(REGISTRY_ADDRESS);

    groups = [];
    groupAddresses = [];
    for (let i = 0; i < 3; i++) {
      const [group] = await randomSigner(parseUnits("11000"));
      groups.push(group);
      groupAddresses.push(group.address);
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      await registerValidatorGroup(group);
      await registerValidatorAndAddToGroupMembers(group, validator, validatorWallet);
    }

    await hre.deployments.fixture("TestAccount");
    owner = await hre.ethers.getNamedSigner("owner");
    account = await hre.ethers.getContract("Account");
    await account.connect(owner).setManager(manager.address);
    await account.connect(owner).setPauser();

    election = await hre.kit.contracts.getElection();
  });

  beforeEach(async () => {
    snapshotId = await hre.ethers.provider.send("evm_snapshot", []);
  });

  afterEach(async () => {
    await hre.ethers.provider.send("evm_revert", [snapshotId]);
  });

  /**
   * Compute proper Election sorted-list hints for activating a vote on
   * `group` from `account`, then call `Account.activateAndVote`.
   */
  async function activateOnGroup(group: string, amount: string): Promise<void> {
    const { lesser, greater } = await election.findLesserAndGreaterAfterVote(
      group,
      new BigNumberJs(amount)
    );
    await account.connect(manager).activateAndVote(group, lesser, greater);
  }

  /**
   * Build active votes on `group`: deposit `amount`, activate (this epoch),
   * mine to next epoch, activate again so pending becomes active.
   */
  async function activateGroupWithAmount(group: string, amount: string): Promise<void> {
    await account
      .connect(manager)
      .scheduleVotes([group], [parseUnits(amount)], { value: parseUnits(amount) });
    await activateOnGroup(group, parseUnits(amount).toString());
    await mineToNextEpoch(hre.web3);
    await activateOnGroup(group, "0");
  }

  describe("#getRealisableCeloForGroup() - root cause", () => {
    it("includes scheduledToVote when Election cap has headroom (matches getCeloForGroup)", async () => {
      await account
        .connect(manager)
        .scheduleVotes([groupAddresses[0]], [parseUnits("100")], { value: parseUnits("100") });
      // Don't activate. toVote = 100, active = 0, headroom > 0.

      // Realisable should include the activatable toVote since Election can
      // accept it; the activate-and-vote bot will convert to active votes.
      expect(await account.getRealisableCeloForGroup(groupAddresses[0])).to.equal(
        parseUnits("100")
      );
      expect(await account.getCeloForGroup(groupAddresses[0])).to.equal(parseUnits("100"));
    });

    it("subtracts earmarked toRevoke and toWithdraw", async () => {
      await activateGroupWithAmount(groupAddresses[0], "100");

      // Earmark 30 as a scheduled withdrawal.
      await account
        .connect(manager)
        .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [parseUnits("30")]);

      // Realisable drops by the earmarked 30.
      expect(await account.getRealisableCeloForGroup(groupAddresses[0])).to.equal(parseUnits("70"));
    });

    it("returns zero when all capacity is earmarked", async () => {
      await activateGroupWithAmount(groupAddresses[0], "100");
      await account
        .connect(manager)
        .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [parseUnits("100")]);
      expect(await account.getRealisableCeloForGroup(groupAddresses[0])).to.equal(0);
    });

    it("excludes unbacked scheduledToVote when Account.balance does not back it (root cause)", async () => {
      // ROOT CAUSE PROOF.
      //
      // Production scenario (mainnet 0x81AE): `scheduledVotes[group].toVote`
      // exists but `Account.balance` cannot back it - either the bot's
      // activateAndVote silently failed (Election cap exhausted) and
      // matching balance was consumed by other groups' activates over
      // time, or an in-flight `scheduleTransfer(A -> B)` queued `toVote[B]`
      // before the matching `toRevoke[A]` was physically revoked
      // (CELO still locked under A).
      //
      // Either way, `Account.withdraw`'s immediate path serves only
      // `min(balance, toVote)`, and the remainder needs `revokable`.
      // Pre-fix `scheduleWithdrawals` validated against
      // `getCeloForGroup = active + toVote` and let withdrawals through
      // that the bot could never deliver, pinning users.
      //
      // Reproduce deterministically via `scheduleTransfer`: it adds
      // `toVote[B]` without touching `Account.balance`. With balance = 0
      // and revokable(B) = 0, `getRealisableCeloForGroup(B)` must be 0.
      await activateGroupWithAmount(groupAddresses[0], "100");

      const startingBalance = await hre.ethers.provider.getBalance(account.address);
      expect(startingBalance).to.equal(0, "test setup: balance must be zero pre-transfer");

      // Transfer 50 toVote from group[0] to group[1]. group[0]'s active is
      // earmarked as toRevoke, group[1] gets toVote without any new balance.
      await account
        .connect(manager)
        .scheduleTransfer(
          [groupAddresses[0]],
          [parseUnits("50")],
          [groupAddresses[1]],
          [parseUnits("50")]
        );

      // group[1] now has toVote = 50 but no Account.balance, no revokable.
      expect(await account.scheduledVotesForGroup(groupAddresses[1])).to.equal(parseUnits("50"));
      expect(
        await election.getTotalVotesForGroupByAccount(groupAddresses[1], account.address)
      ).to.equal(0);
      expect(await hre.ethers.provider.getBalance(account.address)).to.equal(0);

      // Inflated (legacy getCeloForGroup) counts toVote -> 50.
      const inflated = await account.getCeloForGroup(groupAddresses[1]);
      expect(inflated).to.equal(parseUnits("50"));

      // Realisable excludes unbacked toVote (balance cap = 0) -> 0.
      const realisable = await account.getRealisableCeloForGroup(groupAddresses[1]);
      expect(realisable).to.equal(0);

      // scheduleWithdrawals against the unbacked promise must revert at
      // boundary - exactly what stops the stuck pin.
      await expect(
        account
          .connect(manager)
          .scheduleWithdrawals(beneficiary.address, [groupAddresses[1]], [parseUnits("50")])
      ).revertedWith(`WithdrawalAmountTooHigh("${groupAddresses[1]}", 0, ${parseUnits("50")})`);
    });
  });

  describe("#scheduleWithdrawals() - prevention of stuck pin", () => {
    it("reverts when scheduled amount exceeds realisable", async () => {
      // Setup: 100 CELO active votes on group[0]. realisable == 100.
      await activateGroupWithAmount(groupAddresses[0], "100");
      // Scheduling 101 CELO exceeds realisable -> revert at the boundary
      // BEFORE stCelo is burned, so user never gets stuck.
      await expect(
        account
          .connect(manager)
          .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [parseUnits("101")])
      ).revertedWith(
        `WithdrawalAmountTooHigh("${groupAddresses[0]}", ${parseUnits("100")}, ${parseUnits(
          "101"
        )})`
      );
    });

    it("subtracts an existing toWithdraw ONCE from combined capacity, not per bucket", async () => {
      // Regression for the double-subtraction bug (review by Mc01).
      //
      // A group with BOTH buckets non-empty: 100 active votes (revoke bucket)
      // plus 50 balance-backed toVote (immediate bucket). Combined physical
      // capacity C = revokable(100) + min(balance 50, toVote 50) = 150.
      await activateGroupWithAmount(groupAddresses[0], "100"); // active=100, toVote=0, balance=0
      await account
        .connect(manager)
        .scheduleVotes([groupAddresses[0]], [parseUnits("50")], { value: parseUnits("50") });
      // toVote=50 backed by balance=50, revokable=100, toRevoke=0.

      // Pin an existing withdrawal W = 50 on the group.
      await account
        .connect(manager)
        .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [parseUnits("50")]);

      // Account.withdraw is immediate-first, so W consumes the COMBINED
      // capacity once. Realisable for a new pin = C - W = 150 - 50 = 100.
      // The buggy double-subtraction reported 50 (revokable-W=50 plus
      // immediate min(balance, toVote-W)=0), wrongly hiding 50 of real
      // capacity.
      expect(await account.getRealisableCeloForGroup(groupAddresses[0])).to.equal(
        parseUnits("100")
      );

      // A second withdrawal of exactly C - W = 100 must schedule. Pre-fix this
      // reverted WithdrawalAmountTooHigh(group, 50, 100) - a serviceable
      // withdrawal wrongly rejected.
      await account
        .connect(manager)
        .scheduleWithdrawals(nonOwner.address, [groupAddresses[0]], [parseUnits("100")]);

      // Now the whole capacity (150) is earmarked; one wei more reverts.
      await expect(
        account.connect(manager).scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [1])
      ).revertedWith(`WithdrawalAmountTooHigh("${groupAddresses[0]}", 0, 1)`);
    });

    it("guarantees Account.withdraw fulfills any successfully scheduled amount", async () => {
      // After scheduling passes, the bot's Account.withdraw must succeed via
      // immediate + revoke path. Invariant: scheduled <= realisable =>
      // revokable + activatable >= scheduled.
      await activateGroupWithAmount(groupAddresses[0], "100");
      await account
        .connect(manager)
        .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [parseUnits("100")]);

      const votedGroups = await election.getGroupsVotedForByAccount(account.address);
      const voterIndex = votedGroups.findIndex(
        (g) => g.toLowerCase() === groupAddresses[0].toLowerCase()
      );
      const { lesser, greater } = await election.findLesserAndGreaterAfterVote(
        groupAddresses[0],
        new BigNumberJs(parseUnits("-100").toString())
      );
      await account.withdraw(
        beneficiary.address,
        groupAddresses[0],
        ADDRESS_ZERO,
        ADDRESS_ZERO,
        lesser,
        greater,
        voterIndex
      );

      // Scheduled withdrawal cleared, no stuck state.
      expect(
        await account.scheduledWithdrawalsForGroupAndBeneficiary(
          groupAddresses[0],
          beneficiary.address
        )
      ).to.equal(0);
    });
  });

  describe("#rescueScheduledWithdrawal() - permissionless deficit rescue", () => {
    async function setupScheduledWithdrawal(amount: string): Promise<void> {
      await activateGroupWithAmount(groupAddresses[0], amount);
      await account
        .connect(manager)
        .scheduleWithdrawals(beneficiary.address, [groupAddresses[0]], [parseUnits(amount)]);
    }

    it("reverts GroupNotInDeficit when fromGroup can still fulfill THIS beneficiary's pin", async () => {
      // Schedule a per-beneficiary pin where Account.withdraw could
      // physically deliver it (revokable + immediate >= userClaim).
      // Permissionless rescue must reject so a griefer cannot reroute a
      // payable withdrawal to slower-unbond groups.
      await setupScheduledWithdrawal("100");
      await activateGroupWithAmount(groupAddresses[1], "200");
      // capacity(group[0]) = revokable(100) + immediate(0) = 100.
      // userClaim = 100. capacity >= userClaim -> NOT in deficit.
      await expect(
        account
          .connect(nonOwner)
          .rescueScheduledWithdrawal(
            beneficiary.address,
            groupAddresses[0],
            [groupAddresses[1]],
            [parseUnits("100")]
          )
      ).revertedWith(
        `GroupNotInDeficit("${beneficiary.address}", "${groupAddresses[0]}", ${parseUnits(
          "100"
        )}, ${parseUnits("100")})`
      );
    });

    it("reverts NoScheduledWithdrawal when beneficiary has no pin on fromGroup", async () => {
      // No prior schedule on groupAddresses[0] for beneficiary -> revert
      // happens BEFORE the deficit check (cheap input validation).
      await expect(
        account
          .connect(nonOwner)
          .rescueScheduledWithdrawal(
            beneficiary.address,
            groupAddresses[0],
            [groupAddresses[1]],
            [parseUnits("100")]
          )
      ).revertedWith(`NoScheduledWithdrawal("${beneficiary.address}", "${groupAddresses[0]}")`);
    });

    it("reverts on toGroups/amounts length mismatch", async () => {
      await setupScheduledWithdrawal("100");
      await expect(
        account
          .connect(nonOwner)
          .rescueScheduledWithdrawal(
            beneficiary.address,
            groupAddresses[0],
            [groupAddresses[1], groupAddresses[2]],
            [parseUnits("100")]
          )
      ).revertedWith("GroupsAndVotesArrayLengthsMismatch()");
    });
  });
});
