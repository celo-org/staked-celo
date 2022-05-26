import fs from "fs";
import path from "path";
import hre from "hardhat";

/*
 * TODO: See why this doesn't do the job.
 * Hardhat can't give us nice stack traces when transactions
 * revert during core celo contracts that it doesn't know
 * about. So I tried telling it about them, but it hasn't
 * worked out of the box. But maybe there's a miss-match
 * between the bytecode that's in the devchain, and what
 * we get from compiling things fresh.
 * I tried using a couple of differ tags for celo-monorepo,
 * (mainnet-v5, alfajores-v5, iirc) but didn't get far.
 * Everything works but you get things like
 * "Unrecognized contract" in the node, and no solidity
 * stack trace on reverts.
 */
export async function addCompilationResults() {
  const buildInfoPath = path.join("artifacts", "build-info");
  const files = fs.readdirSync(path.join("artifacts", "build-info"));
  await Promise.all(
    files.map(async (file) => {
      const filePath = path.join(buildInfoPath, file);
      const buildInfo = JSON.parse(fs.readFileSync(filePath).toString());
      await hre.ethers.provider.send("hardhat_addCompilationResult", [
        buildInfo["solcVersion"],
        buildInfo["input"],
        buildInfo["output"],
      ]);
    })
  );
}
