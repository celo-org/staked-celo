import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  const manager = await hre.deployments.get("Manager");
  const multisig = await hre.deployments.get("MultiSig");

  const deployment = await deploy("StakedCelo", {
    from: deployer,
    log: true,
    proxy: {
      owner: multisig.address,
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [manager.address, deployer],
      },
    },
  });
};

func.id = "deploy_staked_celo";
func.tags = ["StakedCelo", "core"];
func.dependencies = ["MultiSig", "Manager"];
export default func;
