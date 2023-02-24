import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import chalk from "chalk";
import { BigNumber } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { MULTISIG_ENCODE_PROPOSAL_PAYLOAD } from "../lib/tasksNames";
import { ADDRESS_ZERO } from "../test-ts/utils";
import { DefaultStrategy } from "../typechain-types/DefaultStrategy";
import { GroupHealth } from "../typechain-types/GroupHealth";

const parseValidatorGroups = (validatorGroupsString: string | undefined) =>
  validatorGroupsString ? validatorGroupsString.split(",") : [];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const groupHealth = await hre.deployments.get("GroupHealth");
  const groupHealthContract: GroupHealth = await hre.ethers.getContract("GroupHealth");
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

    const validatorGroups = parseValidatorGroups(process.env.VALIDATOR_GROUPS);
    if (validatorGroups.length == 0) {
      return;
    }

    const defaultStrategyContract = await hre.ethers.getContract("DefaultStrategy");
    const accountContract = await hre.ethers.getContract("Account");

    const validatorGroupsWithCelo = await Promise.all(
      validatorGroups.map(async (validatorGroup) => ({
        group: validatorGroup,
        celo: (await accountContract.getCeloForGroup(validatorGroup)) as BigNumber,
      }))
    );

    const validatorGroupsSortedDesc = validatorGroupsWithCelo.sort((a, b) =>
      a.celo.lt(b.celo) ? 1 : -1
    );

    let nextGroup = ADDRESS_ZERO;
    for (let i = 0; i < validatorGroupsSortedDesc.length; i++) {
      const healthy = await groupHealthContract.isGroupValid(validatorGroupsSortedDesc[i].group);
      if (!healthy) {
        console.log(
          chalk.red(
            `Group ${validatorGroupsSortedDesc[i].group} is not healthy - it cannot be activated!`
          )
        );
        continue;
      }
      const activateTx = await defaultStrategyContract.activateGroup(
        validatorGroupsSortedDesc[i].group,
        ADDRESS_ZERO,
        nextGroup
      );
      await activateTx.wait();
      nextGroup = validatorGroupsSortedDesc[i].group;
    }
  } else {
    console.log(
      chalk.red(
        `DefaultStrategy is already owned by multisig run task ${MULTISIG_ENCODE_PROPOSAL_PAYLOAD} to set dependencies addresses and possibly activate groups in DefaultStrategy contract!`
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
