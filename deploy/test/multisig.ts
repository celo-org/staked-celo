import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { DAY } from "../../test-ts/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer, multisigOwner0, multisigOwner1 } = await hre.getNamedAccounts();
  const owners = [multisigOwner0, multisigOwner1];

  const deployment = await deploy("MultiSig", {
    from: deployer,
    log: true,
    args: [3 * DAY],
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

func.id = "deploy_test_multisig";
func.tags = ["TestMultiSig"];
func.dependencies = [];
export default func;
