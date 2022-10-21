import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { StakedCelo } from "../typechain-types/StakedCelo";
import { executeAndWait } from "../lib/deploy-utils";
import { Account } from "../typechain-types/Account";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const vote = await hre.deployments.get("Vote");
  const stakedCelo: StakedCelo = await hre.ethers.getContract("StakedCelo");
  const account: Account = await hre.ethers.getContract("Account");
  await executeAndWait(stakedCelo.setVoteContract(vote.address));
  await executeAndWait(account.setVoteContract(vote.address));
};

func.id = "deploy_set_voteContract";
func.tags = ["SetVoteOnStakedCelo", "core"];
func.dependencies = ["Vote", "StakedCelo"];
export default func;
