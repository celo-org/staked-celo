import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  await deploy("PausableTest", {
    from: deployer,
    log: true,
  });
};

func.id = "deploy_test_pausable";
func.tags = ["TestPausable"];
export default func;
