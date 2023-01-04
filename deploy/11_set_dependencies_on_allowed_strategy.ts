import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { AllowedStrategy } from "../typechain-types/AllowedStrategy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const groupHealth = await hre.deployments.get("GroupHealth");
  const allowedStrategy: AllowedStrategy = await hre.ethers.getContract("AllowedStrategy");
  const multisig = await hre.deployments.get("MultiSig");

  if ((await allowedStrategy.callStatic.owner()) !== multisig.address) {
    await executeAndWait(allowedStrategy.setDependencies(account.address, groupHealth.address));
  }
};

func.id = "deploy_set_dependencies_on_allowed_strategy";
func.tags = ["SetDepsOnAllowedStrategy", "core"];
func.dependencies = ["AllowedStrategy", "Account", "GroupHealth", "MultiSig"];
export default func;
