import { DeployFunction, DeployResult } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const namedAccounts = await hre.getNamedAccounts();

  const deployer = namedAccounts.deployer;
  const minDelay = Number(process.env.TIME_LOCK_MIN_DELAY);
  const delay = Number(process.env.TIME_LOCK_DELAY);

  const multisigOwners: string[] = [];
  for (const key in namedAccounts) {
    const res = key.includes("multisigOwner");
    if (res) {
      multisigOwners.push(namedAccounts[key]);
    }
  }

  const requiredConfirmations = Number(process.env.MULTISIG_REQUIRED_CONFIRMATIONS);

  await catchUpgradeErrorInMultisig(
    deploy("MultiSig", {
      from: deployer,
      log: true,
      // minDelay 4 Days, to protect against stakedCelo withdrawals
      args: [minDelay],
      proxy: {
        proxyArgs: ["{implementation}", "{data}"],
        proxyContract: "ERC1967Proxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [multisigOwners, requiredConfirmations, delay],
          },
        },
      },
    })
  );
};

func.id = "deploy_multisig";
func.tags = ["MultiSig", "core", "proxy"];
func.dependencies = [];
export default func;

async function catchUpgradeErrorInMultisig(
  action: Promise<DeployResult> | (() => Promise<DeployResult>)
) {
  try {
    if (action instanceof Promise) {
      await action;
    } else {
      await action();
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (e: any) {
    if (e?.data?.stack?.indexOf("VM Exception while processing transaction: revert")) {
      console.log(
        chalk.red(
          "Transaction was reverted. Most probably it was because caller is not an owner. Please make sure to update the proxy implementation manually."
        )
      );
    } else {
      throw e;
    }
  }
}
