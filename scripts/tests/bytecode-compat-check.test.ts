// Tests for scripts/bytecode-compat-check.ts. Run with `node --test scripts/tests/`.
//
// Every case builds a throwaway Foundry `out/` tree, so the tests never need `forge build`
// and never read the real artifacts.

import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { after, describe, it } from "node:test";
import { fileURLToPath } from "node:url";

import {
  ROOT,
  buildReference,
  checkHardhat,
  checkReference,
  digest,
  norm,
  serializeReference,
  stripMetadata,
  updateReference,
  main,
} from "../bytecode-compat-check.ts";

const temporaryDirectories: string[] = [];

after(() => {
  for (const directory of temporaryDirectories) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function temporaryDirectory(): string {
  const directory = mkdtempSync(join(tmpdir(), "bytecode-compat-"));
  temporaryDirectories.push(directory);
  return directory;
}

/** Appends a CBOR metadata trailer, i.e. the metadata bytes plus their two-byte length. */
function withMetadata(body: string, metadata: string): string {
  const length = (metadata.length / 2).toString(16).padStart(4, "0");
  return `0x${body}${metadata}${length}`;
}

const CREATION_BODY = "60806040523480";
const RUNTIME_BODY = "6080604052348015";
const METADATA_A = "aa".repeat(8);
const METADATA_B = "bb".repeat(8);

const CREATION_A = withMetadata(CREATION_BODY, METADATA_A);
const RUNTIME_A = withMetadata(RUNTIME_BODY, METADATA_A);
const CREATION_B = withMetadata(CREATION_BODY, METADATA_B);
const RUNTIME_B = withMetadata(RUNTIME_BODY, METADATA_B);

interface ArtifactSpec {
  source: string;
  contract: string;
  creation?: string;
  runtime?: string;
  /** Artifact file name, when it is not the default `<Contract>.json`. */
  filename?: string;
  /** Drops metadata.settings.compilationTarget, the way a non-contract artifact has none. */
  withoutCompilationTarget?: boolean;
}

function writeForgeArtifact(outDir: string, spec: ArtifactSpec): void {
  const directory = join(outDir, basename(spec.source));
  mkdirSync(directory, { recursive: true });
  const artifact = {
    bytecode: { object: spec.creation ?? CREATION_A },
    deployedBytecode: { object: spec.runtime ?? RUNTIME_A },
    ...(spec.withoutCompilationTarget
      ? {}
      : { metadata: { settings: { compilationTarget: { [spec.source]: spec.contract } } } }),
  };
  writeFileSync(
    join(directory, spec.filename ?? `${spec.contract}.json`),
    JSON.stringify(artifact)
  );
}

function writeHardhatArtifact(
  artifactsDir: string,
  spec: { source: string; contract: string; creation: string; runtime: string }
): void {
  const directory = join(artifactsDir, spec.source);
  mkdirSync(directory, { recursive: true });
  const artifact = {
    contractName: spec.contract,
    sourceName: spec.source,
    bytecode: spec.creation,
    deployedBytecode: spec.runtime,
  };
  writeFileSync(join(directory, `${spec.contract}.json`), JSON.stringify(artifact));
}

/** Runs `body` with stdout captured, and returns everything it printed. */
function capture(body: () => void): string {
  const lines: string[] = [];
  const originalLog = console.log;
  const originalError = console.error;
  const record = (...parts: unknown[]): void => {
    lines.push(parts.map((part) => String(part)).join(" "));
  };
  console.log = record;
  console.error = record;
  try {
    body();
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
  return lines.join("\n");
}

/** An out directory with two pinned contracts and a reference file that matches it. */
function fixture(): { outDir: string; referencePath: string } {
  const outDir = temporaryDirectory();
  writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
  writeForgeArtifact(outDir, {
    source: "contracts/common/MultiSig.sol",
    contract: "MultiSig",
    creation: CREATION_B,
    runtime: RUNTIME_B,
  });
  const referencePath = join(temporaryDirectory(), "reference.json");
  capture(() => updateReference(referencePath, outDir));
  return { outDir, referencePath };
}

describe("hex helpers", () => {
  it("strips the 0x prefix and leaves bare hex alone", () => {
    assert.equal(norm("0xabcd"), "abcd");
    assert.equal(norm("abcd"), "abcd");
    assert.equal(norm(""), "");
  });

  it("removes the CBOR metadata trailer named by the last two bytes", () => {
    assert.equal(stripMetadata(CREATION_A), CREATION_BODY);
    assert.equal(stripMetadata(CREATION_B), CREATION_BODY);
    assert.equal(stripMetadata(RUNTIME_A), RUNTIME_BODY);
  });

  it("digests the lowercase hex digits without the 0x prefix", () => {
    // The hash is taken over the hex text, not the bytes it spells, so it is
    // sha256("00") and both spellings of the same byte have to reach it.
    assert.equal(digest("0x00"), digest("00"));
    assert.equal(digest("0xAB"), digest("ab"));
    assert.equal(
      digest("0x00"),
      "f1534392279bddbf9d43dde8701cb5be14b82f76ec6607bf8d6ad557f60f304e"
    );
  });
});

describe("artifact discovery", () => {
  it("pins only contracts under contracts/ that carry bytecode", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
    writeForgeArtifact(outDir, { source: "test/AccountTest.t.sol", contract: "AccountTest" });
    writeForgeArtifact(outDir, {
      source: "contracts/interfaces/IAccount.sol",
      contract: "IAccount",
      creation: "0x",
      runtime: "0x",
    });
    writeForgeArtifact(outDir, {
      source: "contracts/Account.sol",
      contract: "Untargeted",
      withoutCompilationTarget: true,
    });

    assert.deepEqual(Object.keys(buildReference(outDir).contracts), [
      "contracts/Account.sol:Account",
    ]);
  });

  it("prefers <Name>.json over <Name>.default.json and ignores the other profiles", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
    writeForgeArtifact(outDir, {
      source: "contracts/Account.sol",
      contract: "Account",
      filename: "Account.default.json",
      creation: CREATION_B,
      runtime: RUNTIME_B,
    });
    writeForgeArtifact(outDir, {
      source: "contracts/Account.sol",
      contract: "Account",
      filename: "Account.test-via-ir.json",
      creation: CREATION_B,
      runtime: RUNTIME_B,
    });

    const contracts = buildReference(outDir).contracts;
    assert.deepEqual(Object.keys(contracts), ["contracts/Account.sol:Account"]);
    assert.equal(contracts["contracts/Account.sol:Account"]?.creation, digest(CREATION_A));
  });

  it("falls back to <Name>.default.json when the build has no default-profile artifact", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, {
      source: "contracts/Account.sol",
      contract: "Account",
      filename: "Account.default.json",
    });

    assert.deepEqual(Object.keys(buildReference(outDir).contracts), [
      "contracts/Account.sol:Account",
    ]);
  });

  it("never descends into build-info", () => {
    const outDir = temporaryDirectory();
    mkdirSync(join(outDir, "build-info"), { recursive: true });
    writeFileSync(
      join(outDir, "build-info", "9c406c8694f4e33e.json"),
      JSON.stringify({
        bytecode: { object: CREATION_A },
        deployedBytecode: { object: RUNTIME_A },
        metadata: { settings: { compilationTarget: { "contracts/Account.sol": "Account" } } },
      })
    );

    assert.deepEqual(buildReference(outDir).contracts, {});
  });
});

