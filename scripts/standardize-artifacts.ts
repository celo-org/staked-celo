/* eslint-disable @typescript-eslint/no-explicit-any */
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

  const artifactsAbsolute = path.join(inputDirResolved, artifactDirectory);
  const contractsAbsolute = path.join(artifactsAbsolute, contractsDirectory);

  const contracts = await getContracts(
    path.join(inputDirResolved, artifactDirectory),
    contractsAbsolute
  );

  const buildInfos: Record<string, BuildInfoInterface> = {};
  let allBuildSources: Set<string> = new Set<string>();

  for (const contract of contracts) {
    console.log("Processing", contract.relativePath);

    const dbgString = readFileSync(
      path.join(artifactsAbsolute, contract.relativePath, contract.dbg),
      "utf-8"
    );
    const dbg = JSON.parse(dbgString) as Dbg;
    const buildInfoPath = path.join(artifactsAbsolute, contract.relativePath, dbg.buildInfo);
    contract.buildInfoPath = buildInfoPath;
    if (buildInfos[buildInfoPath] == null) {
      const buildInfoString = readFileSync(buildInfoPath, "utf-8");
      buildInfos[buildInfoPath] = JSON.parse(buildInfoString);
      allBuildSources = new Set([
        ...allBuildSources.values(),
        ...Object.keys(buildInfos[buildInfoPath].output.sources),
      ]);
    }

    const source = buildInfos[buildInfoPath].output.sources[contract.relativePath];
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

  console.log("allBuildSources", JSON.stringify(allBuildSources));

  for (const source of allBuildSources.values()) {
    const contractName = path.parse(source).name;
    const contractInputSource = getInputContractSource(buildInfos, source);
    const contractOutputSource = getOutputContractSource(buildInfos, source);
    const contract = getContract(buildInfos, source);
    const art: ArtifactInterface = {
      contractName: contractName,
      ast: contractOutputSource?.ast,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      abi: (contract?.[contractName].abi as any) ?? [],
      bytecode: "0x",
      deployedBytecode: "0x",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      metadata: (contract?.[contractName].metadata as any) ?? "",
      source: (contractInputSource?.[source]?.content as any) ?? "",
      compiler: {
        name: "solc",
        version: buildInfos[Object.keys(buildInfos)?.[0]].solcVersion,
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

function getInputContractSource(buildInfos: Record<string, BuildInfoInterface>, source: string) {
  for (const key of Object.keys(buildInfos)) {
    if (buildInfos[key].input.sources[source] != null) {
      return buildInfos[key].input.sources[source];
    }
  }
  return undefined;
}

function getOutputContractSource(buildInfos: Record<string, BuildInfoInterface>, source: string) {
  for (const key of Object.keys(buildInfos)) {
    if (buildInfos[key].output.sources[source] != null) {
      return buildInfos[key].output.sources[source];
    }
  }
  return undefined;
}

function getContract(buildInfos: Record<string, BuildInfoInterface>, source: string) {
  for (const key of Object.keys(buildInfos)) {
    if (buildInfos[key].output.contracts[source] != null) {
      return buildInfos[key].output.contracts[source];
    }
  }
  return undefined;
}

function exitOnError(p: Promise<unknown>) {
  p.catch((err) => {
    console.error(`Command Failed`);
    console.error(err);
    process.exit(1);
  });
}
