/**
 * Regression tests for scripts/abi-compat-check.ts.
 *
 * Each test builds a pair of minimal Foundry `out/` directories in a temp dir - just
 * enough of an artifact for the checker to pick it up - and runs the real entry point
 * over them, so the exit status and the report are covered along with the comparison.
 *
 * Run with:  yarn test:scripts
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { main } from "../abi-compat-check.ts";
import type {
  AbiEntry,
  Artifact,
  AstNode,
  StorageEntry,
  TypeInfo,
  TypesMap,
} from "../abi-compat-check.ts";

const UINT256: TypeInfo = { encoding: "inplace", label: "uint256", numberOfBytes: "32" };
const UINT128: TypeInfo = { encoding: "inplace", label: "uint128", numberOfBytes: "16" };
const ADDRESS: TypeInfo = { encoding: "inplace", label: "address", numberOfBytes: "20" };

function gapType(length: number): string {
  return `t_array(t_uint256)${length}_storage`;
}

const ABI: AbiEntry[] = [
  {
    type: "function",
    name: "deposit",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "Deposited",
    inputs: [{ name: "who", type: "address", indexed: true }],
    anonymous: false,
  },
];

const RECEIVE: AbiEntry = { type: "receive", stateMutability: "payable" };
const PAYABLE_FALLBACK: AbiEntry = { type: "fallback", stateMutability: "payable" };
const PLAIN_FALLBACK: AbiEntry = { type: "fallback", stateMutability: "nonpayable" };

/** One entry of storageLayout.storage, or one struct member; solc shapes them alike. */
function slotEntry(label: string, slot: number, typeId: string, offset = 0): StorageEntry {
  return { label, slot: String(slot), offset, type: typeId };
}

function artifact(
  name: string,
  storage: StorageEntry[],
  types: TypesMap,
  abi: AbiEntry[] = ABI,
  ast: AstNode | null = null
): Artifact {
  const content: Artifact = {
    metadata: { settings: { compilationTarget: { [`contracts/${name}.sol`]: name } } },
    storageLayout: { storage: [...storage], types: { ...types } },
    abi: [...abi],
  };
  if (ast !== null) {
    content.ast = ast;
  }
  return content;
}

/** Types map carrying a uint256[N] for every gap length the fixture spells out. */
function gapTypes(...lengths: number[]): TypesMap {
  const types: TypesMap = { t_uint256: UINT256, t_address: ADDRESS };
  for (const length of lengths) {
    types[gapType(length)] = {
      encoding: "inplace",
      label: `uint256[${length}]`,
      numberOfBytes: String(32 * length),
      base: "t_uint256",
    };
  }
  return types;
}

/** A source unit AST holding one contract level enum, shaped the way solc emits it. */
function enumAst(contract: string, enumName: string, members: string[]): AstNode {
  return {
    nodeType: "SourceUnit",
    nodes: [
      {
        nodeType: "ContractDefinition",
        name: contract,
        nodes: [
          {
            nodeType: "EnumDefinition",
            name: enumName,
            canonicalName: `${contract}.${enumName}`,
            members: members.map((member) => ({ nodeType: "EnumValue", name: member })),
          },
        ],
      },
    ],
  };
}

/**
 * A Vault storing a `Status`, either directly or as a member of a struct.
 *
 * The layout says no more than "one byte" either way, so the member list has to come
 * from the AST - which is what `withAst` can withhold.
 */
function enumVault(
  members: string[],
  astId: number,
  options: { nested?: boolean; withAst?: boolean } = {}
): Artifact {
  const nested = options.nested ?? false;
  const withAst = options.withAst ?? true;
  const enumId = `t_enum(Status)${astId}`;
  const types: TypesMap = {
    t_uint256: UINT256,
    [enumId]: { encoding: "inplace", label: "enum Vault.Status", numberOfBytes: "1" },
  };
  let storage: StorageEntry[];
  if (nested) {
    const structId = `t_struct(Entry)${astId}_storage`;
    types[structId] = {
      encoding: "inplace",
      label: "struct Vault.Entry",
      numberOfBytes: "64",
      members: [slotEntry("amount", 0, "t_uint256"), slotEntry("status", 1, enumId)],
    };
    storage = [slotEntry("entry", 0, structId)];
  } else {
    storage = [slotEntry("status", 0, enumId)];
  }
  return artifact(
    "Vault",
    storage,
    types,
    ABI,
    withAst ? enumAst("Vault", "Status", members) : null
  );
}