describe("--reference", () => {
  it("reports ok on every contract when the build matches", () => {
    const { outDir, referencePath } = fixture();
    let failures = -1;
    const output = capture(() => {
      failures = checkReference(referencePath, outDir);
    });

    assert.equal(failures, 0);
    assert.match(output, /contracts\/Account\.sol\s+Account\s+ok\s+ok/);
    assert.match(output, /contracts\/common\/MultiSig\.sol\s+MultiSig\s+ok\s+ok/);
    assert.ok(!output.includes("DIFF"));
  });

  it("reports DIFF on the column whose digest changed", () => {
    const { outDir, referencePath } = fixture();
    writeForgeArtifact(outDir, {
      source: "contracts/Account.sol",
      contract: "Account",
      creation: CREATION_B,
    });

    let failures = -1;
    const output = capture(() => {
      failures = checkReference(referencePath, outDir);
    });

    assert.equal(failures, 1);
    assert.match(output, /contracts\/Account\.sol\s+Account\s+DIFF\s+ok/);
    assert.match(output, /contracts\/common\/MultiSig\.sol\s+MultiSig\s+ok\s+ok/);
    assert.match(output, /rerun with --update-reference/);
  });

  it("reports MISSING when the reference pins a contract the build does not produce", () => {
    const { outDir, referencePath } = fixture();
    rmSync(join(outDir, "MultiSig.sol"), { recursive: true });

    let failures = -1;
    const output = capture(() => {
      failures = checkReference(referencePath, outDir);
    });

    assert.equal(failures, 1);
    assert.match(output, /contracts\/common\/MultiSig\.sol\s+MultiSig\s+MISSING\s+MISSING/);
  });

  it("reports UNPINNED when the build produces a contract the reference does not pin", () => {
    const { outDir, referencePath } = fixture();
    writeForgeArtifact(outDir, { source: "contracts/Vote.sol", contract: "Vote" });

    let failures = -1;
    const output = capture(() => {
      failures = checkReference(referencePath, outDir);
    });

    assert.equal(failures, 1);
    assert.match(output, /contracts\/Vote\.sol\s+Vote\s+UNPINNED\s+UNPINNED/);
  });

  it("exits 1 with a hint when the reference file does not exist", () => {
    const { outDir } = fixture();
    let status = -1;
    const output = capture(() => {
      status = main(["--out", outDir, "--reference", join(outDir, "nope.json")]);
    });

    assert.equal(status, 1);
    assert.match(output, /reference not found: .*nope\.json \(create it with --update-reference\)/);
  });
});

