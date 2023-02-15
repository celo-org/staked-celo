import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { MULTISIG_ENCODE_PROPOSAL_PAYLOAD } from "../lib/tasksNames";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const groupHealth = await hre.deployments.get("GroupHealth");
  const specificGroupStrategy = await hre.deployments.get("SpecificGroupStrategy");
  const defaultStrategy: DefaultStrategy = await hre.ethers.getContract("DefaultStrategy");
  const multisig = await hre.deployments.get("MultiSig");

  if ((await defaultStrategy.callStatic.owner()) !== multisig.address) {
    await executeAndWait(
      defaultStrategy.setDependencies(
        account.address,
        groupHealth.address,
        specificGroupStrategy.address
      )
    );
  } else {
    console.log(
      chalk.red(
        `DefaultStrategy is already owned by multisig run task ${MULTISIG_ENCODE_PROPOSAL_PAYLOAD} to set dependencies address in DefaultStrategy contract!`
      )
    );
  }
};

func.id = "deploy_set_dependencies_on_vote";
func.tags = ["SetDepsOnDefaultStrategy", "core"];
func.dependencies = [
  "DefaultStrategy",
  "Account",
  "GroupHealth",
  "SpecificGroupStrategy",
  "MultiSig",
];
export default func;
