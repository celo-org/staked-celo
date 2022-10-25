import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { Manager } from "../typechain-types/Manager";
import { executeAndWait } from "../lib/deploy-utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const vote = await hre.deployments.get("Vote");
  const manager: Manager = await hre.ethers.getContract("Manager");
  await executeAndWait(manager.setVoteContract(vote.address));
};

func.id = "deploy_set_voteContract";
func.tags = ["SetVoteOnStakedCelo", "core"];
func.dependencies = ["Vote", "StakedCelo"];
export default func;
