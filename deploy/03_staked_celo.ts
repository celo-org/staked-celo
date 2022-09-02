import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { getNoDependencies, getNoProxy } from "../lib/deploy-utils";

const noDependencies = getNoDependencies();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  const managerAddress =
    process.env.MANAGER_ADDRESS ?? (await hre.deployments.get("Manager")).address;
  const noProxy = getNoProxy();

  const deployment = await deploy("StakedCelo", {
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
            args: [managerAddress, deployer],
          },
        },
  });
};

func.id = "deploy_staked_celo";
func.tags = ["StakedCelo", "core"];
func.dependencies = noDependencies ? undefined : ["MultiSig", "Manager"];
export default func;
