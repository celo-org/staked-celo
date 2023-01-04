import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeAndWait } from "../lib/deploy-utils";
import { Vote } from "../typechain-types/Vote";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account = await hre.deployments.get("Account");
  const stakedCelo = await hre.deployments.get("StakedCelo");
  const vote: Vote = await hre.ethers.getContract("Vote");
  const multisig = await hre.deployments.get("MultiSig");

  if ((await vote.callStatic.owner()) !== multisig.address) {
    await executeAndWait(vote.setDependencies(stakedCelo.address, account.address));
  }
};

func.id = "deploy_set_dependencies_on_vote";
func.tags = ["SetDepsOnVote", "core"];
func.dependencies = ["Vote", "Account", "StakedCelo"];
export default func;
