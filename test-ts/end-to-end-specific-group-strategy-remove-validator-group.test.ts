import { ValidatorsWrapper } from "@celo/contractkit/lib/wrappers/Validators";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { ACCOUNT_REVOKE } from "../lib/tasksNames";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { MockGroupHealth } from "../typechain-types/MockGroupHealth";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import { StakedCelo } from "../typechain-types/StakedCelo";
import {
  activateAndVoteTest,
  distributeEpochRewards,
  getGroupsOfAllStrategies,
  getRealVsExpectedCeloForGroups,
  mineToNextEpoch,
  randomSigner,
  rebalanceDefaultGroups,
  rebalanceGroups,
  resetNetwork,
  upgradeToMockGroupHealthE2E,
} from "./utils";
import {
  activateValidators,
  deregisterValidatorGroup,
  electMockValidatorGroupsAndUpdate,
  registerValidatorAndAddToGroupMembers,
  registerValidatorGroup,
} from "./utils-validators";

after(() => {
  hre.kit.stop();
});

describe("e2e specific group strategy voting removed validator group", () => {
  let accountContract: Account;
  let managerContract: Manager;
  let groupHealthContract: MockGroupHealth;
  let validatorsWrapper: ValidatorsWrapper;
  let specificGroupStrategyContract: SpecificGroupStrategy;
  let defaultStrategy: DefaultStrategy;

  const deployerAccountName = "deployer";
  // default strategy
  let depositor1: SignerWithAddress;
  let depositor2: SignerWithAddress;
  // specific strategy that is same as one of the active groups
  let voter: SignerWithAddress;

  let groups: SignerWithAddress[];
  let activatedGroupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let stakedCeloContract: StakedCelo;
  let multisigOwner0: SignerWithAddress;

  const rewardsGroup0 = hre.ethers.BigNumber.from(parseUnits("10"));
  const rewardsGroup1 = hre.ethers.BigNumber.from(parseUnits("20"));
  const rewardsGroup2 = hre.ethers.BigNumber.from(parseUnits("30"));
  const rewardsGroup5 = hre.ethers.BigNumber.from(parseUnits("10"));

  let specificGroupStrategyDifferentFromActive: SignerWithAddress;

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

    [depositor1] = await randomSigner(parseUnits("300"));
    [depositor2] = await randomSigner(parseUnits("300"));
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
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    accountContract = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    stakedCeloContract = await hre.ethers.getContract("StakedCelo");
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
    ]);

    await activateValidators(
      defaultStrategy,
      groupHealthContract as unknown as GroupHealth,
      multisigOwner0,
      activatedGroupAddresses
    );
  });

  it("deposit, rebalance, transfer and withdraw", async () => {
    const amountOfCeloToDeposit = hre.ethers.BigNumber.from(parseUnits("1"));

    await managerContract
      .connect(depositor1)
      .changeStrategy(specificGroupStrategyDifferentFromActive.address);

    await managerContract.connect(depositor1).deposit({ value: amountOfCeloToDeposit });
    await managerContract.connect(depositor2).deposit({ value: amountOfCeloToDeposit });

    console.log("celoForGroup", (await accountContract.getCeloForGroup(specificGroupStrategyDifferentFromActive.address)).toString());

    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    await activateAndVoteTest();
    await mineToNextEpoch(hre.web3);
    await activateAndVoteTest();

    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    await expectStCeloBalance(depositor1.address, amountOfCeloToDeposit);

    await rebalanceAllAndActivate();

    await activateAndVoteTest();
    await mineToNextEpoch(hre.web3);
    await activateAndVoteTest();
    await distributeAllRewards();
    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);

    await deregisterValidatorGroup(specificGroupStrategyDifferentFromActive);

    await specificGroupStrategyContract.getStCeloInGroup(specificGroupStrategyDifferentFromActive.address);

    await groupHealthContract.updateGroupHealth(specificGroupStrategyDifferentFromActive.address);


    await specificGroupStrategyContract.rebalanceWhenHealthChanged(
      specificGroupStrategyDifferentFromActive.address
    );


    await expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy);
    
    await rebalanceAllAndActivate();
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

  async function expectStCeloBalance(account: string, expectedAmount: BigNumberish) {
    const balance = await stakedCeloContract.balanceOf(account);
    expect(expectedAmount, `account ${account} ex: ${expectedAmount} real: ${balance}`).to.eq(
      balance
    );
  }

   // We use range because of possible rounding errors when withdrawing
   function expectBigNumberInRange(real: BigNumber, expected: BigNumber, range = 10) {
    expect(
      real.add(range).gte(expected),
      `Number ${real.toString()} is not in range <${expected.sub(range).toString()}, ${expected
        .add(range)
        .toString()}>`
    ).to.be.true;
    expect(
      real.sub(range).lte(expected),
      `Number ${real.toString()} is not in range <${expected.sub(range).toString()}, ${expected
        .add(range)
        .toString()}>`
    ).to.be.true;
  }

  async function expectSumOfExpectedAndRealCeloInGroupsToEqual(defaultStrategy: DefaultStrategy) {
    const allGroups = await getGroupsOfAllStrategies(
      defaultStrategy,
      specificGroupStrategyContract
    );
    const expectedVsReal = await getRealVsExpectedCeloForGroups(managerContract, allGroups);
    let expectedSum = hre.ethers.BigNumber.from(0);
    let realSum = hre.ethers.BigNumber.from(0);
    for (const group of expectedVsReal) {
      expectedSum = expectedSum.add(group.expected);
      realSum = realSum.add(group.real);
    }
    expectBigNumberInRange(realSum, expectedSum);
  }
});
