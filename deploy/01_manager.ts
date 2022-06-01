import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  // Get a list the named accounts based on network
  const namedAccounts = await hre.getNamedAccounts();

  const deployer = namedAccounts.deployer;

  console.log("deployer--->", namedAccounts);

  // Since we can't get specific named accounts, we remove those we have gotten their value, so that
  // we now have only the multisig left.
  delete namedAccounts["deployer"];

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

func.id = "deploy_manager";
func.tags = ["Manager", "core"];
func.dependencies = ["MultiSig"];
export default func;