describe("--update-reference", () => {
  it("writes the same bytes on every run", () => {
    const { outDir } = fixture();
    const directory = temporaryDirectory();
    const first = join(directory, "first.json");
    const second = join(directory, "second.json");

    const output = capture(() => {
      updateReference(first, outDir);
      updateReference(second, outDir);
    });

    assert.deepEqual(readFileSync(first), readFileSync(second));
    assert.match(output, /wrote 2 contract digests to .*first\.json/);
  });

  it("writes two-space JSON with sorted keys and a trailing newline", () => {
    const { outDir } = fixture();
    const path = join(temporaryDirectory(), "reference.json");
    capture(() => updateReference(path, outDir));
    const text = readFileSync(path, "utf8");

    assert.ok(text.endsWith("}\n"));
    assert.ok(text.includes('\n  "contracts": {\n    "contracts/Account.sol:Account": {\n'));
    const reference = JSON.parse(text) as { contracts: Record<string, unknown> };
    assert.deepEqual(Object.keys(reference), ["comment", "algorithm", "contracts"]);
    assert.deepEqual(Object.keys(reference.contracts), [
      "contracts/Account.sol:Account",
      "contracts/common/MultiSig.sol:MultiSig",
    ]);
    assert.equal(text, serializeReference(buildReference(outDir)));
  });

  it("keeps the checked-in reference file's header fields byte-identical", () => {
    // The digests need a build, but the two header fields do not: if either drifts,
    // --update-reference stops reproducing scripts/bytecode-reference.json byte for byte.
    const checkedIn = JSON.parse(
      readFileSync(join(ROOT, "scripts", "bytecode-reference.json"), "utf8")
    ) as { comment: string; algorithm: string };
    const generated = buildReference(temporaryDirectory());

    assert.equal(generated.comment, checkedIn.comment);
    assert.equal(generated.algorithm, checkedIn.algorithm);
  });
});

