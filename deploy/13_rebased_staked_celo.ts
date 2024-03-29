import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { catchNotOwnerForProxy } from "../lib/deploy-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const stakedCeloAddress = (await hre.deployments.get("StakedCelo")).address;
  const accountAddress = (await hre.deployments.get("Account")).address;
  const multiSigAddress = (await hre.deployments.get("MultiSig")).address;

  const { deploy } = hre.deployments;

  const { deployer } = await hre.getNamedAccounts();
  await catchNotOwnerForProxy(
    deploy("RebasedStakedCelo", {
      from: deployer,
      log: true,
      proxy: {
        proxyArgs: ["{implementation}", "{data}"],
        owner: multiSigAddress,
        proxyContract: "ERC1967Proxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [stakedCeloAddress, accountAddress, multiSigAddress],
          },
        },
      },
    })
  );
};

func.id = "deploy_rebased_staked_celo";
func.tags = ["RebasedStakedCelo", "core", "proxy"];
func.dependencies = ["StakedCelo", "Account", "MultiSig"];
export default func;
