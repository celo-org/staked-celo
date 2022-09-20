import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { Manager } from "../typechain-types/Manager";
import { executeAndWait } from "../lib/deploy-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const stakedCelo = await hre.deployments.get("StakedCelo");
  const manager: Manager = await hre.ethers.getContract("Manager");
  await executeAndWait(manager.setDependencies(stakedCelo.address, account.address));
};

func.id = "deploy_set_dependencies_on_manager";
func.tags = ["SetDepsOnManager", "core"];
func.dependencies = ["Manager", "Account", "StakedCelo"];
export default func;
