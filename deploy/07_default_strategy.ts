import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { BigNumber } from "ethers";
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

  const isDefaultStrategyAlreadyDeployed = await hre.deployments.getOrNull("DefaultStrategy");

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

  if (!isDefaultStrategyAlreadyDeployed) {
    const validatorGroups = parseValidatorGroups(process.env.VALIDATOR_GROUPS);
    if (validatorGroups.length == 0) {
      return;
    }

    const defaultStrategy = await hre.ethers.getContract("DefaultStrategy");
    const account = await hre.ethers.getContract("Account");

    const validatorGroupsWithCelo = await Promise.all(
      validatorGroups.map(async (validatorGroup) => ({
        group: validatorGroup,
        celo: (await account.getCeloForGroup(validatorGroup)) as BigNumber,
      }))
    );

    const validatorGroupsSortedDesc = validatorGroupsWithCelo.sort((a, b) =>
      a.celo.lt(b.celo) ? 1 : -1
    );

    let nextGroup = ADDRESS_ZERO;
    for (let i = 0; i < validatorGroupsSortedDesc.length; i++) {
      const activateTx = await defaultStrategy.activateGroup(
        validatorGroupsSortedDesc[i].group,
        ADDRESS_ZERO,
        nextGroup
      );
      await activateTx.wait();
      nextGroup = validatorGroupsSortedDesc[i].group;
    }
  }
};

func.id = "deploy_default_strategy";
func.tags = ["DefaultStrategy", "core", "proxy"];
func.dependencies = ["MultiSig"];
export default func;
