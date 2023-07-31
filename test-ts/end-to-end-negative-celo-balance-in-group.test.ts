import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { ACCOUNT_REVOKE } from "../lib/tasksNames";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import {
  activateAndVoteTest,
  activateValidators,
  ADDRESS_ZERO,
  distributeEpochRewards,
  electMockValidatorGroupsAndUpdate,
  getGroupsOfAllStrategies,
  getRealVsExpectedCeloForGroups,
  mineToNextEpoch,
  randomSigner,
  rebalanceDefaultGroups,
  rebalanceGroups,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
  resetNetwork,
  upgradeToMockGroupHealthE2E,
} from "./utils";

after(() => {
  hre.kit.stop();
});

describe("e2e change strategy from specific when specific doesn't have enough of celo", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let groupHealthContract: MockGroupHealth;
  let validatorsWrapper: ValidatorsWrapper;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategy: DefaultStrategy;

  const deployerAccountName = "deployer";
  let depositor0: SignerWithAddress;
  let depositor1: SignerWithAddress;
  // only deposits to strategy that is different from active groups
  let voter: SignerWithAddress;

  let groups: SignerWithAddress[];
  let activatedGroupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let multisigOwner0: SignerWithAddress;

  const rewardsGroup0 = hre.ethers.BigNumber.from(parseUnits("10"));
  const rewardsGroup1 = hre.ethers.BigNumber.from(parseUnits("20"));
  const rewardsGroup2 = hre.ethers.BigNumber.from(parseUnits("30"));
  const rewardsGroup5 = hre.ethers.BigNumber.from(parseUnits("10"));

  let specificGroupStrategyDifferentFromActive: SignerWithAddress;
  let specificGroupThatWillBeUnhealthy: SignerWithAddress;

  // eslint-disable-next-line no-unused-vars, @typescript-eslint/no-explicit-any
  before(async function (this: any) {
    this.timeout(0); // Disable test timeout
    await resetNetwork();

    process.env = {
      ...process.env,
      TIME_LOCK_MIN_DELAY: "1",
      TIME_LOCK_DELAY: "1",
      MULTISIG_REQUIRED_CONFIRMATIONS: "1",
      VALIDATOR_GROUPS: "",
    };

    [depositor0] = await randomSigner(parseUnits("300"));
    [depositor1] = await randomSigner(parseUnits("300"));
    [voter] = await randomSigner(parseUnits("300"));
    const accounts = await hre.kit.contracts.getAccounts();
    await accounts.createAccount().sendAndWaitForReceipt({
      from: voter.address,
    });
    groups = [];
    activatedGroupAddresses = [];
    validators = [];
    validatorAddresses = [];
    for (let i = 0; i < 10; i++) {
      const [group] = await randomSigner(parseUnits("11000"));
      groups.push(group);
      if (i < 3) {
        activatedGroupAddresses.push(groups[i].address);
      }
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      validators.push(validator);
      validatorAddresses.push(validators[i].address);

      await registerValidatorGroup(groups[i]);
      await registerValidatorAndAddToGroupMembers(groups[i], validators[i], validatorWallet);
    }
    specificGroupStrategyDifferentFromActive = groups[5];
    specificGroupThatWillBeUnhealthy = groups[7];
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    groupHealthContract = await hre.ethers.getContract("GroupHealth");
    specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");
    defaultStrategy = await hre.ethers.getContract("DefaultStrategy");
    validatorsWrapper = await hre.kit.contracts.getValidators();

    multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");

    groupHealthContract = await upgradeToMockGroupHealthE2E(
      multisigOwner0,
      groupHealthContract as unknown as GroupHealth
    );
    await electMockValidatorGroupsAndUpdate(validatorsWrapper, groupHealthContract, [
      ...activatedGroupAddresses,
      specificGroupStrategyDifferentFromActive.address,
      specificGroupThatWillBeUnhealthy.address,
    ]);

    await activateValidators(
      defaultStrategy,
      groupHealthContract as unknown as GroupHealth,
      multisigOwner0.address,
      activatedGroupAddresses
    );
  });

  it("deposit, rebalance, transfer and withdraw", async () => {
    const amountOfCeloToDeposit = hre.ethers.BigNumber.from(parseUnits("1"));

    await managerContract
      .connect(depositor0)
      .changeStrategy(specificGroupStrategyDifferentFromActive.address);

    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    await managerContract.connect(depositor0).deposit({ value: amountOfCeloToDeposit });
    await managerContract.connect(depositor1).deposit({ value: amountOfCeloToDeposit });

    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    await activateAndVoteTest();
    await mineToNextEpoch(hre.web3);
    await activateAndVoteTest();

    await distributeAllRewards();

    await managerContract.connect(depositor0).changeStrategy(ADDRESS_ZERO);

    expect(
      await accountContract.getCeloForGroup(specificGroupStrategyDifferentFromActive.address)
    ).to.deep.eq(0);
    expect(
      await accountContract.votesForGroup(specificGroupStrategyDifferentFromActive.address)
    ).to.deep.eq(amountOfCeloToDeposit.add(rewardsGroup5));
    expect(
      await accountContract.scheduledRevokeForGroup(
        specificGroupStrategyDifferentFromActive.address
      )
    ).to.deep.eq((await accountContract.getTotalCelo()).div(2));

    const expectedActual = await managerContract.getExpectedAndActualCeloForGroup(
      specificGroupStrategyDifferentFromActive.address
    );

    const votes = await accountContract.votesForGroup(
      specificGroupStrategyDifferentFromActive.address
    );
    const revoke = await accountContract.scheduledRevokeForGroup(
      specificGroupStrategyDifferentFromActive.address
    );

    expect(expectedActual.expectedCelo.sub(expectedActual.actualCelo)).to.deep.eq(
      revoke.sub(votes)
    );

    await revokeGroup(specificGroupStrategyDifferentFromActive.address);

    const votesAfterSpecificGroupRevoke = await accountContract.votesForGroup(
      specificGroupStrategyDifferentFromActive.address
    );
    const revokeAfterSpecificGroupRevoke = await accountContract.scheduledRevokeForGroup(
      specificGroupStrategyDifferentFromActive.address
    );

    expect(votesAfterSpecificGroupRevoke).to.deep.eq(hre.ethers.BigNumber.from(0));
    expect(revokeAfterSpecificGroupRevoke).to.deep.eq(revoke.sub(votes));

    await rebalanceAllAndActivate();

    const votesAfterRebalance = await accountContract.votesForGroup(
      specificGroupStrategyDifferentFromActive.address
    );
    const revokeAfterRebalance = await accountContract.scheduledRevokeForGroup(
      specificGroupStrategyDifferentFromActive.address
    );

    expect(votesAfterRebalance).to.deep.eq(hre.ethers.BigNumber.from(0));
    expect(revokeAfterRebalance).to.deep.eq(hre.ethers.BigNumber.from(0));

    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);
  });

  async function rebalanceAllAndActivate() {
    await rebalanceDefaultGroups(defaultStrategy);
    await rebalanceGroups(managerContract, specificGroupStrategyContract, defaultStrategy);
    await hre.run(ACCOUNT_REVOKE, {
      account: deployerAccountName,
      useNodeAccount: true,
      logLevel: "info",
    });
    await activateAndVoteTest();
  }

  async function distributeAllRewards() {
    await distributeEpochRewards(groups[0].address, rewardsGroup0.toString());
    await distributeEpochRewards(groups[1].address, rewardsGroup1.toString());
    await distributeEpochRewards(groups[2].address, rewardsGroup2.toString());
    await distributeEpochRewards(groups[5].address, rewardsGroup5.toString());
  }

  async function expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy: DefaultStrategy) {
    const allGroups = await getGroupsOfAllStrategies(
      defaultStrategy,
      specificGroupStrategyContract
    );
    const expectedVsReal = await getRealVsExpectedCeloForGroups(managerContract, allGroups);
    const expectedSum = hre.ethers.BigNumber.from(0);
    const realSum = hre.ethers.BigNumber.from(0);
    for (const group of expectedVsReal) {
      expectedSum.add(group.expected);
      realSum.add(group.real);
    }
    expect(expectedSum).to.deep.eq(realSum);
  }

  async function revokeGroup(group: string) {
    const electionWrapper = await hre.kit.contracts.getElection();
    const scheduledToRevokeAmount = await accountContract.scheduledRevokeForGroup(group);

    if (scheduledToRevokeAmount.gt(0)) {
      let remainingToRevokeAmount = hre.ethers.BigNumber.from(0);
      let toRevokeFromPending = hre.ethers.BigNumber.from(0);

      let lesserAfterPendingRevoke: string = ADDRESS_ZERO;
      let greaterAfterPendingRevoke: string = ADDRESS_ZERO;
      let lesserAfterActiveRevoke: string = ADDRESS_ZERO;
      let greaterAfterActiveRevoke: string = ADDRESS_ZERO;

      // substract the immediateWithdrawalAmount from scheduledToRevokeAmount to get the revokable amount
      const immediateWithdrawalAmount = await accountContract.scheduledVotesForGroup(group);
      if (immediateWithdrawalAmount.lt(scheduledToRevokeAmount)) {
        remainingToRevokeAmount = scheduledToRevokeAmount.sub(immediateWithdrawalAmount);

        // get AccountContract pending votes for group.
        const groupVote = await electionWrapper.getVotesForGroupByAccount(
          accountContract.address,
          group
        );
        const pendingVotes = groupVote.pending;

        // amount to revoke from pending
        toRevokeFromPending = hre.ethers.BigNumber.from(
          remainingToRevokeAmount.lt(hre.ethers.BigNumber.from(pendingVotes.toString())) // Math.min
            ? remainingToRevokeAmount.toString()
            : pendingVotes.toString()
        );

        // find lesser and greater for pending votes
        const lesserAndGreaterAfterPendingRevoke =
          await electionWrapper.findLesserAndGreaterAfterVote(
            group,
            // @ts-ignore:  hre.ethers.BigNumber types library conflict.
            toRevokeFromPending.mul(-1).toString()
          );
        lesserAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.lesser;
        greaterAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.greater;

        // Given that validators are sorted by total votes and that revoking pending votes happen before active votes.
        // One must account for any pending votes that would get removed from the total votes when revoking active votes
        // in the same transaction.

        // find lesser and greater for active votes
        const lesserAndGreaterAfterActiveRevoke =
          await electionWrapper.findLesserAndGreaterAfterVote(
            group,
            // @ts-ignore:  hre.ethers.BigNumber types library conflict.
            remainingToRevokeAmount.mul(-1).toString()
          );
        lesserAfterActiveRevoke = lesserAndGreaterAfterActiveRevoke.lesser;
        greaterAfterActiveRevoke = lesserAndGreaterAfterActiveRevoke.greater;
      }

      // find index of group
      const index = await findAddressIndex(electionWrapper, group, accountContract.address);

      // use current index
      const tx = await accountContract.revokeVotes(
        group,
        lesserAfterPendingRevoke,
        greaterAfterPendingRevoke,
        lesserAfterActiveRevoke,
        greaterAfterActiveRevoke,
        index
      );

      await tx.wait();
    }
  }

  async function findAddressIndex(
    electionWrapper: ElectionWrapper,
    group: string,
    account: string
  ): Promise<number> {
    const list = await electionWrapper.getGroupsVotedForByAccount(account);
    return list.indexOf(group);
  }
});
