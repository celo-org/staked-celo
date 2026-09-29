#!/usr/bin/env node
// Verifies that the Foundry build produces the same bytecode as a reference build.
// DESCRIPTION below is the full explanation and is what --help prints.

import { execFileSync } from "node:child_process";
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
  "The production contracts must keep compiling to exactly the bytecode that was audited and",
  "deployed (solc 0.8.11, evm istanbul, optimizer off, literal metadata content). Two",
  "references are supported:",
  "",
  "  --reference FILE          Checked-in digests of every contract's creation and runtime",
  "                            bytecode (scripts/bytecode-reference.json). This is the check",
  "                            CI runs: it fails as soon as a contract or a compiler setting",
  "                            changes, because the solc settings are hashed into the",
  "                            metadata trailer. Regenerate it with --update-reference when",
  "                            a contract change is intended.",
  "",
  "  --deployments NETWORK     `deployments/<NETWORK>/*_Implementation.json` records of the",
  "                            deployed implementations. Only informational: implementations",
  "                            on chain may predate the current sources. The runtime bytecode",
  "                            is compared twice: in full and with the CBOR metadata trailer",
  "                            stripped (the trailer only carries the metadata hash).",
  "                            The older records carry the bytecode. The ones",
  "                            the Foundry scripts write carry only the address, so their code",
  "                            is read from the chain with `cast code` (see --rpc-url). Linked",
  "                            library addresses and immutables are only filled in at",
  "                            deployment, so those bytes are masked on both sides.",
  "",
  "Exit status is non-zero when a strict comparison finds a difference.",
].join("\n");

const USAGE = [
  `usage: ${PROG} [-h] [--reference REFERENCE]`,
  "                                [--update-reference UPDATE_REFERENCE]",
  "                                [--deployments DEPLOYMENTS] [--rpc-url RPC_URL]",
  "                                [--out OUT]",
].join("\n");

const OPTIONS_HELP = [
  "options:",
  "  -h, --help            show this help message and exit",
  "  --reference REFERENCE",
  "                        checked-in bytecode digests to verify against (strict)",
  "  --update-reference UPDATE_REFERENCE",
  "                        regenerate the digest file from the current build",
  "  --deployments DEPLOYMENTS",
  "                        network name under deployments/ (informational)",
  "  --rpc-url RPC_URL     node to read the code of records without bytecode from; an",
  "                        URL or a foundry.toml rpc_endpoints alias (default: the",
  "                        --deployments network name)",
  "  --out OUT             Foundry out directory",
].join("\n");

/** One report line: source, contract, and the two comparison verdicts. */
export type Row = readonly [source: string, contract: string, full: string, stripped: string];

export interface Digests {
  creation: string;
  runtime: string;
}

export interface Reference {
  comment: string;
  algorithm: string;
  contracts: Record<string, Digests>;
}

/** A byte range of runtime code, the way solc reports link and immutable references. */
export interface ByteRange {
  start: number;
  length: number;
}

