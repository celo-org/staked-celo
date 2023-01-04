import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { Account } from "../typechain-types/Account";
import { AllowedStrategy } from "../typechain-types/AllowedStrategy";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";
import { Manager } from "../typechain-types/Manager";
import { StakedCelo } from "../typechain-types/StakedCelo";
import { Vote } from "../typechain-types/Vote";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account: Account = await hre.ethers.getContract("Account");
  const stakedCelo: StakedCelo = await hre.ethers.getContract("StakedCelo");
  const manager: Manager = await hre.ethers.getContract("Manager");
  const vote: Vote = await hre.ethers.getContract("Vote");
  const groupHealth: GroupHealth = await hre.ethers.getContract("GroupHealth");
  const allowedStrategy: AllowedStrategy = await hre.ethers.getContract("AllowedStrategy");
  const defaultStrategy: DefaultStrategy = await hre.ethers.getContract("DefaultStrategy");
  const multisig = await hre.deployments.get("MultiSig");

  if ((await account.callStatic.owner()) !== multisig.address) {
    await executeAndWait(account.transferOwnership(multisig.address));
  }
  if ((await stakedCelo.callStatic.owner()) !== multisig.address) {
    await executeAndWait(stakedCelo.transferOwnership(multisig.address));
  }
  if ((await manager.callStatic.owner()) !== multisig.address) {
    await executeAndWait(manager.transferOwnership(multisig.address));
  }
  if ((await vote.callStatic.owner()) !== multisig.address) {
    await executeAndWait(vote.transferOwnership(multisig.address));
  }
  if ((await groupHealth.callStatic.owner()) !== multisig.address) {
    await executeAndWait(groupHealth.transferOwnership(multisig.address));
  }
  if ((await allowedStrategy.callStatic.owner()) !== multisig.address) {
    await executeAndWait(allowedStrategy.transferOwnership(multisig.address));
  }
  if ((await defaultStrategy.callStatic.owner()) !== multisig.address) {
    await executeAndWait(defaultStrategy.transferOwnership(multisig.address));
  }
};

func.id = "deploy_transfer_to_multisig";
func.tags = ["TransferAllContractsToMultisig", "core"];
func.dependencies = ["Manager", "Account", "StakedCelo", "MultiSig", "Vote"];
export default func;
