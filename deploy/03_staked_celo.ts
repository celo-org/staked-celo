import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  const managerAddress = (await hre.deployments.get("Manager")).address;

  const deployment = await deploy("StakedCelo", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [managerAddress, deployer],
        },
      },
    },
  });
};

func.id = "deploy_staked_celo";
func.tags = ["StakedCelo", "core"];
func.dependencies = ["MultiSig", "Manager"];
export default func;
