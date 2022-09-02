import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { getNoDependencies, getNoProxy } from "../lib/deploy-utils";

const noDependencies = getNoDependencies();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const noProxy = getNoProxy();

  const managerAddress =
    process.env.MANAGER_ADDRESS ?? (await hre.deployments.get("Manager")).address;
  const { deployer } = await hre.getNamedAccounts();
  const deployment = await deploy("Account", {
    from: deployer,
    log: true,
    proxy: noProxy
      ? undefined
      : {
          proxyArgs: ["{implementation}", "{data}"],
          upgradeIndex: 0,
          proxyContract: "ERC1967Proxy",
          execute: {
            methodName: "initialize",
            args: [hre.ethers.constants.AddressZero, managerAddress, deployer],
          },
        },
  });
};

func.id = "deploy_account";
func.tags = ["Account", "core"];
func.dependencies = noDependencies ? undefined : ["MultiSig", "Manager"];
export default func;
