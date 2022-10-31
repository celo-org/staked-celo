import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { Manager } from "../typechain-types/Manager";
import { Account } from "../typechain-types/Account";
import { StakedCelo } from "../typechain-types/StakedCelo";
import { executeAndWait } from "../lib/deploy-utils";
import { Vote } from "../typechain-types/Vote";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const account: Account = await hre.ethers.getContract("Account");
  const stakedCelo: StakedCelo = await hre.ethers.getContract("StakedCelo");
  const manager: Manager = await hre.ethers.getContract("Manager");
  const vote: Vote = await hre.ethers.getContract("Vote");
  const multisig = await hre.deployments.get("MultiSig");

  await executeAndWait(account.transferOwnership(multisig.address));
  await executeAndWait(stakedCelo.transferOwnership(multisig.address));
  await executeAndWait(manager.transferOwnership(multisig.address));
  await executeAndWait(vote.transferOwnership(multisig.address));
};

func.id = "deploy_transfer_to_multisig";
func.tags = ["TransferAllContractsToMultisig", "core"];
func.dependencies = ["Manager", "Account", "StakedCelo", "MultiSig", "Vote"];
export default func;
