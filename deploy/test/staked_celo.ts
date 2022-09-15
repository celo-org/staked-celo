import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@pahor167/hardhat-deploy/types";

const DESIRED_MIN_VOTES_PER_GROUP = 10;

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const manager = await hre.deployments.get("Manager");
  const { deploy } = hre.deployments;

  const { deployer, owner } = await hre.getNamedAccounts();
  const deployment = await deploy("StakedCelo", {
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
func.tags = ["TestStakedCelo"];
func.dependencies = ["TestManager"];
export default func;
