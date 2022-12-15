import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { readdir } from "node:fs/promises";
import path from "node:path";
import yargs from "yargs";
import {
  ArtifactInterface,
  BuildInfoInterface,
  Contract,
  Dbg,
} from "./standardize-artifacts-interface";

const getContracts = async (artifactsDirectory: string, dirName: string) => {
  let contracts: Contract[] = [];
  const items = await readdir(dirName, { withFileTypes: true });

  for (const item of items) {
    if (item.isDirectory() && item.name.indexOf(".sol") > 0) {
      const contractName = path.parse(item.name);
      const contract: Contract = {
        name: contractName.base,
        relativePath: path.join(dirName, item.name).slice(artifactsDirectory.length + 1),
        dbg: `${contractName.name}.dbg.json`,
        artifact: `${contractName.name}.json`,
      };
      contracts.push(contract);
    } else if (item.isDirectory()) {
      contracts = [
        ...contracts,
        ...(await getContracts(artifactsDirectory, `${dirName}/${item.name}`)),
      ];
    }
  }

  return contracts;
};

const removeFilesInDirectory = (directory: string) => {
  for (const file of readdirSync(directory)) {
    unlinkSync(path.join(directory, file));
  }
};

yargs
  .scriptName("standardizeArtifacts")
  .recommendCommands()
  .demandCommand(1)
  .strict(true)
  .showHelpOnFail(true)
  .command(
    "run",
    "Generates Truffle-like artifacts from HH artifacts",
    (args) =>
      args
        .option("outputDir", { type: "string", description: "Path of output directory" })
        .option("inputDir", { type: "string", description: "Path input directory" }),
    (args) => exitOnError(runCmd(args.outputDir!, args.inputDir!))
  ).argv;

async function runCmd(outputDir: string, inputDir: string) {
  const inputDirResolved = inputDir ? path.resolve(inputDir) : path.resolve(__dirname, "..");
  console.log("repoPath", inputDirResolved);

  const artifactDirectory = "/artifacts";
  const contractsDirectory = "contracts";

  const artifactsPostProcessed = "artifactsPostProcessed";
  const artifactsPostProcessedPath = outputDir
    ? path.resolve(outputDir)
    : path.join(inputDirResolved, artifactsPostProcessed);
  if (existsSync(artifactsPostProcessedPath)) {
    removeFilesInDirectory(artifactsPostProcessedPath);
  } else {
    mkdirSync(artifactsPostProcessedPath);
  }

  const contractsAbsolute = path.join(inputDirResolved, artifactDirectory, contractsDirectory);

  const contracts = await getContracts(
    path.join(inputDirResolved, artifactDirectory),
    contractsAbsolute
  );

  let buildInfo: BuildInfoInterface | undefined;
  let allBuildSources: Set<string> = new Set<string>();

  if (contracts.length > 0) {
    const contract = contracts[0];
    const dbgString = readFileSync(
      path.join(contractsAbsolute, contract.name, contract.dbg),
      "utf-8"
    );
    const dbg = JSON.parse(dbgString) as Dbg;
    const buildInfoString = readFileSync(
      path.join(contractsAbsolute, contract.name, dbg.buildInfo),
      "utf-8"
    );
    buildInfo = JSON.parse(buildInfoString) as BuildInfoInterface;
    allBuildSources = new Set(Object.keys(buildInfo.output.sources));
  }

  for (const contract of contracts) {
    console.log("Processing", contract.relativePath);

    const source = buildInfo!.output.sources[contract.relativePath];
    const artifactString = readFileSync(
      path.join(inputDirResolved, artifactDirectory, contract.relativePath, contract.artifact),
      "utf-8"
    );
    const artifact = JSON.parse(artifactString) as ArtifactInterface;
    artifact.ast = source.ast;
    allBuildSources.delete(contract.relativePath);

    writeFileSync(
      path.join(artifactsPostProcessedPath, `${path.parse(contract.name).name}.json`),
      JSON.stringify(artifact)
    );
  }

  for (const source of allBuildSources.values()) {
    const contractName = path.parse(source).name;
    const art: ArtifactInterface = {
      contractName: contractName,
      ast: buildInfo!.output.sources[source].ast,
      abi: (buildInfo!.output.contracts[source]?.[contractName].abi as any) ?? [],
      bytecode: "0x",
      deployedBytecode: "0x",
      metadata: (buildInfo!.output.contracts[source]?.[contractName].metadata as any) ?? "",
      source: (buildInfo!.input.sources[source]?.content as any) ?? "",
      compiler: {
        name: "solc",
        version: buildInfo!.solcVersion,
      },
    };
    let artPath = path.join(artifactsPostProcessedPath, `${contractName}`);
    while (existsSync(`${artPath}.json`)) {
      artPath += "1";
    }

    writeFileSync(`${artPath}.json`, JSON.stringify(art));
  }

  // This file is a hack because of Solidity compilation
  // check contracts/common/ERC1967Proxy.sol for more info
  unlinkSync(path.join(artifactsPostProcessedPath, "ERC1967Proxy1.json"));

  return null;
}

function exitOnError(p: Promise<unknown>) {
  p.catch((err) => {
    console.error(`Command Failed`);
    console.error(err);
    process.exit(1);
  });
}
