import hre, { ethers } from "hardhat";
import { Account } from "../../typechain-types/Account";
import { AccountsWrapper } from "@celo/contractkit/lib/wrappers/Accounts";
import { ElectionWrapper } from "@celo/contractkit/lib/wrappers/Election";
import { LockedGoldWrapper } from "@celo/contractkit/lib/wrappers/LockedGold";
import { expect } from "chai";
import { parseUnits } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  ADDRESS_ZERO,
  LOCKED_GOLD_UNLOCKING_PERIOD,
  randomSigner,
  registerValidator,
  registerValidatorGroup,
  resetNetwork,
  timeTravel,
} from "../utils";
import { Manager } from "../../typechain-types/Manager";
import { MockStakedCelo } from "../../typechain-types/MockStakedCelo";
import { MockStakedCelo__factory } from "../../typechain-types/factories/MockStakedCelo__factory";
import { ACCOUNT_ACTIVATE_AND_VOTE, ACCOUNT_WITHDRAW } from "../../lib/tasksNames";
import { StakedCelo } from "../../typechain-types/StakedCelo";
import { StakedCelo__factory } from "../../typechain-types/factories/StakedCelo__factory";
import { MultiSig } from "../../typechain-types/MultiSig";

after(() => {
  hre.kit.stop();
});

describe("e2e", () => {
  let accountsInstance: AccountsWrapper;
  let lockedGold: LockedGoldWrapper;
  let election: ElectionWrapper;

  let account: Account;
  let managerContract: Manager;
  let multisigContract: MultiSig;

  let depositor: SignerWithAddress;
  let owner: SignerWithAddress;

  let groups: SignerWithAddress[];
  let groupAddresses: string[];
  let validators: SignerWithAddress[];
  let validatorAddresses: string[];

  let stakedCelo: StakedCelo;

  before(async () => {
    await resetNetwork();

    process.env = {
      ...process.env,
      TIME_LOCK_MIN_DELAY: "1",
      TIME_LOCK_DELAY: "1",
      MULTISIG_REQUIRED_CONFIRMATIONS: "1",
    };

    [depositor] = await randomSigner(parseUnits("300"));
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

    // const stakedCeloFactory: StakedCelo__factory = (
    //   await hre.ethers.getContractFactory("StakedCelo")
    // ).connect(owner) as StakedCelo__factory;
    // stakedCelo = await stakedCeloFactory.deploy(

    // );

    // await hre.deployments.fixture("StakedCelo");
  });

  beforeEach(async () => {
    await hre.deployments.fixture("core");
    const owner = await hre.ethers.getNamedSigner("owner");
    const deployer = await hre.ethers.getNamedSigner("deployer");
    account = await hre.ethers.getContract("Account");
    managerContract = await hre.ethers.getContract("Manager");
    managerContract = managerContract.attach(await account.manager());
    multisigContract = await hre.ethers.getContract("MultiSig");
    console.log("Hello");
    console.log("Account owner", await account.owner());
    console.log("Manager owner", await managerContract.owner());
    console.log("myOwner", owner.address);
    console.log("deployer", deployer.address);
    console.log("multisigContract", multisigContract.address);
    // await account.connect(deployer).setManager(managerContract.address);

    const msOwners = await multisigContract.getOwners();
    console.log("msOwners", msOwners);

    stakedCelo = await hre.ethers.getContract("StakedCelo");

    // await stakedCelo.connect(owner).initialize(managerContract.address, owner.address)
    const stakedCeloOwner = await stakedCelo.owner();
    console.log("stakedCeloOwner", stakedCeloOwner);

    const myOwner = owner.address;
    console.log("myOwner", myOwner);
    // await stakedCelo.connect(owner).setManager(managerContract.address)
  });

  it("deposit and withdraw", async () => {
    managerContract.setDependencies(stakedCelo.address, account.address);

    const multisigOwner0 = await hre.ethers.getNamedSigner("multisigOwner0");
    console.log("multisigOwner0", multisigOwner0);
    // const multisigOwner0 = await hre.ethers.getSigner(multisigContract.address)

    await impersonateAccount(multisigContract.address);
    const tx = await owner.sendTransaction({
      to: multisigContract.address,
      value: ethers.BigNumber.from("10000000000000000000"),
    });
    await tx.wait();
    const signerWithAddress = await ethers.getSigner(multisigContract.address);

    for (let i = 0; i < 3; i++) {
      await managerContract.connect(signerWithAddress).activateGroup(groupAddresses[i]);
    }
    await managerContract.connect(depositor).deposit({ value: 100 });
    let stCelo = await stakedCelo.balanceOf(depositor.address);
    expect(stCelo).to.eq(100);

    await hre.run(ACCOUNT_ACTIVATE_AND_VOTE);

    const withdrawStakedCelo = await managerContract.connect(depositor).withdraw(100);
    await withdrawStakedCelo.wait();

    stCelo = await stakedCelo.balanceOf(depositor.address);
    expect(stCelo).to.eq(0);

    await hre.run(ACCOUNT_WITHDRAW, { beneficiary: depositor.address });

    const depositorBeforeWithdrawalBalance = await depositor.getBalance();

    await timeTravel(LOCKED_GOLD_UNLOCKING_PERIOD);

    const finishPendingWithdrawal = account.finishPendingWithdrawal(depositor.address, 0, 0);
    await (await finishPendingWithdrawal).wait();
    const depositorAfterWithdrawalBalance = await depositor.getBalance();
    expect(depositorAfterWithdrawalBalance.gt(depositorBeforeWithdrawalBalance)).to.be.true;
  });

  async function impersonateAccount(address: string) {
    await hre.network.provider.send("hardhat_impersonateAccount", [address]);
  }
});
