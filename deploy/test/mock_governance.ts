import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer, owner } = await hre.getNamedAccounts();
  const deployment = await deploy("MockGovernance", {
    from: deployer,
    log: true,
  });
};

func.id = "deploy_test_mock_governance";
func.tags = ["TestMockGovernance", "TestAccount"];
func.dependencies = [];
export default func;
