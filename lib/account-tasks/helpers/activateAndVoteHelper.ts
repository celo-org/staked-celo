import chalk from "chalk";
import { Signer } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export async function activateAndVote(hre: HardhatRuntimeEnvironment, signer: Signer) {
  const accountContract = await hre.ethers.getContract("Account");
  const managerContract = await hre.ethers.getContract("Manager");

  const electionWrapper = await hre.kit.contracts.getElection();
  const electionContract = await hre.ethers.getContractAt("IElection", electionWrapper.address);

  const activeGroups = await managerContract.getGroups();
  const allowedStrategies: [] = await managerContract.getAllowedStrategies();
  const groupList = new Set<string>(activeGroups.concat(allowedStrategies)).values();
  console.log("groups:", groupList);

  for (const group of groupList) {
    // Using election contract to make this `hasActivatablePendingVotes` call.
    // This allows to check activatable pending votes for a specified group,
    // as opposed to using the `ElectionWrapper.hasActivatablePendingVotes`
    // which checks if account has activatable pending votes from any group.
    const canActivateForGroup = await electionContract.hasActivatablePendingVotes(
      accountContract.address,
      group
    );
    const amountScheduled = await accountContract.scheduledVotesForGroup(group);
    console.log(chalk.yellow("current group:"), group);
    console.log(chalk.yellow(`can activate for group:`), canActivateForGroup);
    console.log(chalk.yellow(`amount scheduled for group:`), amountScheduled.toString());

    if (amountScheduled > hre.ethers.BigNumber.from(0) || canActivateForGroup) {
      const { lesser, greater } = await electionWrapper.findLesserAndGreaterAfterVote(
        group,
        amountScheduled.toString()
      );

      console.log(chalk.red("lesser:"), lesser);

      console.log(chalk.green("greater:"), greater);

      const tx = await accountContract.connect(signer).activateAndVote(group, lesser, greater);

      const receipt = await tx.wait();
      console.log(chalk.yellow("receipt status"), receipt.status);
    }
  }
}
