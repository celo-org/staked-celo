// Deletes the vendored OpenZeppelin sources a build never compiled, and the directories
// that empties. Everything that is not Solidity - the LICENSE of each package - is left
// alone.
//
// Usage: node scripts/lib/prune-vendored-openzeppelin.ts <root> <build-info-dir>

import { readdirSync, readFileSync, rmdirSync, unlinkSync } from "node:fs";
import { join, relative, sep } from "node:path";

type BuildInfo = {
  source_id_to_path?: Record<string, string>;
  input: { sources: Record<string, unknown> };
};

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

const [root, buildInfo] = process.argv.slice(2);
if (process.argv.length < 4) {
  fail("usage: prune-vendored-openzeppelin.ts <root> <build-info-dir>");
}

const infos = readdirSync(buildInfo)
  .filter((name) => name.endsWith(".json"))
  .sort();
if (infos.length === 0) fail(`no build-info written to ${buildInfo}`);

// The standard-json input of a compilation lists every source unit solc was handed,
// transitive imports included, under the same "@openzeppelin/..." names the contracts
// import. One build-info file per compiler invocation, so the sets are unioned.
const used = new Set<string>();
for (const info of infos) {
  const build = JSON.parse(readFileSync(join(buildInfo, info), "utf8")) as BuildInfo;
  // source_id_to_path is the cheap one; input.sources names the same units for
  // build-info versions written before it existed.
  const byId = build.source_id_to_path;
  const names = byId ? Object.values(byId) : Object.keys(build.input.sources);
  for (const name of names) {
    if (name.startsWith("@openzeppelin/")) used.add(name);
  }
}

if (used.size === 0) fail("the build imports no @openzeppelin source; refusing to empty the tree");

let kept = 0;
let removed = 0;
const directories: string[] = [];

for (const entry of readdirSync(join(root, "@openzeppelin"), {
  recursive: true,
  withFileTypes: true,
})) {
  const path = join(entry.parentPath, entry.name);
  if (entry.isDirectory()) {
    directories.push(path);
    continue;
  }
  if (!entry.name.endsWith(".sol")) continue;
  if (used.has(relative(root, path).split(sep).join("/"))) {
    kept++;
  } else {
    unlinkSync(path);
    removed++;
  }
}

// Deepest first, so a directory emptied by its own subdirectories goes too.
for (const directory of directories.sort().reverse()) {
  if (readdirSync(directory).length === 0) rmdirSync(directory);
}

console.log(`pruned @openzeppelin: kept ${kept} imported sources, removed ${removed} unused`);
