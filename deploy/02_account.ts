import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const managerAddress = (await hre.deployments.get("Manager")).address;
  const { deployer } = await hre.getNamedAccounts();
  const deployment = await deploy("Account", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      proxyContract: "ERC1967Proxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [hre.ethers.constants.AddressZero, managerAddress, deployer],
        },
      },
    },
  });
};

func.id = "deploy_account";
func.tags = ["Account", "core"];
func.dependencies = ["MultiSig", "Manager"];
export default func;
