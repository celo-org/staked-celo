import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { catchNotOwnerForProxy, executeAndWait } from "../lib/deploy-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const managerAddress = (await hre.deployments.get("Manager")).address;
  const deployment = await catchNotOwnerForProxy(
    deploy("Vote", {
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

func.id = "deploy_vote";
func.tags = ["Vote", "core", "proxy", "voteDeploy"];
func.dependencies = ["MultiSig"];
export default func;
