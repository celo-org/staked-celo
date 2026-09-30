/**
 * Reads the parts of a Foundry build the per-contract artifacts leave out: the compiler
 * runs (`out/build-info/<id>.json`) and which run built which contract (the cache
 * Forge keeps next to `out/`).
 *
 * A contract artifact carries the AST of its own source file only. A declaration it
 * imports from a file that declares no contract - a file level enum, say - has no
 * artifact of its own and appears in the build-info alone. Every compiler run also
 * numbers its AST nodes on its own, and an incremental build keeps several runs side by
 * side, so an AST id only means something together with the run it came from.
 */
import fs from "node:fs";
import path from "node:path";

/** The shape of `cache/solidity-files-cache.json` this module reads. */
type BuildCache = {
  files?: Record<
    string,
    {
      artifacts?: Record<string, Record<string, Record<string, { build_id?: string }>>>;
    }
  >;
};

/** The shape of `out/build-info/<id>.json` this module reads. */
type BuildInfo = {
  output?: { sources?: Record<string, { ast?: unknown }> };
};

/** The build-info ids present under `outDir`, sorted. */
export function buildInfoIds(outDir: string): string[] {
  let names: string[];
  try {
    names = fs.readdirSync(path.join(outDir, "build-info"));
  } catch {
    return [];
  }
  return names
    .filter((name) => name.endsWith(".json"))
    .map((name) => name.slice(0, -".json".length))
    .sort();
}

/**
 * Maps `<source>:<contract>` to the build-info id of the compiler run that produced the
 * contract's default-profile artifact, read from the cache Forge keeps beside `outDir`
 * (`forge build` and `forge build --root <dir>` both put `cache/` next to `out/`).
 * Empty when there is no cache.
 */
export function contractBuilds(outDir: string): Map<string, string> {
  const cachePath = path.join(
    path.dirname(path.resolve(outDir)),
    "cache",
    "solidity-files-cache.json"
  );
  let cache: BuildCache;
  try {
    cache = JSON.parse(fs.readFileSync(cachePath, "utf8")) as BuildCache;
  } catch {
    return new Map();
  }
  const builds = new Map<string, string>();
  for (const [source, file] of Object.entries(cache.files ?? {})) {
    for (const [contract, versions] of Object.entries(file.artifacts ?? {})) {
      for (const profiles of Object.values(versions)) {
        const buildId = profiles["default"]?.build_id;
        if (buildId !== undefined) {
          builds.set(`${source}:${contract}`, buildId);
        }
      }
    }
  }
  return builds;
}

/** Every source file of one compiler run with its AST, as [source path, AST]. */
export function buildInfoSources(outDir: string, buildId: string): Array<[string, unknown]> {
  const file = path.join(outDir, "build-info", `${buildId}.json`);
  const info = JSON.parse(fs.readFileSync(file, "utf8")) as BuildInfo;
  return Object.entries(info.output?.sources ?? {}).map(([source, unit]) => [source, unit.ast]);
}