export interface ForgeArtifactJson {
  bytecode?: { object?: string };
  deployedBytecode?: {
    object?: string;
    linkReferences?: Record<string, Record<string, ByteRange[]>>;
    immutableReferences?: Record<string, ByteRange[]>;
  };
  metadata?: { settings?: { compilationTarget?: Record<string, string> } };
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

/**
 * The runtime code of a Foundry artifact together with the byte ranges that only get their
 * value at deployment: linked library addresses (placeholders in the artifact) and
 * immutables (zeros in the artifact, e.g. the `__self` of every UUPS implementation).
 */
export interface ForgeRuntime {
  code: string;
  deployTimeRanges: ByteRange[];
}

export function forgeRuntime(
  outDir: string,
  sourceName: string,
  contractName: string
): ForgeRuntime | null {
  const path = join(outDir, basename(sourceName), `${contractName}.json`);
  if (!existsSync(path)) {
    return null;
  }
  const deployed = (readJson(path) as ForgeArtifactJson).deployedBytecode ?? {};
  const linked = Object.values(deployed.linkReferences ?? {}).flatMap((libraries) =>
    Object.values(libraries).flat()
  );
  const immutables = Object.values(deployed.immutableReferences ?? {}).flat();
  return { code: norm(deployed.object ?? ""), deployTimeRanges: [...linked, ...immutables] };
}

/** Zeroes the given byte ranges, so linked or deployed code compares with an artifact. */
export function maskRanges(hexstr: string, ranges: readonly ByteRange[]): string {
  const digits = norm(hexstr).split("");
  for (const { start, length } of ranges) {
    const end = Math.min((start + length) * 2, digits.length);
    for (let index = start * 2; index < end; index += 1) {
      digits[index] = "0";
    }
  }
  return digits.join("");
}

/** Returns the runtime code at an address as hex; empty (or `0x`) when it holds none. */
export type CodeReader = (address: string) => string;

/**
 * Reads code with `cast code`, run from the repository root so that an rpc_endpoints alias
 * of foundry.toml (`celo`, `sepolia`, `local`) resolves as well as a plain URL.
 */
export function castCodeReader(rpcUrl: string): CodeReader {
  return (address) =>
    execFileSync("cast", ["code", address, "--rpc-url", rpcUrl], {
      cwd: ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
}

function errorMessage(error: unknown): string {
  const stderr = (error as { stderr?: unknown }).stderr;
  const text = typeof stderr === "string" && stderr.trim() !== "" ? stderr : String(error);
  return text.trim().split("\n")[0] ?? "";
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

/**
 * Compares the implementation records of a network with the current build. A record
 * without bytecode is read from the chain through `readCode`; without a reader, or when
 * reading fails, it is reported as UNREAD instead of being compared with nothing.
 */
export function checkDeployments(
  network: string,
  outDir: string,
  deploymentsDir: string = join(ROOT, "deployments"),
  readCode?: CodeReader
): number {
  const rows: Row[] = [];
  const notes: string[] = [];
  for (const path of implementationFiles(join(deploymentsDir, network))) {
    const name = basename(path).replace("_Implementation.json", "");
    const deployment = readJson(path) as { address?: string; deployedBytecode?: string };
    const forge = forgeRuntime(outDir, `${name}.sol`, name);
    if (forge === null) {
      rows.push([network, name, "MISSING", "MISSING"]);
      continue;
    }
    let runtime = norm(deployment.deployedBytecode ?? "");
    if (runtime === "") {
      if (readCode === undefined || !deployment.address) {
        rows.push([network, name, "UNREAD", "UNREAD"]);
        notes.push(`${name}: the record has no bytecode and no code reader was given`);
        continue;
      }
      try {
        runtime = norm(readCode(deployment.address));
      } catch (error) {
        rows.push([network, name, "UNREAD", "UNREAD"]);
        notes.push(`${name}: reading ${deployment.address} failed: ${errorMessage(error)}`);
        continue;
      }
      if (runtime === "") {
        rows.push([network, name, "NO CODE", "NO CODE"]);
        continue;
      }
    }
    const expected = maskRanges(forge.code, forge.deployTimeRanges);
    const actual = maskRanges(runtime, forge.deployTimeRanges);
    const full = actual === expected;
    const stripped = stripMetadata(actual) === stripMetadata(expected);
    rows.push([network, name, full ? "ok" : "DIFF", stripped ? "ok" : "DIFF"]);
  }
  printTable(`deployments/${network} implementations vs Foundry (informational)`, rows);
  for (const note of notes) {
    console.log(`  ${note}`);
  }
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
  deployments?: string;
  rpcUrl?: string;
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
      !["--reference", "--update-reference", "--deployments", "--rpc-url", "--out"].includes(flag)
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
    } else if (flag === "--deployments") {
      args.deployments = value;
    } else if (flag === "--rpc-url") {
      args.rpcUrl = value;
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
  if (!(args.reference || args.updateReference || args.deployments)) {
    throw usageError("pass --reference, --update-reference and/or --deployments");
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
  if (args.deployments) {
    const reader = castCodeReader(args.rpcUrl ?? args.deployments);
    failures += checkDeployments(args.deployments, args.out, undefined, reader);
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
