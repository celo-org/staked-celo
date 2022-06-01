import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { DAY } from "../test-ts/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  // Get a list the named accounts based on network
  const namedAccounts = await hre.getNamedAccounts();

  const deployer = namedAccounts.deployer;
  const minDelay = Number(process.env.TIME_LOCK_MIN_DELAY);
  const delay = Number(process.env.TIME_LOCK_DELAY);

  console.log(deployer, minDelay, delay);

  // Since we can't get specific named accounts, we remove those we have gotten their value, so that
  // we now have only the multisig left.
  delete namedAccounts["deployer"];

  const multisigOwners = Object.values(namedAccounts);
  const requiredConfirmations = multisigOwners.length > 1 ? multisigOwners.length - 1 : 1;

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
