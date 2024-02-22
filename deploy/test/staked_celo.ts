import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const manager = await hre.deployments.get("Manager");
  const { deploy } = hre.deployments;

  const { deployer, owner } = await hre.getNamedAccounts();
  await deploy("StakedCelo", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      owner: owner,
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [manager.address, owner],
      },
    },
  });
};

func.id = "deploy_test_staked_celo";
func.tags = ["TestStakedCelo", "TestVote"];
func.dependencies = ["TestManager"];
export default func;
