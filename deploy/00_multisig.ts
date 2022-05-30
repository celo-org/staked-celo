import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { DAY } from "../test-ts/utils";
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer, multisigOwner0, multisigOwner1, multisigOwner2 } = await hre.getNamedAccounts();
  // const [deployer] = await ethers.getSigners();
  // console.log(deployer);
  // const owners = ["0x0a692a271DfAf2d36E46f50269c932511B55e871", "0x2B73d814BA2231606f9d856C7C20423915F96711", "0xF4BB4Aa6AAD00E9B660B744736B7092816704CB9Ò"];
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
