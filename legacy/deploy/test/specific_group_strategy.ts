import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer, owner } = await hre.getNamedAccounts();
  const managerAddress = (await hre.deployments.get("Manager")).address;

  await deploy("SpecificGroupStrategy", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      owner: owner,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [owner, managerAddress],
      },
    },
  });
};

func.id = "deploy_test_specific_group_strategy";
func.tags = ["FullTestManager", "TestSpecificGroupStrategy", "TestVote"];
func.dependencies = ["TestManager"];
export default func;
