import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { catchNotOwnerForProxy } from "../lib/deploy-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  // Fetch deployed library
  let addressSortedLinkedListAddress;
  const defaultStrategyImplementationContract = await hre.deployments.getOrNull(
    "DefaultStrategy_Implementation"
  );

  if (defaultStrategyImplementationContract == null) {
    // Library deployment
    const lib = await hre.ethers.getContractFactory("AddressSortedLinkedList");
    const libInstance = await lib.deploy();
    await libInstance.deployed();
    addressSortedLinkedListAddress = libInstance.address;
  } else {
    // Reuse deployed library
    const defaultStrategyLibraries = defaultStrategyImplementationContract.libraries!;
    addressSortedLinkedListAddress = defaultStrategyLibraries["AddressSortedLinkedList"];
  }

  const managerAddress = (await hre.deployments.get("Manager")).address;
  await catchNotOwnerForProxy(
    deploy("DefaultStrategy", {
      from: deployer,
      log: true,
      libraries: { AddressSortedLinkedList: addressSortedLinkedListAddress },
      proxy: {
        proxyArgs: ["{implementation}", "{data}"],
        proxyContract: "ERC1967Proxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [deployer, managerAddress],
          },
        },
      },
    })
  );
};

func.id = "deploy_default_strategy";
func.tags = ["DefaultStrategy", "core", "proxy"];
func.dependencies = ["MultiSig"];
export default func;
