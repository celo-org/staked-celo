#!/usr/bin/env node
// Verifies that the Foundry build produces the same bytecode as a reference build.
// DESCRIPTION below is the full explanation and is what --help prints.

import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));

const PROG = "bytecode-compat-check.ts";

// Only the project's own contracts are pinned; library and test sources pulled in by
// the build are not part of the deployed surface.
const REFERENCE_SOURCE_PREFIX = "contracts/";

// Copied verbatim into the reference file, so --update-reference reproduces the checked-in
// scripts/bytecode-reference.json byte for byte. Only change this text in a commit that
// regenerates that file as well.
const REFERENCE_COMMENT =
  "Digests of the creation and runtime bytecode of every contract under " +
  "contracts/. Regenerate with `forge build && scripts/bytecode-compat-check.ts " +
  "--update-reference scripts/bytecode-reference.json` whenever a contract change " +
  "is intended, and review the resulting diff as carefully as the contract change.";

const REFERENCE_ALGORITHM = "sha256 of the lowercase hex digits, without the 0x prefix";

const DESCRIPTION = [
  "Verifies that the Foundry build produces the same bytecode as a reference build.",
  "",
  "The production contracts must keep compiling to exactly the bytecode Hardhat produced",
  "(solc 0.8.11, evm istanbul, optimizer off, literal metadata content). Three references",
  "are supported:",
  "",
  "  --reference FILE          Checked-in digests of every contract's creation and runtime",
  "                            bytecode (scripts/bytecode-reference.json). This is the check",
  "                            CI runs: it needs no Hardhat install, and it fails as soon as",
  "                            a contract or a compiler setting changes, because the solc",
  "                            settings are hashed into the metadata trailer. Regenerate it",
  "                            with --update-reference when a contract change is intended.",
  "",
  "  --hardhat-artifacts DIR   Hardhat `artifacts/contracts` directory, produced by the frozen",
  "                            toolchain, kept in git history before the Foundry migration. Every contract is compared on both",
  "                            creation and runtime bytecode. This is the strict check that",
  "                            originally proved the Foundry build reproduces the Hardhat one.",
  "",
  "  --deployments NETWORK     `deployments/<NETWORK>/*_Implementation.json` produced by",
  "                            hardhat-deploy. Only informational: implementations on chain",
  "                            may predate the current sources.",
  "",
  "For the two artifact-based modes the comparison is reported twice: on the full bytecode",
  "and with the CBOR metadata trailer stripped (the trailer only carries the metadata hash).",
  "",
  "Exit status is non-zero when a strict comparison finds a difference.",
].join("\n");

const USAGE = [
  `usage: ${PROG} [-h] [--reference REFERENCE]`,
  "                                [--update-reference UPDATE_REFERENCE]",
  "                                [--hardhat-artifacts HARDHAT_ARTIFACTS]",
  "                                [--deployments DEPLOYMENTS] [--out OUT]",
].join("\n");

const OPTIONS_HELP = [
  "options:",
  "  -h, --help            show this help message and exit",
  "  --reference REFERENCE",
  "                        checked-in bytecode digests to verify against (strict)",
  "  --update-reference UPDATE_REFERENCE",
  "                        regenerate the digest file from the current build",
  "  --hardhat-artifacts HARDHAT_ARTIFACTS",
  "                        Hardhat artifacts/contracts directory (strict)",
  "  --deployments DEPLOYMENTS",
  "                        network name under deployments/ (informational)",
  "  --out OUT             Foundry out directory",
].join("\n");

/** One report line: source, contract, and the two comparison verdicts. */
export type Row = readonly [source: string, contract: string, full: string, stripped: string];

/** The creation and runtime bytecode of a Foundry artifact, hex without the 0x prefix. */
export type ForgeBytecode = readonly [creation: string, runtime: string];

export interface Digests {
  creation: string;
  runtime: string;
}

export interface Reference {
  comment: string;
  algorithm: string;
  contracts: Record<string, Digests>;
}

export interface ForgeArtifactJson {
  bytecode?: { object?: string };
  deployedBytecode?: { object?: string };
  metadata?: { settings?: { compilationTarget?: Record<string, string> } };
}

export interface HardhatArtifactJson {
  contractName: string;
  sourceName: string;
  bytecode?: string;
  deployedBytecode?: string;
}

/** A contract of the default compiler profile, as found under the Foundry out directory. */
export interface DefaultArtifact {
  source: string;
  contract: string;
  artifact: ForgeArtifactJson;
}

type ExitError = Error & { exitCode: number };

