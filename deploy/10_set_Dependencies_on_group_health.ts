import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { GroupHealth } from "../typechain-types/GroupHealth";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const manager = await hre.deployments.get("Manager");
  const allowedStrategy = await hre.deployments.get("AllowedStrategy");
  const stakedCelo = await hre.deployments.get("StakedCelo");
  const groupHealth: GroupHealth = await hre.ethers.getContract("GroupHealth");
  const multisig = await hre.deployments.get("MultiSig");

  if ((await groupHealth.callStatic.owner()) !== multisig.address) {
    await executeAndWait(
      groupHealth.setDependencies(
        stakedCelo.address,
        account.address,
        allowedStrategy.address,
        manager.address
      )
    );
  }
};

func.id = "deploy_set_Dependencies_on_group_health";
func.tags = ["SetDepsOnGroupHealth", "core"];
func.dependencies = [
  "GroupHealth",
  "Account",
  "Manager",
  "AllowedStrategy",
  "StakedCelo",
  "MultiSig",
];
export default func;
