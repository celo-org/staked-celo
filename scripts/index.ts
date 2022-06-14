// import fs from "fs-extra";
// import path from "path";
// import yargs from "yargs";
// import { spawn, SpawnOptions } from "child_process";

// import { confirmProposal, doSomething, executeProposal, scheduleProposal } from "../lib/multiSigInterface";

// yargs
//     .scriptName("multisig")
//     .recommendCommands()
//     .demandCommand(1)
//     .strict(true)
//     .showHelpOnFail(true)
//     .command(
//         "confirmProposal <proposalId>",
//         "Create a new tarball that includes the deployed staked CELO contracts",
//         (args) =>
//             args
//                 .positional("proposalId", { type: "number", description: "Id of proposal to confirm" })
//                 // .positional("monorepo", { type: "string", description: "Path to monorepo" })
//                 .option("network", {
//                     type: "string",
//                     description: "Filename of output tarball (default: stakedCeloDevchain.tar.gz)",
//                 }),
//         (args) =>
//             exitOnError(
//                 confirmProposal(args.proposalId!)
//                 // runCmd(
//                 //     args.datadir!,
//                 //     args.filename != ("" || undefined) ? args.filename : "stakedCeloDevchain.tar.gz",
//                 //     args.monorepo!
//                 // )
//             )
//     )
//     .command(
//         "executeProposal <proposalId>",
//         "Create a new tarball that includes the deployed staked CELO contracts",
//         (args) =>
//             args
//                 .positional("proposalId", { type: "number", description: "Path to devchain data directory" })
//                 // .positional("monorepo", { type: "string", description: "Path to monorepo" })
//                 .option("network", {
//                     type: "string",
//                     description: "RPC network to connect to",
//                 }),
//         (args) =>
//             exitOnError(
//                 executeProposal(args.proposalId!)
//                 // doSomething()
//                 // runCmd(
//                 //     args.datadir!,
//                 //     args.filename != ("" || undefined) ? args.filename : "stakedCeloDevchain.tar.gz",
//                 //     args.monorepo!
//                 // )
//             )
//     )
//     .command(
//         "scheduleProposal <proposalId>",
//         "Create a new tarball that includes the deployed staked CELO contracts",
//         (args) =>
//             args
//                 .positional("proposalId", { type: "number", description: "Path to devchain data directory" }),
//         // .positional("monorepo", { type: "string", description: "Path to monorepo" })
//         // .option("filename", {
//         //     type: "string",
//         //     description: "Filename of output tarball (default: stakedCeloDevchain.tar.gz)",
//         // }),
//         (args) =>
//             exitOnError(
//                 scheduleProposal(0)
//             )
//     )
//     .argv;

// function runCmd(proposalId: string, network: string, monorepo: string) {
//     // const chainDataDir = "chainData/";
//     // const deploymentsDir = "deployments/local";

//     // fs.copySync(deploymentsDir, chainDataDir + deploymentsDir);
//     const cmdArgs = ["hardhat", "run", "--network", network, "run", proposalId,];
//     // const ProtocolRoot = path.normalize(path.join(__dirname, `../${monorepo}/packages/protocol`));

//     return execCmd(`yarn`, cmdArgs);
// }

// export function execCmd(
//     cmd: string,
//     args: string[],
//     options?: SpawnOptions & { silent?: boolean }
// ) {
//     return new Promise<number>(async (resolve, reject) => {
//         const { silent, ...spawnOptions } = options || { silent: false };
//         if (!silent) {
//             console.debug("$ " + [cmd].concat(args).join(" "));
//         }
//         const process = spawn(cmd, args, {
//             ...spawnOptions,
//             stdio: silent ? "ignore" : "inherit",
//         });
//         process.on("close", (code) => {
//             try {
//                 resolve(code!);
//             } catch (error) {
//                 reject(error);
//             }
//         });
//     });
// }

// function exitOnError(p: Promise<unknown>) {
//     p.catch((err) => {
//         console.error(`Command Failed`);
//         console.error(err);
//         process.exit(1);
//     });
// }
