import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { catchNotOwnerForProxy, executeAndWait } from "../lib/deploy-utils";

const parseValidatorGroups = (validatorGroupsString: string | undefined) =>
  validatorGroupsString ? validatorGroupsString.split(",") : [];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const validatorGroups = parseValidatorGroups(process.env.VALIDATOR_GROUPS);

  const isManagerAlreadyDeployed = await hre.deployments.getOrNull("Manager");

  await catchNotOwnerForProxy(
    deploy("Manager", {
      from: deployer,
      log: true,
      proxy: {
        proxyArgs: ["{implementation}", "{data}"],
        proxyContract: "ERC1967Proxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [hre.ethers.constants.AddressZero, deployer],
          },
        },
      },
    })
  );

  if (isManagerAlreadyDeployed) {
    console.log("Manager proxy was already deployed - skipping group activation");
    return;
  }
  // TODO: move to default strategy
  // const manager = await hre.ethers.getContract("Manager");

  // for (let i = 0; i < validatorGroups.length; i++) {
  //   console.log("activating group", validatorGroups[i]);
  //   await executeAndWait(manager.activateGroup(validatorGroups[i]));
  // }
};

func.id = "deploy_manager";
func.tags = ["Manager", "core", "proxy"];
func.dependencies = ["MultiSig"];
export default func;
