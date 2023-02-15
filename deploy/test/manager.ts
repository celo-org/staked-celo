import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer, owner } = await hre.getNamedAccounts();

  await deploy("Manager", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      owner: owner,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [hre.ethers.constants.AddressZero, deployer],
      },
    },
  });
};

func.id = "deploy_test_manager";
func.tags = ["FullTestManager", "TestManager"];
func.dependencies = [];
export default func;
