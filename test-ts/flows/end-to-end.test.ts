import hre, { ethers } from "hardhat";
import { Account } from "../../typechain-types/Account";
import { Account__factory } from "../../typechain-types/factories/Account__factory";
import { AccountsWrapper } from "@celo/contractkit/lib/wrappers/Accounts";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  ADDRESS_ZERO,
  LOCKED_GOLD_UNLOCKING_PERIOD,
  mineToNextEpoch,
  randomSigner,
  registerValidator,
  registerValidatorGroup,
  REGISTRY_ADDRESS,
  resetNetwork,
  timeTravel,
} from "../utils";
import { Manager } from "../../typechain-types/Manager";
import { MockStakedCelo } from "../../typechain-types/MockStakedCelo";
import { MockStakedCelo__factory } from "../../typechain-types/factories/MockStakedCelo__factory";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

after(() => {
  hre.kit.stop();
});

describe("e2e", () => {
  let accountsInstance: AccountsWrapper;
  let lockedGold: LockedGoldWrapper;
  let election: ElectionWrapper;

  let account: Account;
  let managerContract: Manager;

  let depositor: SignerWithAddress;
  let owner: SignerWithAddress;
  let nonManager: SignerWithAddress;
  let beneficiary: SignerWithAddress;
  let otherBeneficiary: SignerWithAddress;
  let nonBeneficiary: SignerWithAddress;

  let groups: SignerWithAddress[];
  let groupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let stakedCelo: MockStakedCelo;

  before(async () => {
    await resetNetwork();

    [depositor] = await randomSigner(parseUnits("300"));
    [nonManager] = await randomSigner(parseUnits("100"));
    [beneficiary] = await randomSigner(parseUnits("100"));
    [otherBeneficiary] = await randomSigner(parseUnits("100"));
    [nonBeneficiary] = await randomSigner(parseUnits("100"));
    [owner] = await randomSigner(parseUnits("100"));

    groups = [];
    groupAddresses = [];
    validators = [];
    validatorAddresses = [];
    for (let i = 0; i < 3; i++) {
      const [group] = await randomSigner(parseUnits("11000"));
      groups.push(group);
      groupAddresses.push(groups[i].address);
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      validators.push(validator);
      validatorAddresses.push(validators[i].address);

      await registerValidatorGroup(groups[i]);
      await registerValidator(groups[i], validators[i], validatorWallet);
    }

    accountsInstance = await hre.kit.contracts.getAccounts();
    lockedGold = await hre.kit.contracts.getLockedGold();
    election = await hre.kit.contracts.getElection();

    const stakedCeloFactory: MockStakedCelo__factory = (
      await hre.ethers.getContractFactory("MockStakedCelo")
    ).connect(owner) as MockStakedCelo__factory;
    stakedCelo = await stakedCeloFactory.deploy();
  });

  beforeEach(async () => {
    const testAccountDeployment = await hre.deployments.fixture("TestAccount");
    const owner = await hre.ethers.getNamedSigner("owner");
    account = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    managerContract = managerContract.attach(await account.manager());
    await account.connect(owner).setManager(managerContract.address);
  });

  it("deposit and withdraw", async () => {
    const depositorInitialBalance = await depositor.getBalance();
    console.log("depositorInitialBalance", depositorInitialBalance.toString());

    managerContract.setDependencies(stakedCelo.address, account.address);

    for (let i = 0; i < 3; i++) {
      await managerContract.activateGroup(groupAddresses[i]);
    }
    await managerContract.connect(depositor).deposit({ value: 100 });
    let stCelo = await stakedCelo.balanceOf(depositor.address);
    expect(stCelo).to.eq(100);

    const depositorAfterDepositBalance = await depositor.getBalance();
    console.log("depositorAfterDepositBalance", depositorAfterDepositBalance.toString());

    const groupList = await managerContract.getGroups();
    console.log(`Groups: ${groupList}`);

    for (var group of groupList) {
      // Using election contract to make this `hasActivatablePendingVotes` call.
      // This allows to check activatable pending votes for a specified group,
      // as opposed to using the `ElectionWrapper.hasActivatablePendingVotes`
      // which checks if account has activatable pending votes from any group.
      const canActivateForGroup = await (election as any).hasActivatablePendingVotes(
        account.address,
        group
      );

      const amountScheduled = await account.scheduledVotesForGroup(group);
      console.log(`Current group: ${group}`);
      console.log(`Can activate for group: ${canActivateForGroup}`);
      console.log(`Amount scheduled for group: ${amountScheduled.toString()}`);

      if (amountScheduled.toNumber() > 0 || canActivateForGroup) {
        const { lesser, greater } = await (election as any).findLesserAndGreaterAfterVote(
          group,
          amountScheduled.toString()
        );

        const txObject = await account.activateAndVote(group, lesser, greater);
        const receipt = await txObject.wait();
        console.log(`Activate And Vote for ${group}, receipt status: ${receipt.status}`);
        const celoForGroup = await account.getCeloForGroup(group);
        console.log("celoForGroup", celoForGroup.toString());
      }
    }

    const withdrawStakedCelo = await managerContract.connect(depositor).withdraw(100);
    await withdrawStakedCelo.wait();

    stCelo = await stakedCelo.balanceOf(depositor.address);
    expect(stCelo).to.eq(0);

    // Withdraw backend

    for (var group of groupList) {
      // check what the beneficiary withdrawal amount is for each group.
      const scheduledWithdrawalAmount = ethers.BigNumber.from(
        await account.scheduledWithdrawalsForGroupAndBeneficiary(group, depositor.address)
      );

      if (scheduledWithdrawalAmount.gt(0)) {
        let remainingRevokeAmount = ethers.BigNumber.from("0");
        let toRevokeFromPending = ethers.BigNumber.from("0");
        let lesserAfterPendingRevoke: string = ZERO_ADDRESS;
        let greaterAfterPendingRevoke: string = ZERO_ADDRESS;
        let lesserAfterActiveRevoke: string = ZERO_ADDRESS;
        let greaterAfterActiveRevoke: string = ZERO_ADDRESS;

        console.log(`scheduledWithdrawalAmount: ${scheduledWithdrawalAmount}`);

        const immediateWithdrawalAmount = ethers.BigNumber.from(
          await account.scheduledVotesForGroup(group)
        );
        console.log(`immediateWithdrawalAmount: ${immediateWithdrawalAmount}`);

        if (immediateWithdrawalAmount.lt(scheduledWithdrawalAmount)) {
          remainingRevokeAmount = scheduledWithdrawalAmount.sub(immediateWithdrawalAmount);

          console.log(`remainingRevokeAmount: ${remainingRevokeAmount}`);

          // get AccountContract pending votes for group.
          const groupVote = await election.getVotesForGroupByAccount(account.address, group);
          const pendingVotes = ethers.BigNumber.from(groupVote.pending.toString());

          console.log(`pendingVotes: ${pendingVotes}`);

          // amount to revoke from pending
          toRevokeFromPending = remainingRevokeAmount.lt(pendingVotes)
            ? remainingRevokeAmount
            : pendingVotes;

          console.log(`toRevokeFromPending: ${toRevokeFromPending}`);

          // find lesser and greater for pending votes
          const lesserAndGreaterAfterPendingRevoke = await (
            election as any
          ).findLesserAndGreaterAfterVote(group, toRevokeFromPending.mul(-1).toString());
          lesserAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.lesser;
          greaterAfterPendingRevoke = lesserAndGreaterAfterPendingRevoke.greater;

          console.log(`toRevokeFromActive: ${remainingRevokeAmount.sub(toRevokeFromPending)}`);

          // find lesser and greater for active votes
          // Given that validators are sorted by total votes and that revoking pending votes happen before active votes.
          // One must acccount for any pending votes that would get removed from the total votes when also revoking active votes
          // in the same transaction.
          const lesserAndGreaterAfterActiveRevoke = await (
            election as any
          ).findLesserAndGreaterAfterVote(group, remainingRevokeAmount.mul(-1).toString());
          lesserAfterActiveRevoke = lesserAndGreaterAfterActiveRevoke.lesser;
          greaterAfterActiveRevoke = lesserAndGreaterAfterActiveRevoke.greater;
        }
        // find index of group
        const index = await findGroupIndex(election, group, account.address);

        console.log(`Finalizing`);
        console.log(`BeneficiaryAddress: ${depositor.address}`);
        console.log(`Group: ${group}`);
        console.log(`LesserAfterPendingRevoke: ${lesserAfterPendingRevoke}`);
        console.log(`GreaterAfterPendingRevoke: ${greaterAfterPendingRevoke}`);
        console.log(`LesserAfterActiveRevoke: ${lesserAfterActiveRevoke}`);
        console.log(`GreaterAfterActiveRevoke: ${greaterAfterActiveRevoke}`);
        console.log(`Index: ${index}`);

        const txObject = await account.withdraw(
          depositor.address,
          group,
          lesserAfterPendingRevoke,
          greaterAfterPendingRevoke,
          lesserAfterActiveRevoke,
          greaterAfterActiveRevoke,
          index
        );
        const receipt = await txObject.wait();

        console.log(`Withdraw from ${group}, receipt status: ${receipt.status}`);
      }
    }

    const depositorBeforeWithdrawalBalance = await depositor.getBalance();
    console.log("depositorBeforeWithdrawalBalance", depositorBeforeWithdrawalBalance.toString());

    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);

    const finishPendingWithdrawal = account.finishPendingWithdrawal(depositor.address, 0, 0);
    await (await finishPendingWithdrawal).wait();
    const depositorAfterWithdrawalBalance = await depositor.getBalance();
    console.log("depositorBeforeWithdrawalBalance", depositorBeforeWithdrawalBalance.toString());
    expect(depositorAfterWithdrawalBalance.gt(depositorBeforeWithdrawalBalance)).to.be.true;
  });

  // find index of group in list of groups voted for by account.
  async function findGroupIndex(
    electionWrapper: ElectionWrapper,
    group: string,
    account: string
  ): Promise<number> {
    try {
      const list = await electionWrapper.getGroupsVotedForByAccount(account);
      return list.indexOf(group);
    } catch (error) {
      throw error;
    }
  }
});