function exitError(exitCode: number, message: string): ExitError {
  return Object.assign(new Error(message), { exitCode });
}

function usageError(message: string): ExitError {
  return exitError(2, `${USAGE}\n${PROG}: error: ${message}`);
}

function isExitError(value: unknown): value is ExitError {
  return value instanceof Error && typeof (value as { exitCode?: unknown }).exitCode === "number";
}

/** Sorts by code point (locale independent). */
function byCodePoint(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function readJson(path: string): unknown {
  return JSON.parse(readFileSync(path, "utf8"));
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

/** Walks `dir` top-down, yielding every directory with its file names sorted. */
function* walk(
  dir: string,
  skipDirs: ReadonlySet<string> = new Set<string>()
): Generator<{ dir: string; files: string[] }> {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  const files = entries
    .filter((entry) => !entry.isDirectory())
    .map((entry) => entry.name)
    .sort(byCodePoint);
  yield { dir, files };
  const subdirectories = entries
    .filter((entry) => entry.isDirectory() && !skipDirs.has(entry.name))
    .map((entry) => entry.name)
    .sort(byCodePoint);
  for (const name of subdirectories) {
    yield* walk(join(dir, name), skipDirs);
  }
}

export function norm(hexstr: string): string {
  return hexstr.startsWith("0x") ? hexstr.slice(2) : hexstr;
}

export function stripMetadata(hexstr: string): string {
  const code = norm(hexstr);
  if (code.length < 4) {
    return code;
  }
  const length = Number.parseInt(code.slice(-4), 16);
  if (!Number.isFinite(length)) {
    throw new Error(`bytecode does not end in a CBOR metadata length: ${code.slice(-4)}`);
  }
  return code.slice(0, -(length + 2) * 2);
}

export function forgeArtifact(
  outDir: string,
  sourceName: string,
  contractName: string
): ForgeBytecode | null {
  const path = join(outDir, basename(sourceName), `${contractName}.json`);
  if (!existsSync(path)) {
    return null;
  }
  const artifact = readJson(path) as ForgeArtifactJson;
  return [norm(artifact.bytecode?.object ?? ""), norm(artifact.deployedBytecode?.object ?? "")];
}

/** Compares on the full bytecode and again with the CBOR metadata trailer stripped. */
export function compare(
  referenceCreation: string,
  referenceRuntime: string,
  forgeCreation: string,
  forgeRuntime: string
): readonly [full: boolean, stripped: boolean] {
  const full = referenceCreation === forgeCreation && referenceRuntime === forgeRuntime;
  const stripped =
    stripMetadata(referenceCreation) === stripMetadata(forgeCreation) &&
    stripMetadata(referenceRuntime) === stripMetadata(forgeRuntime);
  return [full, stripped];
}

/** Every *.json under `dir`, recursively, in code point order. */
function jsonFilesRecursive(dir: string): string[] {
  const found: string[] = [];
  for (const entry of walk(dir)) {
    for (const file of entry.files) {
      if (file.startsWith(".") || !file.endsWith(".json")) {
        continue;
      }
      found.push(join(entry.dir, file));
    }
  }
  return found.sort(byCodePoint);
}

export function checkHardhat(artifactsDir: string, outDir: string): number {
  let failures = 0;
  const rows: Row[] = [];
  for (const path of jsonFilesRecursive(artifactsDir)) {
    if (path.endsWith(".dbg.json")) {
      continue;
    }
    const artifact = readJson(path) as HardhatArtifactJson;
    if (!artifact.bytecode || artifact.bytecode === "0x") {
      continue; // abstract contract, interface or library without code
    }
    const { contractName: name, sourceName: source } = artifact;
    const forge = forgeArtifact(outDir, source, name);
    if (forge === null) {
      rows.push([source, name, "MISSING", "MISSING"]);
      failures += 1;
      continue;
    }
    const [full, stripped] = compare(
      norm(artifact.bytecode),
      norm(artifact.deployedBytecode ?? ""),
      forge[0],
      forge[1]
    );
    rows.push([source, name, full ? "ok" : "DIFF", stripped ? "ok" : "DIFF"]);
    if (!full) {
      failures += 1;
    }
  }
  printTable("Hardhat artifacts vs Foundry", rows);
  return failures;
}

function implementationFiles(dir: string): string[] {
  let names: string[];
  try {
    names = readdirSync(dir);
  } catch {
    return [];
  }
  return names
    .filter((name) => !name.startsWith(".") && name.endsWith("_Implementation.json"))
    .map((name) => join(dir, name))
    .sort(byCodePoint);
}

export function checkDeployments(network: string, outDir: string): number {
  const rows: Row[] = [];
  for (const path of implementationFiles(join(ROOT, "deployments", network))) {
    const name = basename(path).replace("_Implementation.json", "");
    const deployment = readJson(path) as { deployedBytecode?: string };
    const forge = forgeArtifact(outDir, `${name}.sol`, name);
    if (forge === null) {
      rows.push([network, name, "MISSING", "MISSING"]);
      continue;
    }
    const runtime = norm(deployment.deployedBytecode ?? "");
    const full = runtime === forge[1];
    const stripped = stripMetadata(runtime) === stripMetadata(forge[1]);
    rows.push([network, name, full ? "ok" : "DIFF", stripped ? "ok" : "DIFF"]);
  }
  printTable(`deployments/${network} implementations vs Foundry (informational)`, rows);
  return 0;
}

/** sha256 of the lowercase hex digits of the bytecode, without the 0x prefix. */
export function digest(hexstr: string): string {
  return createHash("sha256").update(norm(hexstr).toLowerCase(), "utf8").digest("hex");
}

/**
 * Yields the artifacts of the default compiler profile.
 *
 * Foundry names the artifact <Contract>.json, or <Contract>.default.json when the
 * contract is also built under one of the additional_compiler_profiles. Artifacts
 * of the other profiles (<Contract>.test-via-ir.json) never ship on chain.
 */
export function* iterDefaultArtifacts(outDir: string): Generator<DefaultArtifact> {
  for (const { dir, files } of walk(outDir, new Set(["build-info"]))) {
    for (const filename of files) {
      if (!filename.endsWith(".json")) {
        continue;
      }
      const stem = filename.slice(0, -".json".length);
      const dot = stem.indexOf(".");
      const name = dot === -1 ? stem : stem.slice(0, dot);
      const profile = dot === -1 ? "" : stem.slice(dot + 1);
      if (profile && (profile !== "default" || files.includes(`${name}.json`))) {
        continue;
      }
      const artifact = readJson(join(dir, filename)) as ForgeArtifactJson;
      const target = artifact.metadata?.settings?.compilationTarget;
      const entry = target === undefined ? undefined : Object.entries(target)[0];
      if (entry === undefined) {
        continue;
      }
      yield { source: entry[0], contract: entry[1], artifact };
    }
  }
}

/** Yields the project's contracts that have code. */
export function* iterContracts(outDir: string): Generator<DefaultArtifact> {
  for (const found of iterDefaultArtifacts(outDir)) {
    if (!found.source.startsWith(REFERENCE_SOURCE_PREFIX)) {
      continue;
    }
    if (!norm(found.artifact.bytecode?.object ?? "")) {
      continue; // abstract contract or interface
    }
    yield found;
  }
}

export function buildReference(outDir: string): Reference {
  const contracts: Record<string, Digests> = {};
  for (const { source, contract, artifact } of iterContracts(outDir)) {
    contracts[`${source}:${contract}`] = {
      creation: digest(artifact.bytecode?.object ?? ""),
      runtime: digest(artifact.deployedBytecode?.object ?? ""),
    };
  }
  const sorted: Record<string, Digests> = {};
  for (const key of Object.keys(contracts).sort(byCodePoint)) {
    sorted[key] = contracts[key] as Digests;
  }
  return { comment: REFERENCE_COMMENT, algorithm: REFERENCE_ALGORITHM, contracts: sorted };
}

/** Serializes a reference exactly the way the checked-in file is written. */
export function serializeReference(reference: Reference): string {
  return `${JSON.stringify(reference, null, 2)}\n`;
}

export function updateReference(path: string, outDir: string): void {
  const reference = buildReference(outDir);
  writeFileSync(path, serializeReference(reference));
  console.log(`wrote ${Object.keys(reference.contracts).length} contract digests to ${path}`);
}

export function checkReference(path: string, outDir: string): number {
  if (!existsSync(path)) {
    throw exitError(1, `reference not found: ${path} (create it with --update-reference)`);
  }
  const expected = (readJson(path) as Reference).contracts;
  const current = buildReference(outDir).contracts;

  let failures = 0;
  const rows: Row[] = [];
  const keys = [...new Set([...Object.keys(expected), ...Object.keys(current)])].sort(byCodePoint);
  for (const key of keys) {
    const separator = key.lastIndexOf(":");
    const source = key.slice(0, separator);
    const name = key.slice(separator + 1);
    const want = expected[key];
    const have = current[key];
    if (want === undefined) {
      rows.push([source, name, "UNPINNED", "UNPINNED"]);
      failures += 1;
      continue;
    }
    if (have === undefined) {
      rows.push([source, name, "MISSING", "MISSING"]);
      failures += 1;
      continue;
    }
    const creation = want.creation === have.creation;
    const runtime = want.runtime === have.runtime;
    rows.push([source, name, creation ? "ok" : "DIFF", runtime ? "ok" : "DIFF"]);
    if (!(creation && runtime)) {
      failures += 1;
    }
  }
  printTable(`${relative(ROOT, resolve(path))} vs Foundry`, rows, ["creation", "runtime"]);
  if (failures) {
    console.log(
      "\nUNPINNED means the contract is not in the reference yet, MISSING means the " +
        "reference has a contract the build does not produce." +
        "\nIf the change is intended, rerun with --update-reference to refresh the reference."
    );
  }
  return failures;
}

export function printTable(
  title: string,
  rows: readonly Row[],
  columns: readonly [string, string] = ["full", "no-metadata"]
): void {
  console.log(`\n${title}`);
  if (rows.length === 0) {
    console.log("  (nothing to compare)");
    return;
  }
  const width = Math.max(...rows.map((row) => row[0].length));
  console.log(
    `  ${"source".padEnd(width)}  ${"contract".padEnd(28)} ${columns[0].padEnd(8)} ${columns[1]}`
  );
  for (const [source, name, full, stripped] of rows) {
    console.log(`  ${source.padEnd(width)}  ${name.padEnd(28)} ${full.padEnd(8)} ${stripped}`);
  }
}

interface Args {
  reference?: string;
  updateReference?: string;
  hardhatArtifacts?: string;
  deployments?: string;
  out: string;
  help: boolean;
}

export function parseArgs(argv: readonly string[]): Args {
  const args: Args = { out: join(ROOT, "out"), help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index] ?? "";
    if (token === "-h" || token === "--help") {
      args.help = true;
      continue;
    }
    const equals = token.indexOf("=");
    const flag = equals === -1 ? token : token.slice(0, equals);
    let value = equals === -1 ? undefined : token.slice(equals + 1);
    if (
      ![
        "--reference",
        "--update-reference",
        "--hardhat-artifacts",
        "--deployments",
        "--out",
      ].includes(flag)
    ) {
      throw usageError(`unrecognized arguments: ${token}`);
    }
    if (value === undefined) {
      index += 1;
      if (index >= argv.length) {
        throw usageError(`argument ${flag}: expected one argument`);
      }
      value = argv[index] ?? "";
    }
    if (flag === "--reference") {
      args.reference = value;
    } else if (flag === "--update-reference") {
      args.updateReference = value;
    } else if (flag === "--hardhat-artifacts") {
      args.hardhatArtifacts = value;
    } else if (flag === "--deployments") {
      args.deployments = value;
    } else {
      args.out = value;
    }
  }
  return args;
}

function run(argv: readonly string[]): number {
  const args = parseArgs(argv);
  if (args.help) {
    console.log(`${USAGE}\n\n${DESCRIPTION}\n\n${OPTIONS_HELP}`);
    return 0;
  }
  if (!(args.reference || args.updateReference || args.hardhatArtifacts || args.deployments)) {
    throw usageError(
      "pass --reference, --update-reference, --hardhat-artifacts and/or --deployments"
    );
  }
  if (!isDirectory(args.out)) {
    throw exitError(1, `Foundry out directory not found: ${args.out} (run \`forge build\` first)`);
  }

  if (args.updateReference) {
    updateReference(args.updateReference, args.out);
    return 0;
  }

  let failures = 0;
  if (args.reference) {
    failures += checkReference(args.reference, args.out);
  }
  if (args.hardhatArtifacts) {
    failures += checkHardhat(args.hardhatArtifacts, args.out);
  }
  if (args.deployments) {
    failures += checkDeployments(args.deployments, args.out);
  }

  if (failures) {
    console.log(`\n${failures} contract(s) differ from the reference build`);
    return 1;
  }
  console.log("\nbytecode matches the reference build");
  return 0;
}

/** Runs the CLI and returns the process exit status. */
export function main(argv: readonly string[]): number {
  try {
    return run(argv);
  } catch (error) {
    if (isExitError(error)) {
      console.error(error.message);
      return error.exitCode;
    }
    throw error;
  }
}

const invoked = process.argv[1];
if (invoked !== undefined && import.meta.url === pathToFileURL(resolve(invoked)).href) {
  process.exitCode = main(process.argv.slice(2));
}
