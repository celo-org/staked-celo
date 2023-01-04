import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const groupHealth = await hre.deployments.get("GroupHealth");
  const allowedStrategy = await hre.deployments.get("AllowedStrategy");
  const defaultStrategy: DefaultStrategy = await hre.ethers.getContract("DefaultStrategy");
  const multisig = await hre.deployments.get("MultiSig");

  if ((await defaultStrategy.callStatic.owner()) !== multisig.address) {
    await executeAndWait(
      defaultStrategy.setDependencies(account.address, groupHealth.address, allowedStrategy.address)
    );
  }
};

func.id = "deploy_set_dependencies_on_vote";
func.tags = ["SetDepsOnDefaultStrategy", "core"];
func.dependencies = ["DefaultStrategy", "Account", "GroupHealth", "AllowedStrategy", "MultiSig"];
export default func;
