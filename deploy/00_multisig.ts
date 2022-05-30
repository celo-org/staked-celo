import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { DAY } from "../test-ts/utils";
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer, multisigOwner0, multisigOwner1, multisigOwner2 } = await hre.getNamedAccounts();
  const owners = [multisigOwner0, multisigOwner1, multisigOwner2];
  const deployment = await deploy("MultiSig", {
    from: deployer,
    log: true,
    // minDelay 4 Days, to protect against stakedCelo withdrawals
    args: [4 * DAY],
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [owners, 2, 7 * DAY],
      },
    },
  });
};

func.id = "deploy_multisig";
func.tags = ["MultiSig", "core"];
func.dependencies = [];
export default func;
