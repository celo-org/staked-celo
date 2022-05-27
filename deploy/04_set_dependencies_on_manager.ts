import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Manager } from "../typechain-types/Manager";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const account = await hre.deployments.get("Account");
  const stakedCelo = await hre.deployments.get("StakedCelo");
  const manager: Manager = await hre.ethers.getContract("Manager");
  await manager.setDependencies(stakedCelo.address, account.address);
};

func.id = "deploy_set_dependencies_on_manager";
func.tags = ["SetDepsOnManager"];
func.dependencies = ["Manager", "Account", "StakedCelo"];
export default func;