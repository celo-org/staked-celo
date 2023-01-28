import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { catchNotOwnerForProxy } from "../lib/deploy-utils";
import { ADDRESS_ZERO } from "../test-ts/utils";

const parseValidatorGroups = (validatorGroupsString: string | undefined) =>
  validatorGroupsString ? validatorGroupsString.split(",") : [];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  // Library deployment
  const lib = await hre.ethers.getContractFactory("AddressSortedLinkedList");
  const libInstance = await lib.deploy();
  await libInstance.deployed();
  console.log("Library Address--->" + libInstance.address);

  const managerAddress = (await hre.deployments.get("Manager")).address;
  await catchNotOwnerForProxy(
    deploy("DefaultStrategy", {
      from: deployer,
      log: true,
      libraries: { AddressSortedLinkedList: libInstance.address },
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

  const defaultStrategy = await hre.ethers.getContract("DefaultStrategy");
  const validatorGroups = parseValidatorGroups(process.env.VALIDATOR_GROUPS);

  let nextGroup = ADDRESS_ZERO;
  for (let i = 0; i < validatorGroups.length; i++) {
    await defaultStrategy.activateGroup(validatorGroups[i], ADDRESS_ZERO, nextGroup);
    nextGroup = validatorGroups[i];
  }
};

func.id = "deploy_default_strategy";
func.tags = ["DefaultStrategy", "core", "proxy"];
func.dependencies = ["MultiSig"];
export default func;
