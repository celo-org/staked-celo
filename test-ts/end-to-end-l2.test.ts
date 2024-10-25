import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import hre from "hardhat";
import { ACCOUNT_REVOKE, ACCOUNT_WITHDRAW } from "../lib/tasksNames";
import { Account } from "../typechain-types/Account";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";
import { StakedCelo } from "../typechain-types/StakedCelo";
import {
  activateAndVoteTest,
  mineToNextEpochL2,
  getValidatorGroupsL2,
  LOCKED_GOLD_UNLOCKING_PERIOD,
  randomSigner,
  rebalanceDefaultGroups,
  rebalanceGroups,
  setBalanceAnvil,
  timeTravel,
} from "./utils";
import {
  activateValidators,
} from "./utils-validators";
import { BigNumber, ContractReceipt } from "ethers";
import { testWithAnvilL2 } from "./test.utils";

after(() => {
  hre.kit.stop();
});

testWithAnvilL2("e2e-L2", async (anvil) => {

  describe("e2e-L2", () => {
    let accountContract: Account;
    let managerContract: Manager;
    let defaultStrategyContract: DefaultStrategy;
    let groupHealthContract: GroupHealth;
    let specificGroupStrategyContract: SpecificGroupStrategy;

    const deployerAccountName = "deployer";
    let depositor0: SignerWithAddress;
    let depositor1: SignerWithAddress;
    let depositor2: SignerWithAddress;
    let voter: SignerWithAddress;

    let groups: string[];
    let activatedGroupAddresses: string[];
    // let validators: SignerWithAddress[];
    let validatorAddresses: string[];

    let stakedCeloContract: StakedCelo;

    // eslint-disable-next-line no-unused-vars, @typescript-eslint/no-explicit-any
    before(async function (this: any) {
      this.timeout(0); // Disable test timeout
      this.timeout(100000);

      process.env = {
        ...process.env,
        TIME_LOCK_MIN_DELAY: "1",
        TIME_LOCK_DELAY: "1",
        MULTISIG_REQUIRED_CONFIRMATIONS: "1",
        VALIDATOR_GROUPS: "",
      };

      [depositor0] = await randomSigner(parseUnits("300"));
      [depositor1] = await randomSigner(parseUnits("300"));
      [depositor2] = await randomSigner(parseUnits("300"));
      [voter] = await randomSigner(parseUnits("300"));
      const accounts = await hre.kit.contracts.getAccounts();
      await accounts.createAccount().sendAndWaitForReceipt({
        from: voter.address,
      });
      groups = [];
      activatedGroupAddresses = [];
      validatorAddresses = [];


      [groups, validatorAddresses] = await getValidatorGroupsL2()
      activatedGroupAddresses = groups

      setBalanceAnvil(depositor0.address, parseUnits("300"));
      setBalanceAnvil(depositor1.address, parseUnits("300"));
    });

    beforeEach(async () => {
      await hre.deployments.fixture("core");
      accountContract = await hre.ethers.getContract("Account");
      managerContract = await hre.ethers.getContract("Manager");
      stakedCeloContract = await hre.ethers.getContract("StakedCelo");
      groupHealthContract = await hre.ethers.getContract("GroupHealth");
      defaultStrategyContract = await hre.ethers.getContract("DefaultStrategy");
      specificGroupStrategyContract = await hre.ethers.getContract("SpecificGroupStrategy");

      const multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");

      for (const group of activatedGroupAddresses) {
        await groupHealthContract.updateGroupHealth(group);
      }

      await activateValidators(
        defaultStrategyContract,
        groupHealthContract as unknown as GroupHealth,
        multisigOwner0,
        activatedGroupAddresses
      );
    });

    it.only("deposit and withdraw", async () => {

      const celoUnreleasedTreasuryAddress = await hre.kit.registry.addressFor("CeloUnreleasedTreasury" as any)
      await setBalanceAnvil(celoUnreleasedTreasuryAddress, parseUnits("900000000"));

      const amountOfCeloToDeposit = hre.ethers.BigNumber.from(parseUnits("0.01"));
      await (await managerContract.connect(depositor1).deposit({ value: amountOfCeloToDeposit })).wait();
      await (await managerContract.connect(depositor0).deposit({ value: amountOfCeloToDeposit })).wait();

      expect(await stakedCeloContract.balanceOf(depositor1.address)).to.eq(amountOfCeloToDeposit);

      await activateAndVoteTest();
      await mineToNextEpochL2()
      await activateAndVoteTest();

      await distributeAllRewardsL2();
      await distributeAllRewardsL2();
      await rebalanceDefaultGroups(defaultStrategyContract);
      await rebalanceGroups(managerContract, specificGroupStrategyContract, defaultStrategyContract);
      await hre.run(ACCOUNT_REVOKE, {
        account: deployerAccountName,
        useNodeAccount: true,
        logLevel: "info",
      });
      await activateAndVoteTest();
      await managerContract.connect(depositor1).withdraw(amountOfCeloToDeposit);
      expect(await stakedCeloContract.balanceOf(depositor1.address)).to.eq(0);
      await hre.run(ACCOUNT_WITHDRAW, {
        beneficiary: depositor1.address,
        account: deployerAccountName,
        useNodeAccount: true,
      });
      const depositor1BeforeWithdrawalBalance = await depositor1.getBalance();

      await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);
      const txs = await finishPendingWithdrawals(depositor1.address);

      expect(txs.length).to.eq(2);

      const firstPartOfAmount = BigNumber.from(3333333333333332);
      const secondPartOfAmount = BigNumber.from(6666666666666668);
      const total = firstPartOfAmount.add(secondPartOfAmount);
      expect(total).to.eq(amountOfCeloToDeposit);

      const firstPartAmountInCelo = await managerContract.toCelo(firstPartOfAmount);
      const secondPartAmountInCelo = await managerContract.toCelo(secondPartOfAmount);

      expect(firstPartAmountInCelo.gt(firstPartOfAmount), `firstPartAmountInCelo ${firstPartAmountInCelo} firstPartOfAmount ${firstPartOfAmount}`).to.be.true;
      expect(secondPartAmountInCelo.gt(secondPartOfAmount), `secondPartAmountInCelo ${secondPartAmountInCelo} secondPartOfAmount ${secondPartOfAmount}`).to.be.true;

      const value1 = getTransferEventValue(txs[1], depositor1.address);
      const value2 = getTransferEventValue(txs[0], depositor1.address);

      await managerContract.connect(depositor2).deposit({ value: amountOfCeloToDeposit });
      expect(await stakedCeloContract.balanceOf(depositor2.address)).to.eq(
        await managerContract.toStakedCelo(amountOfCeloToDeposit)
      );

      expect(value1.add(value2)).to.gt(amountOfCeloToDeposit);
    });

    async function distributeAllRewardsL2() {
      await mineToNextEpochL2(validatorAddresses)
    }

    async function finishPendingWithdrawals(address: string) {
      const { values, timestamps } = await accountContract.getPendingWithdrawals(address);
      const [values2, timestamps2] = await accountContract.getPendingWithdrawals(address);

      const res = []

      for (let i = 0; i < timestamps.length; i++) {
        const tx = await (await accountContract.finishPendingWithdrawal(address, 0, 0)).wait();
        res.push(tx)
      }
      return res
    }

    function getTransferEventValue(receipt: ContractReceipt, to: string): BigNumber {
      // Wait for the transaction to be mined and get the receipt
      // Find the Transfer event in the logs
      const transferEvent = receipt.logs.find((log) => {
        return log.topics[0] === hre.ethers.utils.id("Transfer(address,address,uint256)");
      });

      // Check if the event is found
      if (!transferEvent) {
        throw new Error("Transfer event not found");
      }

      // Decode the event data
      const iface = new hre.ethers.utils.Interface(["event Transfer(address indexed from, address indexed to, uint256 value)"]);
      const decodedLog = iface.decodeEventLog("Transfer", transferEvent.data, transferEvent.topics);

      // Assert the values
      expect(decodedLog.to).to.equal(to);
      return decodedLog.value;
    }
  });
});