/** A source unit AST holding one `type Amount is uint256`, shaped the way solc emits it. */
function valueTypeAst(contract: string, valueType: string, underlying: string): AstNode {
  return {
    nodeType: "SourceUnit",
    nodes: [
      {
        nodeType: "ContractDefinition",
        name: contract,
        nodes: [
          {
            nodeType: "UserDefinedValueTypeDefinition",
            name: valueType,
            canonicalName: `${contract}.${valueType}`,
            underlyingType: {
              nodeType: "ElementaryTypeName",
              name: underlying,
              typeDescriptions: {
                typeIdentifier: `t_${underlying}`,
                typeString: underlying,
              },
            },
          },
        ],
      },
    ],
  };
}

/**
 * A Vault storing an `Amount`: on its own, as a struct member or as a mapping key.
 *
 * solc writes out the same `t_userDefinedValueType(Amount)<id>` of the same width for
 * every underlying type of that width, and labels it with the canonical name either
 * way, so what `Amount` wraps shows up in the AST only - which is what `withAst` can
 * withhold.
 */
function valueTypeVault(
  underlying: string,
  astId: number,
  options: { shape?: "direct" | "struct_member" | "mapping_key"; withAst?: boolean } = {}
): Artifact {
  const shape = options.shape ?? "direct";
  const withAst = options.withAst ?? true;
  const valueId = `t_userDefinedValueType(Amount)${astId}`;
  const types: TypesMap = {
    t_uint256: UINT256,
    [valueId]: { encoding: "inplace", label: "Vault.Amount", numberOfBytes: "32" },
  };
  let storage: StorageEntry[];
  if (shape === "struct_member") {
    const structId = `t_struct(Entry)${astId}_storage`;
    types[structId] = {
      encoding: "inplace",
      label: "struct Vault.Entry",
      numberOfBytes: "64",
      members: [slotEntry("amount", 0, valueId), slotEntry("fee", 1, "t_uint256")],
    };
    storage = [slotEntry("entry", 0, structId)];
  } else if (shape === "mapping_key") {
    const mappingId = `t_mapping(${valueId},t_uint256)`;
    types[mappingId] = {
      encoding: "mapping",
      label: "mapping(Vault.Amount => uint256)",
      numberOfBytes: "32",
      key: valueId,
      value: "t_uint256",
    };
    storage = [slotEntry("byAmount", 0, mappingId)];
  } else {
    storage = [slotEntry("total", 0, valueId)];
  }
  return artifact(
    "Vault",
    storage,
    types,
    ABI,
    withAst ? valueTypeAst("Vault", "Amount", underlying) : null
  );
}

/** An `Entry[]` whose element is a single slot, however many uint128s sit in it. */
function paddedVault(members: string[], astId: number): Artifact {
  const structId = `t_struct(Entry)${astId}_storage`;
  const arrayId = `t_array(${structId})dyn_storage`;
  const types: TypesMap = {
    t_uint128: UINT128,
    [structId]: {
      encoding: "inplace",
      label: "struct Vault.Entry",
      numberOfBytes: "32",
      members: members.map((label, index) => slotEntry(label, 0, "t_uint128", 16 * index)),
    },
    [arrayId]: {
      encoding: "dynamic_array",
      label: "struct Vault.Entry[]",
      numberOfBytes: "32",
      base: structId,
    },
  };
  return artifact("Vault", [slotEntry("entries", 0, arrayId)], types);
}

type Shape =
  | "plain"
  | "dynamic_array"
  | "static_array"
  | "mapping"
  | "mapping_of_array"
  | "struct_of_array";

/**
 * Types map and top level type id for an `Entry` struct held in the given shape.
 *
 * `astId` is what solc appends to struct identifiers; it differs between any two
 * builds, so the fixtures use different ids on the two sides on purpose.
 */
