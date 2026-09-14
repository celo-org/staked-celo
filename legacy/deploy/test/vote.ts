import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer, owner } = await hre.getNamedAccounts();

  const manager = await hre.deployments.get("Manager");

  await deploy("Vote", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      owner: owner,
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [hre.ethers.constants.AddressZero, owner, manager.address],
      },
    },
  });
};

func.id = "deploy_test_vote";
func.tags = ["TestVote"];
func.dependencies = ["TestManager"];
export default func;
