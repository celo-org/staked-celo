import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { catchNotOwnerForProxy, executeAndWait } from "../lib/deploy-utils";
import { VoteValue } from "@celo/contractkit/lib/wrappers/Governance";

const parseValidatorGroups = (validatorGroupsString: string | undefined) =>
  validatorGroupsString ? validatorGroupsString.split(",") : [];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const isVoteAlreadyDeployed = await hre.deployments.getOrNull("Vote");

  const managerAddress = (await hre.deployments.get("Manager")).address;
  const deployment = await catchNotOwnerForProxy(
    deploy("Vote", {
      from: deployer,
      log: true,
      proxy: {
        proxyArgs: ["{implementation}", "{data}"],
        proxyContract: "ERC1967Proxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [hre.ethers.constants.AddressZero, deployer, managerAddress],
          },
        },
      },
    })
  );

  if (isVoteAlreadyDeployed) {
    console.log("Vote proxy was already deployed - skipping group activation");
    return;
  }

  const governance = await hre.kit.contracts.getGovernance();
  const stageDurations = await governance.stageDurations();
  const referendumDuration = stageDurations.Referendum;
  const vote = await hre.ethers.getContract("Vote");
  console.log("setting referendum duration to ", referendumDuration.toString());
  await executeAndWait(vote.setReferendumDuration(referendumDuration));
};

func.id = "deploy_vote";
func.tags = ["Vote", "core", "proxy"];
func.dependencies = ["MultiSig"];
export default func;
