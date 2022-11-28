import yargs from "yargs";
import { checkCompatibility } from "../node_modules/@celo/contract-compatibility-check/src/compatibility-check-helper";

yargs
  .scriptName("compare-artifacts")
  .recommendCommands()
  .demandCommand(1)
  .strict(true)
  .showHelpOnFail(true)
  .command(
    "run",
    "Compare solidity artifacts",
    (args) =>
      args
        .option("oldDir", { type: "string", description: "Path of old artifacts directory" })
        .option("newDir", { type: "string", description: "Path of new artifacts directory" }),
    (args) => exitOnError(runCmd(args.oldDir!, args.newDir!))
  ).argv;

async function runCmd(oldDir: string, newDir: string) {
  await checkCompatibility({
    oldArtifactsFolder: oldDir,
    newArtifactsFolder: newDir,
    exclude: null,
    outFile: "compatibilityReport.json",
    reportOnly: false,
    out: (msg) => console.log(msg),
  });
  return null;
}

function exitOnError(p: Promise<unknown>) {
  p.catch((err) => {
    console.error(`Command Failed`);
    console.error(err);
    process.exit(1);
  });
}