function entryTypes(
  shape: Shape,
  members: string[],
  astId: number
): { types: TypesMap; typeId: string } {
  const structId = `t_struct(Entry)${astId}_storage`;
  const arrayId = `t_array(${structId})dyn_storage`;
  const types: TypesMap = {
    t_uint256: UINT256,
    t_address: ADDRESS,
    [structId]: {
      encoding: "inplace",
      label: "struct Vault.Entry",
      numberOfBytes: String(32 * members.length),
      members: members.map((label, index) => slotEntry(label, index, "t_uint256")),
    },
  };
  const dynamicArray: TypeInfo = {
    encoding: "dynamic_array",
    label: "struct Vault.Entry[]",
    numberOfBytes: "32",
    base: structId,
  };

  if (shape === "plain") {
    return { types, typeId: structId };
  }
  if (shape === "dynamic_array") {
    types[arrayId] = dynamicArray;
    return { types, typeId: arrayId };
  }
  if (shape === "static_array") {
    const staticId = `t_array(${structId})3_storage`;
    types[staticId] = {
      encoding: "inplace",
      label: "struct Vault.Entry[3]",
      numberOfBytes: String(3 * 32 * members.length),
      base: structId,
    };
    return { types, typeId: staticId };
  }
  if (shape === "mapping") {
    const mappingId = `t_mapping(t_address,${structId})`;
    types[mappingId] = {
      encoding: "mapping",
      label: "mapping(address => struct Vault.Entry)",
      numberOfBytes: "32",
      key: "t_address",
      value: structId,
    };
    return { types, typeId: mappingId };
  }
  if (shape === "mapping_of_array") {
    types[arrayId] = dynamicArray;
    const mappingId = `t_mapping(t_address,${arrayId})`;
    types[mappingId] = {
      encoding: "mapping",
      label: "mapping(address => struct Vault.Entry[])",
      numberOfBytes: "32",
      key: "t_address",
      value: arrayId,
    };
    return { types, typeId: mappingId };
  }
  types[arrayId] = dynamicArray;
  const holderId = `t_struct(Holder)${astId + 100}_storage`;
  types[holderId] = {
    encoding: "inplace",
    label: "struct Vault.Holder",
    numberOfBytes: "32",
    members: [slotEntry("items", 0, arrayId)],
  };
  return { types, typeId: holderId };
}

function vault(shape: Shape, members: string[], astId: number, abi: AbiEntry[] = ABI): Artifact {
  const { types, typeId } = entryTypes(shape, members, astId);
  return artifact("Vault", [slotEntry("entries", 0, typeId)], types, abi);
}

type Build = Record<string, Artifact>;

