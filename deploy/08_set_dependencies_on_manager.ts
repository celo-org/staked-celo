import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES } from "../lib/tasksNames";
import { Manager } from "../typechain-types/Manager";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const stakedCelo = await hre.deployments.get("StakedCelo");
  const vote = await hre.deployments.get("Vote");
  const manager: Manager = await hre.ethers.getContract("Manager");
  const multisig = await hre.deployments.get("MultiSig");
  const groupHealth = await hre.deployments.get("GroupHealth");
  const specificGroupStrategy = await hre.deployments.get("SpecificGroupStrategy");
  const defaultStrategy = await hre.deployments.get("DefaultStrategy");

  if ((await manager.callStatic.owner()) !== multisig.address) {
    await executeAndWait(
      manager.setDependencies(
        stakedCelo.address,
        account.address,
        vote.address,
        groupHealth.address,
        specificGroupStrategy.address,
        defaultStrategy.address
      )
    );
  } else {
    console.log(
      chalk.red(
        `Manager is already owned by multisig run task ${MULTISIG_ENCODE_SET_MANAGER_DEPENDENCIES} to set dependencies (including vote) address in manager contract!`
      )
    );
  }
};

func.id = "deploy_set_dependencies_on_manager";
func.tags = ["SetDepsOnManager", "core"];
func.dependencies = ["Manager", "Account", "StakedCelo"];
export default func;
