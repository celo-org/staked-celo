import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { DAY } from "../test-ts/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const namedAccounts = await hre.getNamedAccounts();

  const deployer = namedAccounts.deployer;
  const minDelay = Number(process.env.TIME_LOCK_MIN_DELAY);
  const delay = Number(process.env.TIME_LOCK_DELAY);

  let multisigOwners: string[] = [];
  for (let key in namedAccounts) {
    var res = key.includes("multisigOwner");
    if (res) {
      multisigOwners.push(namedAccounts[key]);
    }
  }

  const requiredConfirmations = Number(process.env.MULTISIG_REQUIRED_CONFIRMATIONS);

  const deployment = await deploy("MultiSig", {
    from: deployer,
    log: true,
    // minDelay 4 Days, to protect against stakedCelo withdrawals
    args: [minDelay * DAY],
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [multisigOwners, requiredConfirmations, delay * DAY],
      },
    },
  });
};

func.id = "deploy_multisig";
func.tags = ["MultiSig", "core"];
func.dependencies = [];
export default func;
