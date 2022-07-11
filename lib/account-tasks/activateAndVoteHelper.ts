import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export async function activateAndvote(hre: HardhatRuntimeEnvironment) {
  const accountContract = await hre.ethers.getContract("Account");
  const ManagerContract = await hre.ethers.getContract("Manager");

  let electionWrapper;

  electionWrapper = await hre.kit.contracts.getElection();

  const groupList = await ManagerContract.getGroups();
  console.log("groups:", groupList);

  for (var group of groupList) {
    const amountScheduled = await accountContract.scheduledVotesForGroup(group);

    console.log(`amount scheduled for group ${group}:`, amountScheduled.toString());

    if (amountScheduled > hre.ethers.BigNumber.from(0)) {
      var { lesser, greater } = await electionWrapper.findLesserAndGreaterAfterVote(
        group,
        amountScheduled.toString()
      );

      console.log(chalk.red("lesser:", lesser));
      console.log("current group:", group);
      console.log(chalk.green("greater:", greater));

      const tx = await accountContract.activateAndVote(group, lesser, greater);

      const receipt = await tx.wait();
      console.log(chalk.yellow("receipt events", receipt.events));
      //TODO: parse events emmitted?
    }
  }
}
