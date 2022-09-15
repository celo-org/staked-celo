import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@pahor167/hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer, owner } = await hre.getNamedAccounts();
  const deployment = await deploy("MockAccount", {
    from: deployer,
    log: true,
  });
};

func.id = "deploy_test_mock_account";
func.tags = ["TestMockAccount"];
func.dependencies = [];
export default func;
