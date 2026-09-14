import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { randomSigner, resetNetwork, upgradeToMockGroupHealthE2E } from "./utils";
import {
  activateValidators,
  electMockValidatorGroupsAndUpdate,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
} from "./utils-validators";

after(() => {
  hre.kit.stop();
});

describe("Manager strategy change: delayed transfer", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let groupHealthContract: MockGroupHealth;
  let defaultStrategy: DefaultStrategy;

  let depositor: SignerWithAddress;
  let groups: SignerWithAddress[];
  let multisigOwner0: SignerWithAddress;

  before(async function () {
    this.timeout(0);
    await resetNetwork();

    process.env = {
      ...process.env,
      TIME_LOCK_MIN_DELAY: "1",
      TIME_LOCK_DELAY: "1",
      MULTISIG_REQUIRED_CONFIRMATIONS: "1",
      VALIDATOR_GROUPS: "",
    };

    [depositor] = await randomSigner(parseUnits("1000"));

    // Create 2 validator groups
    groups = [];
    for (let i = 0; i < 2; i++) {
      const [group] = await randomSigner(parseUnits("21000"));
      groups.push(group);
      await registerValidatorGroup(group, 1);
      const [validator, validatorWallet] = await randomSigner(parseUnits("11000"));
      await registerValidatorAndAddToGroupMembers(group, validator, validatorWallet);
    }
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    groupHealthContract = await hre.ethers.getContract("GroupHealth");
    defaultStrategy = await hre.ethers.getContract("DefaultStrategy");

    multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");

    groupHealthContract = await upgradeToMockGroupHealthE2E(
      multisigOwner0,
      groupHealthContract as unknown as GroupHealth
    );

    const validatorWrapper = await hre.kit.contracts.getValidators();
    await electMockValidatorGroupsAndUpdate(validatorWrapper, groupHealthContract, [
      groups[0].address,
      groups[1].address,
    ]);

    await activateValidators(
      defaultStrategy,
      groupHealthContract as unknown as GroupHealth,
      multisigOwner0,
      [groups[0].address, groups[1].address]
    );
  });

  it("should NOT schedule transfers immediately on strategy change", async () => {
    // Deposit to default strategy
    const depositAmount = parseUnits("100");
    await managerContract.connect(depositor).deposit({ value: depositAmount });

    // Record initial state
    const group0RevokeBefore = await accountContract.scheduledRevokeForGroup(groups[0].address);
    const group1RevokeBefore = await accountContract.scheduledRevokeForGroup(groups[1].address);
    const group0ScheduledBefore = await accountContract.scheduledVotesForGroup(groups[0].address);
    const group1ScheduledBefore = await accountContract.scheduledVotesForGroup(groups[1].address);

    // Change strategy to specific group
    await managerContract.connect(depositor).changeStrategy(groups[0].address);

    // No transfers scheduled after change strategy
    const group0RevokeAfterChange = await accountContract.scheduledRevokeForGroup(
      groups[0].address
    );
    const group1RevokeAfterChange = await accountContract.scheduledRevokeForGroup(
      groups[1].address
    );
    const group0ScheduledAfterChange = await accountContract.scheduledVotesForGroup(
      groups[0].address
    );
    const group1ScheduledAfterChange = await accountContract.scheduledVotesForGroup(
      groups[1].address
    );
    expect(group0RevokeAfterChange).to.equal(
      group0RevokeBefore,
      "changeStrategy must NOT schedule revokes"
    );
    expect(group1RevokeAfterChange).to.equal(
      group1RevokeBefore,
      "changeStrategy must NOT schedule revokes"
    );
    expect(group0ScheduledAfterChange).to.equal(
      group0ScheduledBefore,
      "changeStrategy must NOT schedule votes"
    );
    expect(group1ScheduledAfterChange).to.equal(
      group1ScheduledBefore,
      "changeStrategy must NOT schedule votes"
    );

    // Internal accounting should be updated
    const depositorStrategy = await managerContract.strategies(depositor.address);
    expect(depositorStrategy).to.equal(groups[0].address);

    // Call rebalance
    await managerContract.rebalance(groups[1].address, groups[0].address);

    // Transfers are scheduled after rebalance
    const group0ScheduledAfterRebalance = await accountContract.scheduledVotesForGroup(
      groups[0].address
    );
    expect(group0ScheduledAfterRebalance).to.be.gt(
      group0ScheduledAfterChange,
      "rebalance SHOULD schedule votes"
    );
  });
});
