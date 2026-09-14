import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { MULTISIG_ENCODE_PROPOSAL_PAYLOAD } from "../lib/tasksNames";
import { SpecificGroupStrategy } from "../typechain-types/SpecificGroupStrategy";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const groupHealth = await hre.deployments.get("GroupHealth");
  const defaultStrategy = await hre.deployments.get("DefaultStrategy");
  const specificGroupStrategy: SpecificGroupStrategy = await hre.ethers.getContract(
    "SpecificGroupStrategy"
  );
  const multisig = await hre.deployments.get("MultiSig");

  if ((await specificGroupStrategy.callStatic.owner()) !== multisig.address) {
    await executeAndWait(
      specificGroupStrategy.setDependencies(
        account.address,
        groupHealth.address,
        defaultStrategy.address
      )
    );
  } else {
    console.log(
      chalk.red(
        `SpecificGroupStrategy is already owned by multisig run task ${MULTISIG_ENCODE_PROPOSAL_PAYLOAD} to set dependencies address in SpecificGroupStrategy contract!`
      )
    );
  }
};

func.id = "deploy_set_dependencies_on_allowed_strategy";
func.tags = ["SetDepsOnSpecificGroupStrategy", "core"];
func.dependencies = ["SpecificGroupStrategy", "Account", "GroupHealth", "MultiSig"];
export default func;
