import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { catchNotOwnerForProxy } from "../lib/deploy-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const multisig = await hre.deployments.get("MultiSig");

  await catchNotOwnerForProxy(
    deploy("GroupHealth", {
      from: deployer,
      log: true,
      proxy: {
        proxyArgs: ["{implementation}", "{data}"],
        proxyContract: "ERC1967Proxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [hre.ethers.constants.AddressZero, multisig.address],
          },
        },
      },
    })
  );
};

func.id = "deploy_group_health";
func.tags = ["GroupHealth", "core", "proxy"];
func.dependencies = ["MultiSig"];
export default func;
