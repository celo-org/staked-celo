import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Manager } from "../typechain-types/Manager";
import { Account } from "../typechain-types/Account";
import { StakedCelo } from "../typechain-types/StakedCelo";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const account: Account = await hre.ethers.getContract("Account");
  const stakedCelo: StakedCelo = await hre.ethers.getContract("StakedCelo");
  const manager: Manager = await hre.ethers.getContract("Manager");
  const multisig = await hre.deployments.get("MultiSig");

  await account.transferOwnership(multisig.address);
  await stakedCelo.transferOwnership(multisig.address);
  await manager.transferOwnership(multisig.address);
};

func.id = "deploy_transfer_to_multisig";
func.tags = ["TransferAllContractsToMultisig"];
func.dependencies = ["Manager", "Account", "StakedCelo", "MultiSig"];
export default func;
