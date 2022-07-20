import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const manager = await hre.deployments.get("Manager");
  const multisig = await hre.deployments.get("MultiSig");

  const { deployer } = await hre.getNamedAccounts();
  const deployment = await deploy("Account", {
    from: deployer,
    log: true,
    proxy: {
      owner: multisig.address,
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [hre.ethers.constants.AddressZero, manager.address, deployer],
      },
    },
  });
};

func.id = "deploy_account";
func.tags = ["Account", "core"];
func.dependencies = ["MultiSig", "Manager"];
export default func;
