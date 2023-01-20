import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer, owner } = await hre.getNamedAccounts();
  const managerAddress = (await hre.deployments.get("Manager")).address;

  const lib = await hre.ethers.getContractFactory("AddressSortedLinkedList");
  const libInstance = await lib.deploy();
  await libInstance.deployed();
  console.log("Library Address--->" + libInstance.address)


  await deploy("MockDefaultStrategyFull", {
    from: deployer,
    log: true,
    libraries: { AddressSortedLinkedList: libInstance.address },
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      owner: owner,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [hre.ethers.constants.AddressZero, deployer, managerAddress],
      },
    },
  });
};

func.id = "deploy_test_default_strategy";
func.tags = ["FullTestManager", "TestDefaultStrategy"];
func.dependencies = ["TestManager"];
export default func;
