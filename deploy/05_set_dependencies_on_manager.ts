import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { Manager } from "../typechain-types/Manager";
import { executeAndWait } from "../lib/deploy-utils";
import chalk from "chalk";
import { MULTISIG_SUBMIT_PROPOSAL_SET_DEPENDENCIES } from "../lib/tasksNames";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const stakedCelo = await hre.deployments.get("StakedCelo");
  const vote = await hre.deployments.get("Vote");
  const manager: Manager = await hre.ethers.getContract("Manager");
  const multisig = await hre.deployments.get("MultiSig");

  if ((await manager.callStatic.owner()) !== multisig.address) {
    await executeAndWait(
      manager.setDependencies(stakedCelo.address, account.address, vote.address)
    );
  } else {
    console.log(
      chalk.red(
        `Manager is already owned by multisig run task ${MULTISIG_SUBMIT_PROPOSAL_SET_DEPENDENCIES} to set dependencies (including vote) address in manager contract!`
      )
    );
  }
};

func.id = "deploy_set_dependencies_on_manager";
func.tags = ["SetDepsOnManager", "core"];
func.dependencies = ["Manager", "Account", "StakedCelo"];
export default func;
