// Turns an anvil `--dump-state` document into the fixture the Foundry suite loads:
// test/devchain/allocs.json (a genesis "alloc" map for `vm.loadAllocs`) and
// test/devchain/meta.json (the block environment and the provenance of the dump).
//
// Usage: node scripts/lib/extract-devchain-allocs.ts <state.json> <out-dir> <source>
//
// The state file of the pinned devchain is ~700 MB, which is more than the longest
// string V8 can hold, so `JSON.parse` of the whole document is not an option. Only
// three of its six top-level members are needed, and the bulk - `blocks` and
// `transactions` - is not among them. The scanner below therefore walks the raw bytes
// to find the span of each member and parses only the spans that are wanted; every
// account is parsed on its own, and each of those is small.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const SPACE = 0x20;
const TAB = 0x09;
const LINE_FEED = 0x0a;
const CARRIAGE_RETURN = 0x0d;
const QUOTE = 0x22;
const BACKSLASH = 0x5c;
const COMMA = 0x2c;
const OPEN_BRACE = 0x7b;
const CLOSE_BRACE = 0x7d;
const OPEN_BRACKET = 0x5b;
const CLOSE_BRACKET = 0x5d;

function isSpace(byte: number): boolean {
  return byte === SPACE || byte === TAB || byte === LINE_FEED || byte === CARRIAGE_RETURN;
}

function skipSpace(buffer: Buffer, at: number): number {
  let i = at;
  while (i < buffer.length && isSpace(buffer[i])) i++;
  return i;
}

// The byte after the closing quote of the string starting at `at`.
function endOfString(buffer: Buffer, at: number): number {
  let i = at + 1;
  while (i < buffer.length) {
    const byte = buffer[i];
    if (byte === BACKSLASH) {
      i += 2;
      continue;
    }
    if (byte === QUOTE) return i + 1;
    i++;
  }
  throw new Error(`unterminated string at byte ${at}`);
}

// The byte after the JSON value starting at `at`.
function endOfValue(buffer: Buffer, at: number): number {
  const first = buffer[at];
  if (first === QUOTE) return endOfString(buffer, at);
  if (first === OPEN_BRACE || first === OPEN_BRACKET) {
    let depth = 0;
    let i = at;
    while (i < buffer.length) {
      const byte = buffer[i];
      // Braces and brackets inside a string are not structural.
      if (byte === QUOTE) {
        i = endOfString(buffer, i);
        continue;
      }
      if (byte === OPEN_BRACE || byte === OPEN_BRACKET) {
        depth++;
      } else if (byte === CLOSE_BRACE || byte === CLOSE_BRACKET) {
        depth--;
        if (depth === 0) return i + 1;
      }
      i++;
    }
    throw new Error(`unterminated ${String.fromCharCode(first)} at byte ${at}`);
  }
  // A number, or one of true/false/null: it ends where the enclosing value continues.
  let i = at;
  while (i < buffer.length) {
    const byte = buffer[i];
    if (byte === COMMA || byte === CLOSE_BRACE || byte === CLOSE_BRACKET || isSpace(byte)) break;
    i++;
  }
  return i;
}

type Member = { key: string; start: number; end: number };

// The members of the object starting at `at`, with the byte span of each value.
function* members(buffer: Buffer, at: number): Generator<Member> {
  let i = skipSpace(buffer, at + 1);
  if (buffer[i] === CLOSE_BRACE) return;
  for (;;) {
    const keyEnd = endOfString(buffer, i);
    const key = JSON.parse(buffer.toString("utf8", i, keyEnd)) as string;
    i = skipSpace(buffer, keyEnd);
    i = skipSpace(buffer, i + 1); // past the ':'
    const valueEnd = endOfValue(buffer, i);
    yield { key, start: i, end: valueEnd };
    i = skipSpace(buffer, valueEnd);
    if (buffer[i] !== COMMA) return;
    i = skipSpace(buffer, i + 1);
  }
}

type Account = {
  balance?: unknown;
  nonce?: unknown;
  code?: unknown;
  storage?: Record<string, string> | null;
};

type Alloc = {
  balance: unknown;
  nonce: unknown;
  code?: unknown;
  storage?: Record<string, string>;
};

const [statePath, outDir, source] = process.argv.slice(2);
if (process.argv.length < 5) {
  throw new Error("usage: extract-devchain-allocs.ts <state.json> <out-dir> <source>");
}

const state = readFileSync(statePath);
const root = skipSpace(state, 0);

const allocs: Record<string, Alloc> = {};
let block: { number: string; timestamp: string } | undefined;
let bestBlockNumber: unknown = 0;

for (const member of members(state, root)) {
  if (member.key === "block") {
    block = JSON.parse(state.toString("utf8", member.start, member.end));
  } else if (member.key === "best_block_number") {
    bestBlockNumber = JSON.parse(state.toString("utf8", member.start, member.end));
  } else if (member.key === "accounts") {
    for (const account of members(state, member.start)) {
      const record = JSON.parse(state.toString("utf8", account.start, account.end)) as Account;
      const entry: Alloc = {
        balance: "balance" in record ? record.balance : "0x0",
        nonce: "nonce" in record ? record.nonce : 0,
      };
      const code = record.code;
      if (code && code !== "0x") entry.code = code;
      const storage = record.storage || {};
      if (Object.keys(storage).length > 0) entry.storage = storage;
      allocs[account.key] = entry;
    }
  }
}

if (!block) throw new Error(`no "block" section in ${statePath}`);

writeFileSync(join(outDir, "allocs.json"), JSON.stringify(allocs));

const meta = {
  blockNumber: Number.parseInt(block.number, 16),
  timestamp: Number.parseInt(block.timestamp, 16),
  bestBlockNumber,
  source,
};
writeFileSync(join(outDir, "meta.json"), `${JSON.stringify(meta, null, 2)}\n`);

console.log(
  `wrote ${Object.keys(allocs).length} accounts to ${outDir}/allocs.json;` +
    ` block ${meta.blockNumber} ts ${meta.timestamp}`
);
