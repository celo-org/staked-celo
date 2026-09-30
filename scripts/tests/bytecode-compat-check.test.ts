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
  checkDeployments,
  checkReference,
  digest,
  maskRanges,
  norm,
  parseArgs,
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
  linkReferences?: Record<string, Record<string, { start: number; length: number }[]>>;
  immutableReferences?: Record<string, { start: number; length: number }[]>;
}

function writeForgeArtifact(outDir: string, spec: ArtifactSpec): void {
  const directory = join(outDir, basename(spec.source));
  mkdirSync(directory, { recursive: true });
  const artifact = {
    bytecode: { object: spec.creation ?? CREATION_A },
    deployedBytecode: {
      object: spec.runtime ?? RUNTIME_A,
      ...(spec.linkReferences ? { linkReferences: spec.linkReferences } : {}),
      ...(spec.immutableReferences ? { immutableReferences: spec.immutableReferences } : {}),
    },
    ...(spec.withoutCompilationTarget
      ? {}
      : { metadata: { settings: { compilationTarget: { [spec.source]: spec.contract } } } }),
  };
  writeFileSync(
    join(directory, spec.filename ?? `${spec.contract}.json`),
    JSON.stringify(artifact)
  );
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

describe("--deployments", () => {
  /** A deployments/<network> directory holding one `<Name>_Implementation.json` per entry. */
  function deployments(records: Record<string, string>): string {
    const root = temporaryDirectory();
    mkdirSync(join(root, "testnet"), { recursive: true });
    for (const [name, runtime] of Object.entries(records)) {
      writeFileSync(
        join(root, "testnet", `${name}_Implementation.json`),
        JSON.stringify({
          address: "0x0000000000000000000000000000000000000001",
          deployedBytecode: runtime,
        })
      );
    }
    return root;
  }

  it("reports identical code, a metadata-only difference, a real difference and a missing artifact", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
    writeForgeArtifact(outDir, { source: "contracts/Manager.sol", contract: "Manager" });
    writeForgeArtifact(outDir, { source: "contracts/Vote.sol", contract: "Vote" });
    const root = deployments({
      Account: RUNTIME_A,
      // Same executable code, different metadata hash: only the trailer differs.
      Manager: RUNTIME_B,
      // Different executable code.
      Vote: withMetadata("6080604052600080fd", METADATA_A),
      Gone: RUNTIME_A,
    });

    let status = -1;
    const output = capture(() => {
      status = checkDeployments("testnet", outDir, root);
    });
    const row = (name: string): string =>
      output.split("\n").find((line) => line.includes(` ${name} `)) ?? "";

    assert.equal(status, 0, "the deployments comparison is informational");
    assert.match(row("Account"), /ok\s+ok/);
    assert.match(row("Manager"), /DIFF\s+ok/);
    assert.match(row("Vote"), /DIFF\s+DIFF/);
    assert.match(row("Gone"), /MISSING\s+MISSING/);
  });

  // The artifact of a contract that links a library and has an immutable: the 20 byte
  // placeholder solc leaves for the library address starts at byte 2, the 32 byte
  // immutable (zeros in the artifact) at byte 22.
  const PLACEHOLDER = `__$${"ab".repeat(17)}$__`;
  const LINKED_ARTIFACT = withMetadata(`6080${PLACEHOLDER}${"00".repeat(32)}fd`, METADATA_A);
  const LINKED_REFERENCES = {
    linkReferences: { "contracts/Lib.sol": { Lib: [{ start: 2, length: 20 }] } },
    immutableReferences: { "42": [{ start: 22, length: 32 }] },
  };
  /** The same contract as deployed: library address and immutable filled in. */
  const LINKED_ON_CHAIN = withMetadata(`6080${"11".repeat(20)}${"22".repeat(32)}fd`, METADATA_A);

  /** A deployments/<network> directory holding the given records verbatim. */
  function records(entries: Record<string, object>): string {
    const root = temporaryDirectory();
    mkdirSync(join(root, "testnet"), { recursive: true });
    for (const [name, record] of Object.entries(entries)) {
      writeFileSync(join(root, "testnet", `${name}_Implementation.json`), JSON.stringify(record));
    }
    return root;
  }

  function runDeployments(
    outDir: string,
    root: string,
    readCode?: (address: string) => string
  ): (name: string) => string {
    let status = -1;
    const output = capture(() => {
      status = checkDeployments("testnet", outDir, root, readCode);
    });
    assert.equal(status, 0, "the deployments comparison is informational");
    return (name) => output.split("\n").find((line) => line.includes(` ${name}`)) ?? "";
  }

  it("reads the code of a record without bytecode from the chain", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
    writeForgeArtifact(outDir, { source: "contracts/Vote.sol", contract: "Vote" });
    const root = records({
      Account: { address: "0x00000000000000000000000000000000000000a1" },
      Vote: { address: "0x00000000000000000000000000000000000000b2" },
    });
    const read: string[] = [];
    const chain: Record<string, string> = {
      "0x00000000000000000000000000000000000000a1": RUNTIME_A,
      "0x00000000000000000000000000000000000000b2": withMetadata("6080604052600080fd", METADATA_A),
    };

    const row = runDeployments(outDir, root, (address) => {
      read.push(address);
      return chain[address] ?? "0x";
    });

    assert.deepEqual(read.sort(), Object.keys(chain).sort());
    assert.match(row("Account"), /ok\s+ok/);
    assert.match(row("Vote"), /DIFF\s+DIFF/);
  });

  it("masks linked library addresses and immutables on both sides", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, {
      source: "contracts/Strategy.sol",
      contract: "Strategy",
      runtime: LINKED_ARTIFACT,
      ...LINKED_REFERENCES,
    });
    writeForgeArtifact(outDir, {
      source: "contracts/Linked.sol",
      contract: "Linked",
      runtime: LINKED_ARTIFACT,
      ...LINKED_REFERENCES,
    });
    writeForgeArtifact(outDir, {
      source: "contracts/Changed.sol",
      contract: "Changed",
      runtime: LINKED_ARTIFACT,
      ...LINKED_REFERENCES,
    });
    const root = records({
      // Read from the chain: the library address and the immutable are filled in.
      Strategy: { address: "0x00000000000000000000000000000000000000c3" },
      // An older record stores the linked code.
      Linked: {
        address: "0x00000000000000000000000000000000000000d4",
        deployedBytecode: LINKED_ON_CHAIN,
      },
      // A byte outside the masked ranges differs.
      Changed: {
        address: "0x00000000000000000000000000000000000000e5",
        deployedBytecode: withMetadata(`6080${"11".repeat(20)}${"22".repeat(32)}fe`, METADATA_A),
      },
    });

    const row = runDeployments(outDir, root, () => LINKED_ON_CHAIN);

    assert.match(row("Strategy"), /ok\s+ok/);
    assert.match(row("Linked"), /ok\s+ok/);
    assert.match(row("Changed"), /DIFF\s+DIFF/);
  });

  it("reports a recorded address without code and a read that fails", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
    writeForgeArtifact(outDir, { source: "contracts/Vote.sol", contract: "Vote" });
    const root = records({
      Account: { address: "0x00000000000000000000000000000000000000a1" },
      Vote: { address: "0x00000000000000000000000000000000000000b2" },
    });

    const row = runDeployments(outDir, root, (address) => {
      if (address.endsWith("b2")) {
        throw Object.assign(new Error("cast failed"), { stderr: "Error: connection refused\n" });
      }
      return "0x";
    });

    assert.match(row("Account"), /NO CODE\s+NO CODE/);
    assert.match(row("Vote"), /UNREAD\s+UNREAD/);
    assert.match(row("Vote:"), /reading 0x0+b2 failed: Error: connection refused/);
  });

  it("reports a record without bytecode as unread when no reader is given", () => {
    const outDir = temporaryDirectory();
    writeForgeArtifact(outDir, { source: "contracts/Account.sol", contract: "Account" });
    const root = records({ Account: { address: "0x00000000000000000000000000000000000000a1" } });

    const row = runDeployments(outDir, root);

    assert.match(row("Account"), /UNREAD\s+UNREAD/);
  });
});

describe("maskRanges", () => {
  it("zeroes whole bytes and ignores ranges past the end", () => {
    assert.equal(maskRanges("0xaabbccdd", [{ start: 1, length: 2 }]), "aa0000dd");
    assert.equal(maskRanges("aabb", [{ start: 1, length: 4 }]), "aa00");
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

describe("command line", () => {
  it("accepts --rpc-url next to --deployments", () => {
    const args = parseArgs(["--deployments", "celo", "--rpc-url=https://forno.celo.org"]);

    assert.equal(args.deployments, "celo");
    assert.equal(args.rpcUrl, "https://forno.celo.org");
  });

  it("exits 2 when no mode is selected", () => {
    let status = -1;
    const output = capture(() => {
      status = main([]);
    });

    assert.equal(status, 2);
    assert.match(output, /usage: bytecode-compat-check\.ts/);
    assert.match(output, /error: pass --reference, --update-reference and\/or --deployments/);
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
