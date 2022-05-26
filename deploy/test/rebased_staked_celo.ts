import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const stakedCelo = await hre.deployments.get("MockStakedCelo");
  const account = await hre.deployments.get("MockAccount");

  const { deploy } = hre.deployments;
  const { deployer, owner } = await hre.getNamedAccounts();

  const deployment = await deploy("RebasedStakedCelo", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      owner: owner,
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [stakedCelo.address, account.address, owner],
      },
    },
  });
};

func.id = "deploy_test_rebased_staked_celo";
func.tags = ["TestRebasedStakedCelo"];
func.dependencies = ["TestMockStakedCelo", "TestMockAccount"];
export default func;
