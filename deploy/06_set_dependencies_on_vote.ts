import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { Vote } from "../typechain-types/Vote";
import { executeAndWait } from "../lib/deploy-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const stakedCelo = await hre.deployments.get("StakedCelo");
  const vote: Vote = await hre.ethers.getContract("Vote");
  await executeAndWait(vote.setDependencies(stakedCelo.address, account.address));
};

func.id = "deploy_set_dependencies_on_vote";
func.tags = ["SetDepsOnVote", "core"];
func.dependencies = ["Vote", "Account", "StakedCelo"];
export default func;
