import fs from "fs-extra";
import path from "path";
import yargs from "yargs";
import { spawn, SpawnOptions } from "child_process";

yargs
  .scriptName("tarchain")
  .recommendCommands()
  .demandCommand(1)
  .strict(true)
  .showHelpOnFail(true)
  .command(
    "run <datadir> <monorepo>",
    "Create a new tarball that includes the deployed staked CELO contracts",
    (args) =>
      args
        .positional("datadir", { type: "string", description: "Path to devchain data directory" })
        .positional("monorepo", { type: "string", description: "Path to monorepo" })
        .option("filename", {
          type: "string",
          description: "Filename of output tarball (default: stakedCeloDevchain.tar.gz)",
        }),
    (args) =>
      exitOnError(
        runCmd(
          args.datadir!,
          args.filename != ("" || undefined) ? args.filename : "stakedCeloDevchain.tar.gz",
          args.monorepo!
        )
      )
  ).argv;

function runCmd(datadir: string, filename: string, monorepo: string) {
  const chainDataDir = "chainData/";
  const deploymentsDir = "deployments/local";

  fs.copySync(deploymentsDir, chainDataDir + deploymentsDir);
  const cmdArgs = ["devchain", "compress-chain", datadir, chainDataDir + filename];
  const ProtocolRoot = path.normalize(path.join(__dirname, `../${monorepo}/packages/protocol`));

  return execCmd(`yarn`, cmdArgs, { cwd: ProtocolRoot });
}

export function execCmd(
  cmd: string,
  args: string[],
  options?: SpawnOptions & { silent?: boolean }
) {
  return new Promise<number>(async (resolve, reject) => {
    const { silent, ...spawnOptions } = options || { silent: false };
    if (!silent) {
      console.debug("$ " + [cmd].concat(args).join(" "));
    }
    const process = spawn(cmd, args, {
      ...spawnOptions,
      stdio: silent ? "ignore" : "inherit",
    });
    process.on("close", (code) => {
      try {
        resolve(code!);
      } catch (error) {
        reject(error);
      }
    });
  });
}

function exitOnError(p: Promise<unknown>) {
  p.catch((err) => {
    console.error(`Command Failed`);
    console.error(err);
    process.exit(1);
  });
}