describe("--hardhat-artifacts", () => {
  it("separates a metadata-only difference from a real one", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
    const artifactsDir = temporaryDirectory();
    // Same code, different metadata hash: the full comparison fails, the stripped one passes.
    writeHardhatArtifact(artifactsDir, {
      source: "contracts/Account.sol",
      contract: "Account",
      creation: CREATION_B,
      runtime: RUNTIME_B,
    });

    let failures = -1;
    const output = capture(() => {
      failures = checkHardhat(artifactsDir, outDir);
    });

    assert.equal(failures, 1);
    assert.match(output, /full\s+no-metadata/);
    assert.match(output, /contracts\/Account\.sol\s+Account\s+DIFF\s+ok/);
  });

  it("reports ok on both columns when the two builds agree", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
    const artifactsDir = temporaryDirectory();
    writeHardhatArtifact(artifactsDir, {
      source: "contracts/Account.sol",
      contract: "Account",
      creation: CREATION_A,
      runtime: RUNTIME_A,
    });

    let failures = -1;
    const output = capture(() => {
      failures = checkHardhat(artifactsDir, outDir);
    });

    assert.equal(failures, 0);
    assert.match(output, /contracts\/Account\.sol\s+Account\s+ok\s+ok/);
  });

  it("reports MISSING when the Foundry build has no such artifact", () => {
    const artifactsDir = temporaryDirectory();
    writeHardhatArtifact(artifactsDir, {
      source: "contracts/Gone.sol",
      contract: "Gone",
      creation: CREATION_A,
      runtime: RUNTIME_A,
    });

    let failures = -1;
    const output = capture(() => {
      failures = checkHardhat(artifactsDir, temporaryDirectory());
    });

    assert.equal(failures, 1);
    assert.match(output, /contracts\/Gone\.sol\s+Gone\s+MISSING\s+MISSING/);
  });
});

describe("command line", () => {
  it("exits 2 when no mode is selected", () => {
    let status = -1;
    const output = capture(() => {
      status = main([]);
    });

    assert.equal(status, 2);
    assert.match(output, /usage: bytecode-compat-check\.ts/);
    assert.match(
      output,
      /error: pass --reference, --update-reference, --hardhat-artifacts and\/or --deployments/
    );
  });

  it("exits 2 on an unknown option", () => {
    let status = -1;
    const output = capture(() => {
      status = main(["--nope"]);
    });

    assert.equal(status, 2);
    assert.match(output, /error: unrecognized arguments: --nope/);
  });

  it("exits 1 when the out directory is not there", () => {
    let status = -1;
    const output = capture(() => {
      status = main(["--reference", "whatever.json", "--out", join(temporaryDirectory(), "gone")]);
    });

    assert.equal(status, 1);
    assert.match(output, /Foundry out directory not found: .*gone \(run `forge build` first\)/);
  });

  it("exits 0 and confirms the match, accepting --flag=value too", () => {
    const { outDir, referencePath } = fixture();
    let status = -1;
    const output = capture(() => {
      status = main([`--out=${outDir}`, `--reference=${referencePath}`]);
    });

    assert.equal(status, 0);
    assert.match(output, /bytecode matches the reference build/);
  });

  it("exits 1 and counts the differing contracts", () => {
    const { outDir, referencePath } = fixture();
    writeForgeArtifact(outDir, {
      source: "contracts/Account.sol",
      contract: "Account",
      creation: CREATION_B,
      runtime: RUNTIME_B,
    });

    let status = -1;
    const output = capture(() => {
      status = main(["--out", outDir, "--reference", referencePath]);
    });

    assert.equal(status, 1);
    assert.match(output, /1 contract\(s\) differ from the reference build/);
  });

  it("prints the help text and exits 0", () => {
    let status = -1;
    const output = capture(() => {
      status = main(["--help"]);
    });

    assert.equal(status, 0);
    assert.match(output, /usage: bytecode-compat-check\.ts \[-h\] \[--reference REFERENCE\]/);
    assert.match(output, /Exit status is non-zero when a strict comparison finds a difference\./);
    assert.match(output, /--out OUT {13}Foundry out directory/);
  });

  it("resolves ROOT to the repository root", () => {
    assert.equal(ROOT, dirname(dirname(dirname(fileURLToPath(import.meta.url)))));
  });
});
