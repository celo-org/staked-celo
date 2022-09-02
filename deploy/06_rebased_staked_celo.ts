import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { getNoDependencies, getNoProxy } from "../lib/deploy-utils";

const noDependencies = getNoDependencies();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const noProxy = getNoProxy();
  const stakedCeloAddress =
    process.env.STAKED_CELO_ADDRESS ?? (await hre.deployments.get("StakedCelo")).address;
  const accountAddress =
    process.env.ACCOUNT_ADDRESS ?? (await hre.deployments.get("Account")).address;
  const multiSigAddress =
    process.env.MULTISIG_ADDRESS ?? (await hre.deployments.get("MultiSig")).address;

  const { deploy } = hre.deployments;

  const { deployer } = await hre.getNamedAccounts();
  const deployment = await deploy("RebasedStakedCelo", {
    from: deployer,
    log: true,
    proxy: noProxy
      ? undefined
      : {
          proxyArgs: ["{implementation}", "{data}"],
          owner: multiSigAddress,
          upgradeIndex: 0,
          proxyContract: "ERC1967Proxy",
          execute: {
            methodName: "initialize",
            args: [stakedCeloAddress, accountAddress, multiSigAddress],
          },
        },
  });
};

func.id = "deploy_rebased_staked_celo";
func.tags = ["RebasedStakedCelo", "core"];
func.dependencies = noDependencies ? undefined : ["StakedCelo", "Account", "MultiSig"];
export default func;
