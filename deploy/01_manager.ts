import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { executeAndWait } from "../lib/deploy-utils";

const parseValidatorGroups = (validatorGroupsString: string | undefined) =>
  validatorGroupsString ? validatorGroupsString.split(",") : [];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const validatorGroups = parseValidatorGroups(process.env.VALIDATOR_GROUPS);

  const deployment = await deploy("Manager", {
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
  });

  const manager = await hre.ethers.getContract("Manager");

  for (let i = 0; i < validatorGroups.length; i++) {
    console.log("activating group", validatorGroups[i]);
    await executeAndWait(manager.activateGroup(validatorGroups[i]));
  }
};

func.id = "deploy_manager";
func.tags = ["Manager", "core"];
func.dependencies = ["MultiSig"];
export default func;
