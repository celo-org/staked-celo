import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer, owner } = await hre.getNamedAccounts();
  const deployment = await deploy("MockStakedCelo", {
    from: deployer,
    log: true,
  });
};

func.id = "deploy_test_mock_staked_celo";
func.tags = ["TestMockStakedCelo"];
func.dependencies = [];
export default func;
