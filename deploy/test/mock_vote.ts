import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer, owner } = await hre.getNamedAccounts();
  const deployment = await deploy("MockVote", {
    from: deployer,
    log: true,
  });
};

func.id = "deploy_test_mock_vote";
func.tags = ["TestManager", "TestMockVote"];
func.dependencies = [];
export default func;
