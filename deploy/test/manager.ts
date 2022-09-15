import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@pahor167/hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const deployment = await deploy("Manager", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [hre.ethers.constants.AddressZero, deployer],
      },
    },
  });
};

func.id = "deploy_test_manager";
func.tags = ["TestManager"];
func.dependencies = [];
export default func;
