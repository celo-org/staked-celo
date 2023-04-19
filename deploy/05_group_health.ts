import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { catchNotOwnerForProxy } from "../lib/deploy-utils";

const parseValidatorGroups = (validatorGroupsString: string | undefined) =>
  validatorGroupsString ? validatorGroupsString.split(",") : [];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const multisig = await hre.deployments.get("MultiSig");

  const isGroupHealthAlreadyDeployed = await hre.deployments.getOrNull("GroupHealth");

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

  if (!isGroupHealthAlreadyDeployed) {
    const validatorGroups = parseValidatorGroups(process.env.VALIDATOR_GROUPS);
    if (validatorGroups.length == 0) {
      return;
    }

    const groupHealth = await hre.ethers.getContract("GroupHealth");

    for (let i = 0; i < validatorGroups.length; i++) {
      const updateGroupHealthTx = await groupHealth.updateGroupHealth(validatorGroups[i]);
      await updateGroupHealthTx.wait();
    }
  }
};

func.id = "deploy_group_health";
func.tags = ["GroupHealth", "core", "proxy"];
func.dependencies = ["MultiSig"];
export default func;
