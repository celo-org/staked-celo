import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const stakedCelo = await hre.deployments.get("StakedCelo");
  const account = await hre.deployments.get("Account");
  const multiSig = await hre.deployments.get("MultiSig");

  const { deploy } = hre.deployments;

  const { deployer } = await hre.getNamedAccounts();
  const deployment = await deploy("RebasedStakedCelo", {
    from: deployer,
    log: true,
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      owner: multiSig.address,
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [stakedCelo.address, account.address, multiSig.address],
      },
    },
  });
};

func.id = "deploy_rebased_staked_celo";
func.tags = ["RebasedStakedCelo", "core"];
func.dependencies = ["StakedCelo", "Account", "MultiSig"];
export default func;
