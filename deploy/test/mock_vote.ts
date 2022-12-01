import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer } = await hre.getNamedAccounts();
  await deploy("MockVote", {
    from: deployer,
    log: true,
  });
};

func.id = "deploy_test_mock_vote";
func.tags = ["TestManager", "TestMockVote"];
func.dependencies = [];
export default func;
