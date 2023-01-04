import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { catchNotOwnerForProxy } from "../lib/deploy-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const managerAddress = (await hre.deployments.get("Manager")).address;
  await catchNotOwnerForProxy(
    deploy("AllowedStrategy", {
      from: deployer,
      log: true,
      proxy: {
        proxyArgs: ["{implementation}", "{data}"],
        proxyContract: "ERC1967Proxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [hre.ethers.constants.AddressZero, deployer, managerAddress],
          },
        },
      },
    })
  );
};

func.id = "deploy_allowed_strategy";
func.tags = ["AllowedStrategy", "core", "proxy"];
func.dependencies = ["MultiSig"];
export default func;