/** Writes both sides as Foundry artifacts and runs the checker over them. */
function runCheck(baseline: Build, current: Build): { status: number; output: string } {
  const tmp = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), "abi-compat-"));
  try {
    const directories: string[] = [];
    const sides: Array<[string, Build]> = [
      ["baseline", baseline],
      ["current", current],
    ];
    for (const [side, artifacts] of sides) {
      const out = path.join(tmp, side, "out");
      for (const [name, content] of Object.entries(artifacts)) {
        const contractDir = path.join(out, `${name}.sol`);
        fs.mkdirSync(contractDir, { recursive: true });
        fs.writeFileSync(path.join(contractDir, `${name}.json`), JSON.stringify(content));
      }
      directories.push(out);
    }

    let output = "";
    const status = main(
      ["--baseline", directories[0] as string, "--current", directories[1] as string],
      (text) => {
        output += text;
      }
    );
    return { status, output };
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function assertRejected(baseline: Build, current: Build, ...expected: string[]): string {
  const { status, output } = runCheck(baseline, current);
  assert.equal(status, 1, output);
  assert.ok(output.includes("\nERRORS"), output);
  for (const needle of expected) {
    assert.ok(output.includes(needle), `missing ${JSON.stringify(needle)} in:\n${output}`);
  }
  return output;
}

function assertReviewOnly(baseline: Build, current: Build, ...expected: string[]): string {
  const { status, output } = runCheck(baseline, current);
  assert.equal(status, 0, output);
  assert.ok(!output.includes("\nERRORS"), output);
  assert.ok(output.includes("\nREVIEW"), output);
  for (const needle of expected) {
    assert.ok(output.includes(needle), `missing ${JSON.stringify(needle)} in:\n${output}`);
  }
  return output;
}

function assertCompatible(baseline: Build, current: Build): string {
  const { status, output } = runCheck(baseline, current);
  assert.equal(status, 0, output);
  assert.ok(output.includes("compatible with the baseline (0 item(s) flagged for review)"), output);
  return output;
}

// A struct that is an array element may not grow: the elements sit back to back
// from the array's base slot, so a wider element moves all the ones behind it.
test("appended member in dynamic array element is an error", () => {
  assertRejected(
    { Vault: vault("dynamic_array", ["value"], 1) },
    { Vault: vault("dynamic_array", ["value", "timestamp"], 7) },
    "gained member(s) timestamp at entries[i]",
    "array element"
  );
});

test("appended member in static array element is an error", () => {
  assertRejected(
    { Vault: vault("static_array", ["value"], 1) },
    { Vault: vault("static_array", ["value", "timestamp"], 7) },
    "gained member(s) timestamp at entries[i]"
  );
});

test("appended member in array under a mapping is an error", () => {
  assertRejected(
    { Vault: vault("mapping_of_array", ["value"], 1) },
    { Vault: vault("mapping_of_array", ["value", "timestamp"], 7) },
    "gained member(s) timestamp at entries[key][i]"
  );
});

test("appended member in array under a struct is an error", () => {
  assertRejected(
    { Vault: vault("struct_of_array", ["value"], 1) },
    { Vault: vault("struct_of_array", ["value", "timestamp"], 7) },
    "gained member(s) timestamp at entries.items[i]"
  );
});

// An element that gains a member without getting wider - the member lands in the
// padding the element already carried - leaves the stride, and everything stored
// behind the first element, exactly where it was.
test("member appended within array element padding is a review", () => {
  assertReviewOnly(
    { Vault: paddedVault(["amount"], 1) },
    { Vault: paddedVault(["amount", "fee"], 7) },
    "gained member(s) fee at entries[i]",
    "appended within padding"
  );
});

// A mapping value has nothing behind it: every entry starts at its own hash.
test("appended member in a mapping value is a review", () => {
  assertReviewOnly(
    { Vault: vault("mapping", ["value"], 1) },
    { Vault: vault("mapping", ["value", "timestamp"], 7) },
    "gained member(s) timestamp at entries[key]",
    "not an array element"
  );
});

test("appended member in a top level struct is a review", () => {
  assertReviewOnly(
    { Vault: vault("plain", ["value"], 1) },
    { Vault: vault("plain", ["value", "timestamp"], 7) },
    "gained member(s) timestamp at entries",
    "not an array element"
  );
});

test("removed struct member is an error", () => {
  assertRejected(
    { Vault: vault("mapping", ["value", "timestamp"], 1) },
    { Vault: vault("mapping", ["value"], 7) },
    "member timestamp was removed"
  );
});

test("reordered struct members are an error", () => {
  assertRejected(
    { Vault: vault("mapping", ["value", "timestamp"], 1) },
    { Vault: vault("mapping", ["timestamp", "value"], 7) },
    "was value, is now timestamp"
  );
});

test("unchanged layout is compatible", () => {
  assertCompatible(
    { Vault: vault("dynamic_array", ["value", "timestamp"], 1) },
    { Vault: vault("dynamic_array", ["value", "timestamp"], 7) }
  );
});

test("removed function and event are errors", () => {
  assertRejected(
    { Vault: vault("mapping", ["value"], 1) },
    { Vault: vault("mapping", ["value"], 7, []) },
    "function deposit(uint256) was removed",
    "event Deposited(address) was removed"
  );
});

// receive() and fallback() have no signature to key them by, so they are compared
// on their own. Losing either turns a plain transfer into a revert.
test("removed receive is an error", () => {
  assertRejected(
    { Vault: vault("mapping", ["value"], 1, [...ABI, RECEIVE]) },
    { Vault: vault("mapping", ["value"], 7) },
    "receive() was removed"
  );
});

test("removed fallback is an error", () => {
  assertRejected(
    { Vault: vault("mapping", ["value"], 1, [...ABI, PAYABLE_FALLBACK]) },
    { Vault: vault("mapping", ["value"], 7) },
    "fallback() was removed"
  );
});

test("fallback that stops being payable is an error", () => {
  assertRejected(
    { Vault: vault("mapping", ["value"], 1, [...ABI, PAYABLE_FALLBACK]) },
    { Vault: vault("mapping", ["value"], 7, [...ABI, PLAIN_FALLBACK]) },
    "fallback() changed mutability from payable to nonpayable"
  );
});

test("kept receive is compatible", () => {
  assertCompatible(
    { Vault: vault("mapping", ["value"], 1, [...ABI, RECEIVE]) },
    { Vault: vault("mapping", ["value"], 7, [...ABI, RECEIVE]) }
  );
});

// Shrinking a __gap is how new variables are added to an upgradeable contract,
// so it stays a review item: only a human can tell it from an accidental overlap.
test("shrunk gap is a review", () => {
  const types = gapTypes(49, 50);
  const baseline = artifact("Vault", [slotEntry("__gap", 0, gapType(50))], types);
  const current = artifact(
    "Vault",
    [slotEntry("__gap", 0, gapType(49)), slotEntry("treasury", 49, "t_address")],
    types
  );
  assertReviewOnly(
    { Vault: baseline },
    { Vault: current },
    "reserved gap __gap shrank from 50 to 49 slots",
    "new variable treasury sits at slot 49"
  );
});

// The usual spelling of the same upgrade: the new variable is declared in front of
// the gap, which pushes the gap back a slot and shifts the list position of
// everything behind it without moving a byte of state.
test("gap consumed by a new variable is a review", () => {
  const types = gapTypes(49, 50);
  const baseline = artifact(
    "Vault",
    [slotEntry("treasury", 0, "t_address"), slotEntry("__gap", 1, gapType(50))],
    types
  );
  const current = artifact(
    "Vault",
    [
      slotEntry("treasury", 0, "t_address"),
      slotEntry("keeper", 1, "t_address"),
      slotEntry("__gap", 2, gapType(49)),
    ],
    types
  );
  assertReviewOnly({ Vault: baseline }, { Vault: current }, "consumed 1 gap slot(s)");
});

test("gap consumption that moves a later variable is an error", () => {
  const types = gapTypes(50);
  const baseline = artifact(
    "Vault",
    [
      slotEntry("treasury", 0, "t_address"),
      slotEntry("__gap", 1, gapType(50)),
      slotEntry("keeper", 51, "t_address"),
    ],
    types
  );
  // The gap was not shortened to pay for `minter`, so `keeper` is pushed out.
  const current = artifact(
    "Vault",
    [
      slotEntry("treasury", 0, "t_address"),
      slotEntry("minter", 1, "t_address"),
      slotEntry("__gap", 2, gapType(50)),
      slotEntry("keeper", 52, "t_address"),
    ],
    types
  );
  assertRejected(
    { Vault: baseline },
    { Vault: current },
    "variable keeper moved from slot 51+0 to slot 52+0"
  );
});

test("consuming more slots than the gap reserved is an error", () => {
  const types = gapTypes(50, 51);
  const baseline = artifact("Vault", [slotEntry("__gap", 0, gapType(50))], types);
  const current = artifact(
    "Vault",
    [slotEntry("keeper", 0, "t_address"), slotEntry("__gap", 1, gapType(51))],
    types
  );
  assertRejected(
    { Vault: baseline },
    { Vault: current },
    "reserved by __gap at slot 0 now hold data reaching to slot 52"
  );
});

test("variable replaced at its slot is an error", () => {
  const types = gapTypes(50);
  const baseline = artifact(
    "Vault",
    [slotEntry("treasury", 0, "t_address"), slotEntry("__gap", 1, gapType(50))],
    types
  );
  const current = artifact(
    "Vault",
    [slotEntry("keeper", 0, "t_address"), slotEntry("__gap", 1, gapType(50))],
    types
  );
  assertRejected(
    { Vault: baseline },
    { Vault: current },
    "slot 0+0 held treasury, now holds keeper"
  );
});

test("variable that changed type is an error", () => {
  const types = gapTypes(50);
  const baseline = artifact("Vault", [slotEntry("treasury", 0, "t_address")], types);
  const current = artifact("Vault", [slotEntry("treasury", 0, "t_uint256")], types);
  assertRejected(
    { Vault: baseline },
    { Vault: current },
    "variable treasury changed type from address to uint256"
  );
});

// An enum is one byte in the layout whatever it holds, so the member list has to
// be read out of the AST: reordering it reinterprets every value already stored.
test("unchanged enum is compatible", () => {
  assertCompatible(
    { Vault: enumVault(["Pending", "Active"], 1) },
    { Vault: enumVault(["Pending", "Active"], 7) }
  );
});

test("appended enum member is a review", () => {
  assertReviewOnly(
    { Vault: enumVault(["Pending", "Active"], 1) },
    { Vault: enumVault(["Pending", "Active", "Frozen"], 7) },
    "enum Vault.Status gained member(s) Frozen at the end"
  );
});

test("reordered enum members are an error", () => {
  assertRejected(
    { Vault: enumVault(["Pending", "Active"], 1) },
    { Vault: enumVault(["Active", "Pending"], 7) },
    "enum Vault.Status: value 0 was Pending, is now Active"
  );
});

test("enum member inserted before the existing ones is an error", () => {
  assertRejected(
    { Vault: enumVault(["Pending", "Active"], 1) },
    { Vault: enumVault(["Draft", "Pending", "Active"], 7) },
    "enum Vault.Status: value 0 was Pending, is now Draft"
  );
});

test("removed enum member is an error", () => {
  assertRejected(
    { Vault: enumVault(["Pending", "Active"], 1) },
    { Vault: enumVault(["Pending"], 7) },
    "enum Vault.Status: member Active (value 1) was removed"
  );
});

test("reordered enum inside a struct is an error", () => {
  assertRejected(
    { Vault: enumVault(["Pending", "Active"], 1, { nested: true }) },
    { Vault: enumVault(["Active", "Pending"], 7, { nested: true }) },
    "enum Vault.Status: value 0 was Pending, is now Active"
  );
});

test("enum without a definition is a review", () => {
  assertReviewOnly(
    { Vault: enumVault(["Pending", "Active"], 1) },
    { Vault: enumVault(["Pending", "Active"], 7, { withAst: false }) },
    "enum Vault.Status at status is not in the current build's ASTs"
  );
});

// A user defined value type keeps its name, its label and its width when what it
// wraps changes, so the layout is byte for byte the same and the underlying type has
// to be read out of the AST - otherwise `type Amount is int256` replacing
// `type Amount is uint256` reads every balance above int256.max back as negative.
test("unchanged value type is compatible", () => {
  assertCompatible(
    { Vault: valueTypeVault("uint256", 5) },
    { Vault: valueTypeVault("uint256", 11) }
  );
});

test("changed underlying type is an error", () => {
  assertRejected(
    { Vault: valueTypeVault("uint256", 5) },
    { Vault: valueTypeVault("int256", 11) },
    "value type Vault.Amount at total wraps int256 instead of uint256"
  );
});

test("changed underlying type of a struct member is an error", () => {
  assertRejected(
    { Vault: valueTypeVault("uint256", 5, { shape: "struct_member" }) },
    { Vault: valueTypeVault("int256", 11, { shape: "struct_member" }) },
    "value type Vault.Amount at entry.amount wraps int256 instead of uint256"
  );
});

// A value type used as a mapping key decides which slot an entry hashes to, so a
// value that now means something else sends every lookup somewhere else.
test("changed underlying type of a mapping key is an error", () => {
  assertRejected(
    { Vault: valueTypeVault("uint256", 5, { shape: "mapping_key" }) },
    { Vault: valueTypeVault("int256", 11, { shape: "mapping_key" }) },
    "value type Vault.Amount at byAmount[key] wraps int256 instead of uint256"
  );
});

test("value type without a definition is a review", () => {
  assertReviewOnly(
    { Vault: valueTypeVault("uint256", 5) },
    { Vault: valueTypeVault("uint256", 11, { withAst: false }) },
    "value type Vault.Amount at total is not in the current build's ASTs"
  );
});
