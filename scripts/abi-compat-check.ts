#!/usr/bin/env node
/**
 * Checks that the current build stays upgrade-compatible with a baseline build.
 *
 * Both sides are Foundry `out/` directories (the baseline is produced by building an
 * older release with the same toolchain, see .github/workflows/solidity.yml). This
 * replaces the Hardhat-based `@celo/contract-compatibility-check` run and keeps its
 * contract exclusion regex, so the same set of production contracts is covered.
 *
 * Two things are compared for every non-excluded contract under contracts/:
 *
 *   storage layout  Every baseline variable must keep its label, slot, offset and
 *                   type. Variables are matched by the slot and offset they occupy,
 *                   never by their position in the list, so the standard way of
 *                   adding one to an upgradeable contract - declaring it in front of
 *                   a __gap and shortening the gap by what it takes - reads as the
 *                   gap being consumed rather than as every variable behind it being
 *                   renamed. Struct definitions reachable from the layout must keep
 *                   their members, and enum definitions must keep the order of
 *                   theirs: the layout only records that a slot holds a one byte
 *                   enum, not what its values stand for. A user defined value type
 *                   must likewise keep its underlying type, because `type Amount is
 *                   uint256` and `type Amount is int256` are the same slot under the
 *                   same name. New variables are fine as long as they sit past the
 *                   end of the baseline layout; anything placed inside the baseline
 *                   region (typically by shrinking a __gap) is reported for manual
 *                   review because only a human can tell a deliberate gap
 *                   reservation from an accidental overlap.
 *
 *                   Growing a type is only free where nothing sits behind it. Array
 *                   elements are stored back to back from the array's base slot, so
 *                   the element's size is the stride: growing it moves every element
 *                   after the first one and silently reinterprets the state that is
 *                   already there. Growth anywhere below an array element - directly,
 *                   or through a struct member of one - is therefore an error, while
 *                   growth of a mapping value stays a review item, because every
 *                   mapping entry starts at its own hash. An array element that gains
 *                   a member without growing - the member fits into padding the
 *                   element already carried - moves nothing and stays a review item.
 *
 *   ABI             Every baseline function, event and custom error must still exist
 *                   with identical inputs and outputs. Comparison is by canonical
 *                   signature, which is what the selector and the event topic are
 *                   derived from. The receive() and fallback() handlers carry no
 *                   signature and are compared on their own: dropping either, or its
 *                   payable flag, turns a plain transfer into a revert. Additions are
 *                   fine.
 *
 *                   Every parameter's `internalType` is read along the way, tuple
 *                   components included. solc erases an enum parameter to a uint8 and
 *                   a user defined value type parameter to what it wraps, so neither
 *                   the signature nor the selector moves when an enum's members are
 *                   reordered; `internalType` is the only place the declaration is
 *                   still named. The enums and value types the ABI names go through
 *                   the same definition comparison as the ones the layout reaches, so
 *                   an enum that never touches storage is covered too.
 *
 * Findings come in two flavours: ERROR (breaks a deployed proxy, exit status 1) and
 * REVIEW (legal in principle but a human has to confirm the intent, exit status 0).
 *
 * Usage:
 *   node scripts/abi-compat-check.ts --baseline /path/to/release/out --current out
 */
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

// Same exclusion regex the Hardhat compatibility job used: mocks, test helpers,
// interfaces, proxies and the contracts inherited from the Celo monorepo are not
// deployed behind a proxy, so their layout and ABI may change freely.
export const DEFAULT_EXCLUDE =
  ".*Test|Mock.*|I[A-Z].*|.*Proxy|ReleaseGold|SlasherUtil|UsingPrecompiles|^UsingRegistry|ERC20.*|^Managed$";

// solc appends the declaration's AST id to struct, enum, contract and user defined
// value type identifiers. The id shifts whenever anything above the declaration
// moves, so it carries no layout information and has to go before comparing.
// The number in t_array(...)N_storage is the array length and must be kept.
const AST_ID = /(t_(?:struct|enum|contract|userDefinedValueType)\([^)]*\))\d+/g;

// The declared name inside an enum type identifier, `Status` in t_enum(Status)42.
// Unlike the layout's label it is not qualified by the declaring contract.
const ENUM_TYPE = /^t_enum\(([^)]*)\)/;

// The same for a user defined value type, `Amount` in t_userDefinedValueType(Amount)42.
const VALUE_TYPE = /^t_userDefinedValueType\(([^)]*)\)/;

// The N of a `uint256[N]` label, which is how long a reserved gap is.
const ARRAY_LENGTH = /^.*\[(\d+)\]$/;

// The `[3][]` tail of an ABI parameter's `internalType`, e.g. `enum Vault.Mode[3][]`.
// Only the element type names a declaration.
const INTERNAL_ARRAY = /(?:\[\d*\])+$/;

// An `internalType` naming one of Solidity's own types rather than a declared one.
const ELEMENTARY = /^(?:u?int\d*|address(?: payable)?|bool|string|bytes\d*|u?fixed\d*(?:x\d+)?)$/;

// A declared name, optionally qualified by the contract declaring it. That is all an
// `internalType` consists of for a user defined value type, and all that is left of an
// enum's once the `enum ` in front of it is gone.
const DECLARED_NAME = /^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*$/;

export const ERROR = "ERROR";
export const REVIEW = "REVIEW";

export type Level = "ERROR" | "REVIEW";

export type Finding = {
  level: Level;
  name: string;
  message: string;
};

export type StorageEntry = {
  label: string;
  slot: string;
  offset: number | string;
  type: string;
};

export type TypeInfo = {
  label?: string;
  encoding?: string;
  numberOfBytes?: string;
  base?: string;
  key?: string;
  value?: string;
  members?: StorageEntry[];
};

export type TypesMap = Record<string, TypeInfo>;

export type StorageLayout = {
  storage?: StorageEntry[];
  types?: TypesMap;
};

export type AbiParameter = {
  name?: string;
  type: string;
  internalType?: string;
  indexed?: boolean;
  components?: AbiParameter[];
};

export type AbiEntry = {
  type?: string;
  name?: string;
  inputs?: AbiParameter[];
  outputs?: AbiParameter[];
  stateMutability?: string;
  anonymous?: boolean;
};

export type AstNode = {
  nodeType?: string;
  name?: string;
  canonicalName?: string;
  nodes?: AstNode[];
  members?: AstNode[];
  underlyingType?: {
    nodeType?: string;
    name?: string;
    typeDescriptions?: { typeString?: string; typeIdentifier?: string };
  };
};

export type Artifact = {
  metadata?: { settings?: { compilationTarget?: Record<string, string> } };
  storageLayout?: StorageLayout;
  abi?: AbiEntry[];
  ast?: AstNode;
};

/** The enum and user defined value type declarations of one whole build, keyed by kind. */
export type Definitions = {
  enum: Map<string, string[]>;
  value_type: Map<string, string>;
};

/**
 * One enum or value type the layout or the ABI walk reached, keyed by the pair of names
 * the two sides know it under. `cur` is null where the walk found something else
 * opposite.
 */
export type ReachedEntry = {
  base: string;
  cur: string | null;
  path: string;
};

export type Reached = Map<string, ReachedEntry>;

export type ReachedSets = {
  enum: Reached;
  value_type: Reached;
};

/** The kind and qualified name an ABI parameter's `internalType` declares. */
export type NamedType = {
  kind: "enum" | "value_type";
  name: string;
};

/** Orders strings by code unit, the way Python's `sorted` orders them by code point. */
function compareStrings(left: string, right: string): number {
  if (left < right) {
    return -1;
  }
  return left > right ? 1 : 0;
}

function toInt(value: unknown, fallback: number): number {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  const parsed = Number(value);
  return Number.isNaN(parsed) ? fallback : Math.trunc(parsed);
}

export function normalizeType(typeId: string): string {
  return typeId.replace(AST_ID, "$1");
}

/**
 * Every file level and contract level node of one source unit AST.
 *
 * Solidity only allows an enum or a user defined value type at either level, so the
 * two outermost node lists are the whole search space - no need to walk the statement
 * trees. `canonicalName` is what the storage layout's label spells out
 * ("Vault.Status"), and is just the declared name for a file level declaration.
 */
export function declarations(ast: AstNode | undefined): AstNode[] {
  const found: AstNode[] = [];
  for (const node of ast?.nodes ?? []) {
    found.push(node);
    for (const inner of node.nodes ?? []) {
      found.push(inner);
    }
  }
  return found;
}

/** Yields [qualified name, member names] for every enum of one source unit AST. */
export function enumDefinitions(ast: AstNode | undefined): Array<[string, string[]]> {
  const found: Array<[string, string[]]> = [];
  for (const node of declarations(ast)) {
    if (node.nodeType !== "EnumDefinition") {
      continue;
    }
    const name = node.canonicalName || node.name;
    if (name) {
      found.push([name, (node.members ?? []).map((member) => member.name ?? "")]);
    }
  }
  return found;
}

/**
 * Yields [qualified name, underlying type] for every user defined value type.
 *
 * The underlying type appears nowhere in the storage layout: `Amount` reads as one
 * 32 byte slot whether it wraps a uint256 or an int256, and even the type identifier
 * spells out no more than the name, so it has to come from the AST.
 */
export function valueTypeDefinitions(ast: AstNode | undefined): Array<[string, string]> {
  const found: Array<[string, string]> = [];
  for (const node of declarations(ast)) {
    if (node.nodeType !== "UserDefinedValueTypeDefinition") {
      continue;
    }
    const name = node.canonicalName || node.name;
    const descriptions = node.underlyingType?.typeDescriptions ?? {};
    const underlying = descriptions.typeString || descriptions.typeIdentifier;
    if (name && underlying) {
      found.push([name, underlying]);
    }
  }
  return found;
}

/**
 * What the ASTs say a named type is made of, or null when they do not pin it down.
 *
 * The layout's label is qualified, the type identifier is not, so the lookup falls
 * back to the declared name. Several contracts may declare the same name; that is
 * only good enough while they all declare it the same way.
 */
export function lookupDefinition<T>(
  definitions: Map<string, T>,
  label: string,
  equal: (left: T, right: T) => boolean
): T | null {
  const direct = definitions.get(label);
  if (direct !== undefined) {
    return direct;
  }
  const declared = label.slice(label.lastIndexOf(".") + 1);
  const matches: T[] = [];
  for (const [name, madeOf] of definitions) {
    if (name.slice(name.lastIndexOf(".") + 1) === declared) {
      matches.push(madeOf);
    }
  }
  const first = matches[0];
  if (first !== undefined && matches.every((madeOf) => equal(madeOf, first))) {
    return first;
  }
  return null;
}

function sameMembers(left: string[], right: string[]): boolean {
  return left.length === right.length && left.every((member, index) => member === right[index]);
}

function sameUnderlying(left: string, right: string): boolean {
  return left === right;
}

/** Every directory under `root` with its own file names, `build-info` pruned away. */
function walk(root: string): Array<{ directory: string; files: string[] }> {
  const visited: Array<{ directory: string; files: string[] }> = [];
  const pending = [root];
  while (pending.length > 0) {
    const directory = pending.pop() as string;
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(directory, { withFileTypes: true });
    } catch {
      continue;
    }
    const files: string[] = [];
    const directories: string[] = [];
    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (entry.name !== "build-info") {
          directories.push(entry.name);
        }
      } else {
        files.push(entry.name);
      }
    }
    files.sort(compareStrings);
    directories.sort(compareStrings);
    visited.push({ directory, files });
    for (let index = directories.length - 1; index >= 0; index -= 1) {
      pending.push(path.join(directory, directories[index] as string));
    }
  }
  return visited;
}

/**
 * Maps contract name -> artifact for the compiled sources under sourcePrefix.
 *
 * Returns the AST level definitions of the whole build alongside, keyed by kind, the
 * excluded sources included: an enum or a value type a checked contract stores is
 * often declared by an interface or by one of the inherited OpenZeppelin contracts,
 * whose own layout is not checked.
 */
export function loadArtifacts(
  outDir: string,
  exclude: RegExp,
  sourcePrefix: string
): { artifacts: Map<string, Artifact>; definitions: Definitions } {
  const artifacts = new Map<string, Artifact>();
  const definitions: Definitions = { enum: new Map(), value_type: new Map() };
  for (const { directory, files } of walk(outDir)) {
    const present = new Set(files);
    for (const filename of files) {
      // Foundry names the artifact <Contract>.json, or <Contract>.default.json
      // when the contract is also built under one of the additional compiler
      // profiles. Only the default profile describes what gets deployed.
      if (!filename.endsWith(".json")) {
        continue;
      }
      const stripped = filename.slice(0, -".json".length);
      const dot = stripped.indexOf(".");
      const stem = dot === -1 ? stripped : stripped.slice(0, dot);
      const profile = dot === -1 ? "" : stripped.slice(dot + 1);
      if (profile && (profile !== "default" || present.has(`${stem}.json`))) {
        continue;
      }
      const artifact = JSON.parse(
        fs.readFileSync(path.join(directory, filename), "utf8")
      ) as Artifact;
      for (const [name, members] of enumDefinitions(artifact.ast)) {
        definitions.enum.set(name, members);
      }
      for (const [name, underlying] of valueTypeDefinitions(artifact.ast)) {
        definitions.value_type.set(name, underlying);
      }
      const compiled = Object.entries(artifact.metadata?.settings?.compilationTarget ?? {});
      const target = compiled[0];
      if (target === undefined) {
        continue;
      }
      const [source, name] = target;
      if (!source.startsWith(sourcePrefix) || exclude.test(name)) {
        continue;
      }
      artifacts.set(name, artifact);
    }
  }
  return { artifacts, definitions };
}

/** Number of slots the variable occupies, starting at its own slot. */
export function slotSpan(entry: StorageEntry, types: TypesMap): number {
  const size = toInt(types[entry.type]?.numberOfBytes, 32);
  return Math.max(1, Math.ceil(size / 32));
}

export function layoutEnd(storage: StorageEntry[], types: TypesMap): number {
  let end = 0;
  for (const entry of storage) {
    end = Math.max(end, toInt(entry.slot, 0) + slotSpan(entry, types));
  }
  return end;
}

/** The (slot, offset) a variable sits at - its only identity across builds. */
function position(entry: StorageEntry): string {
  return `${toInt(entry.slot, 0)}:${toInt(entry.offset, 0)}`;
}

function isGap(entry: StorageEntry): boolean {
  return entry.label.startsWith("__gap");
}

/**
 * Canonical name of a type identifier, free of AST ids.
 *
 * solc's own `label` is fully qualified ("struct SortedLinkedList.List"), which
 * the identifier is not: two different libraries in the same layout can both
 * define a `List`, so the identifier alone is ambiguous even after stripping the
 * AST id. Fall back to the stripped identifier for types with no entry.
 */
export function typeLabel(typeId: string, types: TypesMap): string {
  return types[typeId]?.label || normalizeType(typeId);
}

/** Qualified name of an enum type, e.g. `Vault.Status`, or null for other types. */
function enumLabel(typeId: string, definition: TypeInfo | undefined): string | null {
  if (!typeId.startsWith("t_enum(")) {
    return null;
  }
  const label = definition?.label ?? "";
  if (label.startsWith("enum ")) {
    return label.slice("enum ".length);
  }
  const match = ENUM_TYPE.exec(typeId);
  return match === null ? null : (match[1] as string);
}

/**
 * Qualified name of a user defined value type, e.g. `Vault.Amount`, or null.
 *
 * solc writes the canonical name out as the layout label - `Vault.Amount` for a
 * contract level declaration, the bare name for a file level one - with none of the
 * `enum ` style prefix it puts in front of an enum's. The identifier carries the
 * unqualified name only and serves as the fallback.
 */
function valueTypeLabel(typeId: string, definition: TypeInfo | undefined): string | null {
  if (!typeId.startsWith("t_userDefinedValueType(")) {
    return null;
  }
  const label = definition?.label;
  if (label) {
    return label;
  }
  const match = VALUE_TYPE.exec(typeId);
  return match === null ? null : (match[1] as string);
}

function arrayLength(label: string): number | null {
  const match = ARRAY_LENGTH.exec(label);
  return match === null ? null : Number.parseInt(match[1] as string, 10);
}

function typeSize(definition: TypeInfo): number {
  return toInt(definition.numberOfBytes, 32);
}

function remember(reached: Reached, base: string, cur: string | null, walked: string): void {
  const key = JSON.stringify([base, cur]);
  if (!reached.has(key)) {
    reached.set(key, { base, cur, path: walked });
  }
}

/** The reached types ordered by the baseline name, the way Python's stable sort does. */
function byBaselineName(reached: Reached): ReachedEntry[] {
  return [...reached.values()].sort((left, right) => compareStrings(left.base, right.base));
}

/**
 * Compares two type definitions and everything reachable from them.
 *
 * Both sides are walked in lockstep so each identifier is resolved in its own
 * types map; nothing is ever looked up across builds, where the AST ids differ.
 *
 * `stride` says whether the size of this type decides where other data lives,
 * which is what turns a growth from a review item into an error. It is set when
 * descending into an array's element type and stays set for everything that
 * contributes to that element's size (its struct members, and their members in
 * turn). It is cleared again under a mapping value, whose entries are each
 * addressed by their own hash and so have nothing sitting behind them.
 *
 * `reached` collects the enum and user defined value types the walk reaches, keyed by
 * kind and then by the pair of names the two sides know them under, so what they are
 * made of can be compared against the ASTs afterwards. The layout itself says no more
 * than "one byte" for an enum and "one slot named Amount" for a value type, so a
 * reordered enum and a re-wrapped value type are both invisible here.
 *
 * `walked` is the access path the type was reached by, e.g. `withdrawals[key][i]`,
 * and only serves to make the findings readable.
 */
export function checkType(
  name: string,
  baseId: string,
  baseTypes: TypesMap,
  curId: string,
  curTypes: TypesMap,
  findings: Finding[],
  seen: Set<string>,
  reached: ReachedSets,
  stride: boolean,
  walked: string
): void {
  const visit = `${baseId} ${curId} ${stride ? "1" : "0"}`;
  if (seen.has(visit)) {
    return;
  }
  seen.add(visit);

  const baseType = baseTypes[baseId];
  const curType = curTypes[curId];
  if (baseType === undefined || curType === undefined) {
    return;
  }

  const before = findings.length;

  const baseEnum = enumLabel(baseId, baseType);
  if (baseEnum) {
    remember(reached.enum, baseEnum, enumLabel(curId, curType), walked);
  }

  const baseValueType = valueTypeLabel(baseId, baseType);
  if (baseValueType) {
    remember(reached.value_type, baseValueType, valueTypeLabel(curId, curType), walked);
  }

  // Only array types carry a `base`, both the static t_array(...)N_storage and
  // the dynamic t_array(...)dyn_storage kind: in either the elements are packed
  // one after another, so the element size is the distance between them.
  if (baseType.base !== undefined && curType.base !== undefined) {
    checkType(
      name,
      baseType.base,
      baseTypes,
      curType.base,
      curTypes,
      findings,
      seen,
      reached,
      true,
      `${walked}[i]`
    );
  }
  if (baseType.value !== undefined && curType.value !== undefined) {
    checkType(
      name,
      baseType.value,
      baseTypes,
      curType.value,
      curTypes,
      findings,
      seen,
      reached,
      false,
      `${walked}[key]`
    );
  }
  // The key decides which slot an entry hashes to, so an enum or a value type used as
  // one carries the same meaning as one that is stored. Nothing else about a key can
  // move.
  if (baseType.key !== undefined && curType.key !== undefined) {
    checkType(
      name,
      baseType.key,
      baseTypes,
      curType.key,
      curTypes,
      findings,
      seen,
      reached,
      false,
      `${walked}[key]`
    );
  }

  const label = baseType.label ?? baseId;
  const baseMembers = baseType.members;
  const curMembers = curType.members;
  if (baseMembers !== undefined && curMembers === undefined) {
    findings.push({ level: ERROR, name, message: `${label} is no longer a struct` });
    return;
  }

  if (baseMembers !== undefined && curMembers !== undefined) {
    for (let index = 0; index < baseMembers.length; index += 1) {
      const baseMember = baseMembers[index] as StorageEntry;
      if (index >= curMembers.length) {
        findings.push({
          level: ERROR,
          name,
          message: `${label}: member ${baseMember.label} was removed`,
        });
        continue;
      }
      const curMember = curMembers[index] as StorageEntry;
      const baseMemberType = typeLabel(baseMember.type, baseTypes);
      const curMemberType = typeLabel(curMember.type, curTypes);
      if (baseMember.label !== curMember.label) {
        findings.push({
          level: ERROR,
          name,
          message:
            `${label}: slot ${baseMember.slot} was ${baseMember.label}, ` +
            `is now ${curMember.label}`,
        });
      } else if (baseMemberType !== curMemberType) {
        findings.push({
          level: ERROR,
          name,
          message:
            `${label}: member ${baseMember.label} changed type from ` +
            `${baseMemberType} to ${curMemberType}`,
        });
      } else if (baseMember.slot !== curMember.slot || baseMember.offset !== curMember.offset) {
        findings.push({
          level: ERROR,
          name,
          message:
            `${label}: member ${baseMember.label} moved from ` +
            `slot ${baseMember.slot}+${baseMember.offset} to ` +
            `slot ${curMember.slot}+${curMember.offset}`,
        });
      } else {
        checkType(
          name,
          baseMember.type,
          baseTypes,
          curMember.type,
          curTypes,
          findings,
          seen,
          reached,
          stride,
          `${walked}.${baseMember.label}`
        );
      }
    }

    if (curMembers.length > baseMembers.length) {
      const added = curMembers
        .slice(baseMembers.length)
        .map((member) => member.label)
        .join(", ");
      // An array element only moves the elements behind it when it actually
      // gets wider. Members that fit into the padding the element already
      // carried (a second uint128 next to the first) leave the stride alone.
      let level: Level;
      let message: string;
      if (stride && typeSize(baseType) !== typeSize(curType)) {
        level = ERROR;
        message =
          `${label} gained member(s) ${added} at ${walked}; it is an array element, so every ` +
          "element behind the first one moves and existing entries are misread";
      } else if (stride) {
        level = REVIEW;
        message =
          `${label} gained member(s) ${added} at ${walked}; it is an array element, but it still ` +
          `measures ${typeSize(curType)} bytes, so the member(s) were appended within padding ` +
          "and no element moves - confirm those bytes were never written";
      } else {
        level = REVIEW;
        message =
          `${label} gained member(s) ${added} at ${walked}; not an array element (a mapping ` +
          "value starts at its own hash, a top level struct is followed by free slots), so " +
          "existing entries keep their meaning - confirm the slots it grows into are unused";
      }
      findings.push({ level, name, message });
    }
  }

  // Catches the size changes the member walk above cannot see, e.g. a fixed array
  // member whose element type grew. Skipped when something below already reported,
  // because that finding is the same growth, named at the place it happens.
  if (stride && typeSize(baseType) !== typeSize(curType) && findings.length === before) {
    findings.push({
      level: ERROR,
      name,
      message:
        `${label} at ${walked} grew from ${typeSize(baseType)} to ${typeSize(curType)} bytes; ` +
        "it is an array element, so every element behind the first one moves and existing " +
        "entries are misread",
    });
  }
}

/**
 * Compares the member lists of the enums the layout and the ABI walks reached.
 *
 * An enum is one byte in the layout whatever its members are, and a plain uint8 in the
 * ABI, so reordering them or inserting one in front silently changes what the values
 * already in storage - and the ordinals callers already encode - stand for. The member
 * lists only exist in the ASTs, which is why they are looked up per build and by name.
 */
export function checkEnums(
  name: string,
  reached: Reached,
  baseEnums: Map<string, string[]>,
  curEnums: Map<string, string[]>,
  findings: Finding[]
): void {
  for (const { base, cur, path: walked } of byBaselineName(reached)) {
    const baseMembers = lookupDefinition(baseEnums, base, sameMembers);
    const curMembers = lookupDefinition(curEnums, cur || base, sameMembers);
    if (baseMembers === null || curMembers === null) {
      const missing: string[] = [];
      if (baseMembers === null) {
        missing.push("baseline");
      }
      if (curMembers === null) {
        missing.push("current");
      }
      findings.push({
        level: REVIEW,
        name,
        message:
          `enum ${base} at ${walked} is not in the ${missing.join(" or the ")} build's ASTs; ` +
          "the order of its members could not be compared",
      });
      continue;
    }
    for (let index = 0; index < baseMembers.length; index += 1) {
      const member = baseMembers[index] as string;
      if (index >= curMembers.length) {
        findings.push({
          level: ERROR,
          name,
          message: `enum ${base}: member ${member} (value ${index}) was removed`,
        });
      } else if (curMembers[index] !== member) {
        findings.push({
          level: ERROR,
          name,
          message: `enum ${base}: value ${index} was ${member}, is now ${curMembers[index]}`,
        });
      }
    }
    if (curMembers.length > baseMembers.length) {
      const added = curMembers.slice(baseMembers.length).join(", ");
      findings.push({
        level: REVIEW,
        name,
        message:
          `enum ${base} gained member(s) ${added} at the end; the values already stored keep ` +
          "their meaning - confirm nothing switches on the member count",
      });
    }
  }
}

/**
 * Compares the underlying types of the value types the layout and the ABI walks reached.
 *
 * `type Amount is uint256` and `type Amount is int256` occupy the same slot under the
 * same name, and even share a type identifier once the AST id is stripped, so the
 * layout cannot tell one from the other. Swapping them makes every stored value above
 * int256.max read back negative, which is why the underlying type is looked up in the
 * ASTs per build, the way an enum's members are.
 */
export function checkUserDefinedValueTypes(
  name: string,
  reached: Reached,
  baseValueTypes: Map<string, string>,
  curValueTypes: Map<string, string>,
  findings: Finding[]
): void {
  // Sorted by the baseline name alone: the current one is null where the walk found
  // something other than a value type opposite.
  for (const { base, cur, path: walked } of byBaselineName(reached)) {
    const baseUnderlying = lookupDefinition(baseValueTypes, base, sameUnderlying);
    const curUnderlying = lookupDefinition(curValueTypes, cur || base, sameUnderlying);
    if (baseUnderlying === null || curUnderlying === null) {
      const missing: string[] = [];
      if (baseUnderlying === null) {
        missing.push("baseline");
      }
      if (curUnderlying === null) {
        missing.push("current");
      }
      findings.push({
        level: REVIEW,
        name,
        message:
          `value type ${base} at ${walked} is not in the ${missing.join(" or the ")} build's ` +
          "ASTs; its underlying type could not be compared",
      });
    } else if (baseUnderlying !== curUnderlying) {
      findings.push({
        level: ERROR,
        name,
        message:
          `value type ${base} at ${walked} wraps ${curUnderlying} instead of ` +
          `${baseUnderlying}; the slot is unchanged, so every value already stored is ` +
          "reinterpreted",
      });
    }
  }
}

/**
 * Reports what became of the slots a baseline __gap reserved.
 *
 * Adding a variable to an upgradeable contract means spending gap slots: the new
 * variable is declared in front of the __gap and the gap is shortened by what the
 * variable takes, so nothing behind it moves. Both spellings of that show up here,
 * the gap staying put and getting shorter, and the gap being pushed back by the new
 * variables, and both are review items - only a human can tell a deliberate
 * reservation from an accidental overlap. What is not allowed is the replacement
 * reaching past the last slot the gap reserved, because then the layout behind it
 * moves after all.
 */
export function checkGaps(
  name: string,
  baseStorage: StorageEntry[],
  baseTypes: TypesMap,
  curStorage: StorageEntry[],
  curTypes: TypesMap,
  findings: Finding[]
): void {
  const curAt = new Map<string, StorageEntry>();
  for (const entry of curStorage) {
    curAt.set(position(entry), entry);
  }
  for (const baseEntry of baseStorage) {
    if (!isGap(baseEntry)) {
      continue;
    }
    const label = baseEntry.label;
    const start = toInt(baseEntry.slot, 0);
    const end = start + slotSpan(baseEntry, baseTypes);
    const fillers = curStorage.filter((entry) => {
      const slot = toInt(entry.slot, 0);
      return slot >= start && slot < end;
    });
    let reach = end;
    for (const entry of fillers) {
      reach = Math.max(reach, toInt(entry.slot, 0) + slotSpan(entry, curTypes));
    }
    if (reach > end) {
      findings.push({
        level: ERROR,
        name,
        message:
          `the ${
            end - start
          } slot(s) reserved by ${label} at slot ${start} now hold data reaching ` +
          `to slot ${reach}; everything behind the gap moves`,
      });
      continue;
    }

    const curEntry = curAt.get(position(baseEntry));
    if (curEntry !== undefined && isGap(curEntry)) {
      // The gap kept its first slot, so only its length can have changed.
      const baseType = typeLabel(baseEntry.type, baseTypes);
      const curType = typeLabel(curEntry.type, curTypes);
      if (baseType === curType) {
        continue;
      }
      const baseLength = arrayLength(baseType);
      const curLength = arrayLength(curType);
      if (baseLength === null || curLength === null || curLength > baseLength) {
        findings.push({
          level: ERROR,
          name,
          message: `variable ${label} changed type from ${baseType} to ${curType}`,
        });
      } else {
        findings.push({
          level: REVIEW,
          name,
          message:
            `reserved gap ${label} shrank from ${baseLength} to ${curLength} slots; the freed ` +
            "slots must hold the newly added variables",
        });
      }
      continue;
    }

    // The gap no longer starts where it did: new variables took its first slots
    // and the remainder of the gap, if any, was pushed back behind them.
    let kept = 0;
    for (const entry of fillers) {
      if (isGap(entry)) {
        kept += slotSpan(entry, curTypes);
      }
    }
    const consumed = end - start - kept;
    findings.push({
      level: REVIEW,
      name,
      message:
        `reserved gap ${label} at slot ${start} consumed ${consumed} gap slot(s); the rest of the ` +
        `layout stays put, confirm the ${consumed} slot(s) were never written`,
    });
  }
}

export function checkStorage(
  name: string,
  baseline: Artifact,
  current: Artifact,
  reached: ReachedSets,
  findings: Finding[]
): void {
  const baseLayout = baseline.storageLayout ?? {};
  const curLayout = current.storageLayout ?? {};
  const baseStorage = baseLayout.storage ?? [];
  const baseTypes = baseLayout.types ?? {};
  const curStorage = curLayout.storage ?? [];
  const curTypes = curLayout.types ?? {};

  const seenStructs = new Set<string>();
  const curAt = new Map<string, StorageEntry>();
  for (const entry of curStorage) {
    curAt.set(position(entry), entry);
  }

  // Variables are matched by the slot and offset they occupy, never by their index
  // in the list: labels repeat (every inherited upgradeable contract brings its own
  // __gap) and a variable added in front of a __gap shifts the index of everything
  // behind it without moving a byte of state. The gaps themselves are left to
  // checkGaps, which is the only place where a replacement is legitimate.
  for (const baseEntry of baseStorage) {
    if (isGap(baseEntry)) {
      continue;
    }
    const label = baseEntry.label;
    const curEntry = curAt.get(position(baseEntry));
    if (curEntry === undefined) {
      const moved = curStorage.find((entry) => entry.label === label && !isGap(entry));
      if (moved === undefined) {
        findings.push({
          level: ERROR,
          name,
          message: `variable ${label} (slot ${baseEntry.slot}) was removed`,
        });
      } else {
        findings.push({
          level: ERROR,
          name,
          message:
            `variable ${label} moved from slot ${baseEntry.slot}+${baseEntry.offset} ` +
            `to slot ${moved.slot}+${moved.offset}`,
        });
      }
      continue;
    }
    if (curEntry.label !== label) {
      findings.push({
        level: ERROR,
        name,
        message:
          `slot ${baseEntry.slot}+${baseEntry.offset} held ${label}, now holds ` +
          `${curEntry.label}`,
      });
      continue;
    }
    const baseType = typeLabel(baseEntry.type, baseTypes);
    const curType = typeLabel(curEntry.type, curTypes);
    if (baseType !== curType) {
      findings.push({
        level: ERROR,
        name,
        message: `variable ${label} changed type from ${baseType} to ${curType}`,
      });
    } else {
      // A top level variable has no stride of its own: anything that grows
      // behind it shows up as the next variable having moved.
      checkType(
        name,
        baseEntry.type,
        baseTypes,
        curEntry.type,
        curTypes,
        findings,
        seenStructs,
        reached,
        false,
        label
      );
    }
  }

  checkGaps(name, baseStorage, baseTypes, curStorage, curTypes, findings);

  const baseAt = new Set(baseStorage.map(position));
  const baseEnd = layoutEnd(baseStorage, baseTypes);
  for (const curEntry of curStorage) {
    // A gap that moved is reported by checkGaps, as part of the gap it came from.
    if (isGap(curEntry) || baseAt.has(position(curEntry)) || toInt(curEntry.slot, 0) >= baseEnd) {
      continue;
    }
    findings.push({
      level: REVIEW,
      name,
      message:
        `new variable ${curEntry.label} sits at slot ${curEntry.slot}, inside the ` +
        `baseline layout (which ends at slot ${baseEnd}); confirm it only consumes gap space`,
    });
  }
}

/**
 * The enum or user defined value type an ABI parameter was declared as, or null.
 *
 * solc erases both from the parameter's `type`: an enum comes out as `uint8` and a value
 * type as whatever it wraps, so reordering an enum's members leaves the canonical
 * signature - and with it the selector and the event topic - exactly as it was, while
 * every caller compiled against the old declaration keeps sending the old ordinal.
 * `internalType` is the only place the declaration is still named: `enum Vault.Mode` for
 * a contract level enum, `enum Mode` for a file level one, the bare canonical name for a
 * value type, and any of those with an array tail where the parameter is an array.
 *
 * Everything else solc qualifies with a keyword (`struct Vault.Entry`, `contract IVault`)
 * or spells out in full (a function type), so what is left unqualified is either one of
 * Solidity's own types or a value type.
 */
export function declaredType(internalType: string | undefined): NamedType | null {
  if (internalType === undefined) {
    return null;
  }
  const element = internalType.replace(INTERNAL_ARRAY, "");
  if (element.startsWith("enum ")) {
    const named = element.slice("enum ".length);
    return DECLARED_NAME.test(named) ? { kind: "enum", name: named } : null;
  }
  if (!DECLARED_NAME.test(element) || ELEMENTARY.test(element)) {
    return null;
  }
  return { kind: "value_type", name: element };
}

/**
 * Records what one parameter list was declared as, tuple components included.
 *
 * The two sides are walked in lockstep by position: the entry they belong to was matched
 * by its canonical signature, so both lists have the same shape down to the last
 * component. Names already reached through the storage layout are kept as they were
 * found there, so an enum that is both stored and passed is reported once.
 */
function rememberParameters(
  baseParams: AbiParameter[] | undefined,
  curParams: AbiParameter[] | undefined,
  reached: ReachedSets,
  walked: string
): void {
  const base = baseParams ?? [];
  const cur = curParams ?? [];
  for (let index = 0; index < base.length; index += 1) {
    const baseParam = base[index] as AbiParameter;
    const curParam = cur[index];
    const here = `${walked}.${baseParam.name || index}`;
    const declared = declaredType(baseParam.internalType);
    if (declared !== null) {
      const opposite = declaredType(curParam?.internalType);
      const sameKind = opposite !== null && opposite.kind === declared.kind;
      remember(reached[declared.kind], declared.name, sameKind ? opposite.name : null, here);
    }
    rememberParameters(baseParam.components, curParam?.components, reached, here);
  }
}

/** The enums and value types both sides of one matched function, event or error name. */
function rememberSignature(sig: string, base: AbiEntry, cur: AbiEntry, reached: ReachedSets): void {
  rememberParameters(base.inputs, cur.inputs, reached, sig);
  rememberParameters(base.outputs, cur.outputs, reached, `${sig} returns`);
}

export function canonicalType(item: AbiParameter): string {
  if (item.type.startsWith("tuple")) {
    const inner = (item.components ?? []).map((component) => canonicalType(component)).join(",");
    return `(${inner})${item.type.slice("tuple".length)}`;
  }
  return item.type;
}

export function signature(entry: AbiEntry): string {
  const inputs = (entry.inputs ?? []).map((input) => canonicalType(input)).join(",");
  return `${entry.name ?? ""}(${inputs})`;
}

function outputs(entry: AbiEntry): string {
  return (entry.outputs ?? []).map((output) => canonicalType(output)).join(",");
}

function indexedFlags(entry: AbiEntry): boolean[] {
  return (entry.inputs ?? []).map((input) => Boolean(input.indexed));
}

function abiIndex(abi: AbiEntry[], kind: string): Map<string, AbiEntry> {
  const index = new Map<string, AbiEntry>();
  for (const entry of abi) {
    if (entry.type === kind) {
      index.set(signature(entry), entry);
    }
  }
  return index;
}

function sortedKeys(index: Map<string, AbiEntry>): string[] {
  return [...index.keys()].sort(compareStrings);
}

export function checkMutability(
  name: string,
  sig: string,
  base: AbiEntry,
  cur: AbiEntry,
  findings: Finding[]
): void {
  const baseMutability = base.stateMutability ?? "nonpayable";
  const curMutability = cur.stateMutability ?? "nonpayable";
  if (baseMutability === curMutability) {
    return;
  }
  const readOnly = ["view", "pure"];
  const breaking =
    (readOnly.includes(baseMutability) && !readOnly.includes(curMutability)) ||
    (baseMutability === "payable" && curMutability !== "payable");
  findings.push({
    level: breaking ? ERROR : REVIEW,
    name,
    message: `function ${sig} changed mutability from ${baseMutability} to ${curMutability}`,
  });
}

/**
 * Compares the receive() or fallback() handler, which has no signature.
 *
 * Both are unnamed and take no arguments, so they cannot be keyed like the rest of
 * the ABI and a contract has at most one of each. Losing the handler turns every
 * plain transfer into a revert, and so does dropping its payable flag; a handler
 * that was not payable and becomes one changes what a transfer does just as much,
 * so any change at all is reported.
 */
export function checkHandler(
  name: string,
  kind: string,
  baseAbi: AbiEntry[],
  curAbi: AbiEntry[],
  findings: Finding[]
): void {
  const baseEntry = baseAbi.find((entry) => entry.type === kind);
  if (baseEntry === undefined) {
    return;
  }
  const curEntry = curAbi.find((entry) => entry.type === kind);
  if (curEntry === undefined) {
    findings.push({ level: ERROR, name, message: `${kind}() was removed` });
    return;
  }
  const baseMutability = baseEntry.stateMutability ?? "nonpayable";
  const curMutability = curEntry.stateMutability ?? "nonpayable";
  if (baseMutability !== curMutability) {
    findings.push({
      level: ERROR,
      name,
      message: `${kind}() changed mutability from ${baseMutability} to ${curMutability}`,
    });
  }
}

export function checkAbi(
  name: string,
  baseline: Artifact,
  current: Artifact,
  reached: ReachedSets,
  findings: Finding[]
): void {
  const baseAbi = baseline.abi ?? [];
  const curAbi = current.abi ?? [];

  const baseFunctions = abiIndex(baseAbi, "function");
  const curFunctions = abiIndex(curAbi, "function");
  for (const sig of sortedKeys(baseFunctions)) {
    const baseEntry = baseFunctions.get(sig) as AbiEntry;
    const curEntry = curFunctions.get(sig);
    if (curEntry === undefined) {
      findings.push({ level: ERROR, name, message: `function ${sig} was removed` });
      continue;
    }
    rememberSignature(sig, baseEntry, curEntry, reached);
    if (outputs(baseEntry) !== outputs(curEntry)) {
      findings.push({
        level: ERROR,
        name,
        message: `function ${sig} returns (${outputs(curEntry)}) instead of (${outputs(
          baseEntry
        )})`,
      });
    }
    checkMutability(name, sig, baseEntry, curEntry, findings);
  }

  for (const kind of ["receive", "fallback"]) {
    checkHandler(name, kind, baseAbi, curAbi, findings);
  }

  const baseEvents = abiIndex(baseAbi, "event");
  const curEvents = abiIndex(curAbi, "event");
  for (const sig of sortedKeys(baseEvents)) {
    const baseEntry = baseEvents.get(sig) as AbiEntry;
    const curEntry = curEvents.get(sig);
    if (curEntry === undefined) {
      findings.push({ level: ERROR, name, message: `event ${sig} was removed` });
      continue;
    }
    rememberSignature(sig, baseEntry, curEntry, reached);
    if (!sameFlags(indexedFlags(baseEntry), indexedFlags(curEntry))) {
      findings.push({
        level: ERROR,
        name,
        message: `event ${sig} changed which arguments are indexed`,
      });
    } else if (Boolean(baseEntry.anonymous) !== Boolean(curEntry.anonymous)) {
      findings.push({ level: ERROR, name, message: `event ${sig} changed its anonymous flag` });
    }
  }

  const baseErrors = abiIndex(baseAbi, "error");
  const curErrors = abiIndex(curAbi, "error");
  for (const sig of sortedKeys(baseErrors)) {
    const baseEntry = baseErrors.get(sig) as AbiEntry;
    const curEntry = curErrors.get(sig);
    if (curEntry === undefined) {
      findings.push({ level: ERROR, name, message: `error ${sig} was removed` });
      continue;
    }
    rememberSignature(sig, baseEntry, curEntry, reached);
  }
}

function sameFlags(left: boolean[], right: boolean[]): boolean {
  return left.length === right.length && left.every((flag, index) => flag === right[index]);
}

/**
 * Compares everything the two walks collected against the two builds' ASTs.
 *
 * Runs after both, so an enum the storage layout and the ABI both name is compared once,
 * under the path the layout walk found it at.
 */
export function checkDefinitions(
  name: string,
  reached: ReachedSets,
  baseDefinitions: Definitions,
  curDefinitions: Definitions,
  findings: Finding[]
): void {
  checkEnums(name, reached.enum, baseDefinitions.enum, curDefinitions.enum, findings);
  checkUserDefinedValueTypes(
    name,
    reached.value_type,
    baseDefinitions.value_type,
    curDefinitions.value_type,
    findings
  );
}

export type ContractResult = {
  name: string;
  findings: Finding[];
};

export function report(
  results: ContractResult[],
  errors: Finding[],
  reviews: Finding[],
  verbose: boolean,
  print: (line: string) => void
): void {
  let width = 8;
  if (results.length > 0) {
    width = 0;
    for (const result of results) {
      width = Math.max(width, result.name.length);
    }
  }
  const rows: Array<[string, string]> = [];
  for (const { name, findings } of results) {
    const contractErrors = findings.filter((finding) => finding.level === ERROR).length;
    const contractReviews = findings.length - contractErrors;
    if (contractErrors) {
      rows.push([name, `${contractErrors} error(s)`]);
    } else if (contractReviews) {
      rows.push([name, `${contractReviews} to review`]);
    } else if (verbose) {
      rows.push([name, "ok"]);
    }
  }
  if (rows.length > 0) {
    print(`\n${"contract".padEnd(width)}  status`);
    for (const [name, status] of rows) {
      print(`${name.padEnd(width)}  ${status}`);
    }
  }

  const buckets: Array<[Level, Finding[]]> = [
    [ERROR, errors],
    [REVIEW, reviews],
  ];
  for (const [level, bucket] of buckets) {
    if (bucket.length === 0) {
      continue;
    }
    print(level === ERROR ? `\n${level}S` : `\n${level} (not fatal, confirm by hand)`);
    for (const finding of bucket) {
      print(`  ${finding.name}: ${finding.message}`);
    }
  }
}

export type Options = {
  baseline: string;
  current: string;
  exclude: string;
  sourcePrefix: string;
  verbose: boolean;
  help: boolean;
};

const USAGE = `usage: abi-compat-check.ts [-h] --baseline BASELINE [--current CURRENT]
                           [--exclude EXCLUDE] [--source-prefix SOURCE_PREFIX] [-v]

Checks that the current build stays upgrade-compatible with a baseline build.

options:
  -h, --help                     show this help message and exit
  --baseline BASELINE            Foundry out/ directory of the baseline build
  --current CURRENT              Foundry out/ directory of the current build
  --exclude EXCLUDE              contract names to skip
  --source-prefix SOURCE_PREFIX  only check sources under this prefix
  -v, --verbose                  list compatible contracts too`;

export function parseArgs(argv: string[]): Options {
  const options: Options = {
    baseline: "",
    current: "out",
    exclude: DEFAULT_EXCLUDE,
    sourcePrefix: "contracts/",
    verbose: false,
    help: false,
  };
  let seenBaseline = false;
  let index = 0;
  while (index < argv.length) {
    const arg = argv[index] as string;
    index += 1;
    if (arg === "-h" || arg === "--help") {
      options.help = true;
      continue;
    }
    if (arg === "-v" || arg === "--verbose") {
      options.verbose = true;
      continue;
    }
    const equals = arg.startsWith("--") ? arg.indexOf("=") : -1;
    const flag = equals === -1 ? arg : arg.slice(0, equals);
    const inline = equals === -1 ? null : arg.slice(equals + 1);
    if (
      flag !== "--baseline" &&
      flag !== "--current" &&
      flag !== "--exclude" &&
      flag !== "--source-prefix"
    ) {
      throw new Error(`unrecognized arguments: ${arg}`);
    }
    let value: string;
    if (inline !== null) {
      value = inline;
    } else {
      const next = argv[index];
      if (next === undefined) {
        throw new Error(`argument ${flag}: expected one argument`);
      }
      value = next;
      index += 1;
    }
    if (flag === "--baseline") {
      options.baseline = value;
      seenBaseline = true;
    } else if (flag === "--current") {
      options.current = value;
    } else if (flag === "--exclude") {
      options.exclude = value;
    } else {
      options.sourcePrefix = value;
    }
  }
  if (!options.help && !seenBaseline) {
    throw new Error("the following arguments are required: --baseline");
  }
  return options;
}

function isDirectory(candidate: string): boolean {
  try {
    return fs.statSync(candidate).isDirectory();
  } catch {
    return false;
  }
}

/**
 * Runs the whole comparison and returns the process exit status.
 *
 * `write` receives everything the report prints, so the tests can capture it without
 * touching the process streams; diagnostics keep going to stderr, the way argparse
 * and `sys.exit(message)` sent them.
 */
export function main(
  argv: string[],
  write: (text: string) => void = (text) => {
    process.stdout.write(text);
  }
): number {
  const print = (line: string): void => {
    write(`${line}\n`);
  };
  const fail = (message: string): void => {
    process.stderr.write(`${message}\n`);
  };

  let options: Options;
  try {
    options = parseArgs(argv);
  } catch (problem) {
    fail(`${USAGE}\nabi-compat-check.ts: error: ${(problem as Error).message}`);
    return 2;
  }
  if (options.help) {
    print(USAGE);
    return 0;
  }

  for (const directory of [options.baseline, options.current]) {
    if (!isDirectory(directory)) {
      fail(`not a directory: ${directory} (run \`forge build\` first)`);
      return 1;
    }
  }

  const exclude = new RegExp(options.exclude);
  const base = loadArtifacts(options.baseline, exclude, options.sourcePrefix);
  const cur = loadArtifacts(options.current, exclude, options.sourcePrefix);
  if (base.artifacts.size === 0) {
    fail(`no contracts found under ${options.baseline}; is it a Foundry out/ directory?`);
    return 1;
  }

  print(`baseline: ${options.baseline} (${base.artifacts.size} contracts)`);
  print(`current:  ${options.current} (${cur.artifacts.size} contracts)`);

  const results: ContractResult[] = [];
  const errors: Finding[] = [];
  const reviews: Finding[] = [];
  for (const name of [...base.artifacts.keys()].sort(compareStrings)) {
    const findings: Finding[] = [];
    const baseline = base.artifacts.get(name) as Artifact;
    const current = cur.artifacts.get(name);
    if (current === undefined) {
      findings.push({ level: ERROR, name, message: "contract is gone from the current build" });
    } else {
      const reached: ReachedSets = { enum: new Map(), value_type: new Map() };
      checkStorage(name, baseline, current, reached, findings);
      checkAbi(name, baseline, current, reached, findings);
      checkDefinitions(name, reached, base.definitions, cur.definitions, findings);
    }
    results.push({ name, findings });
    for (const finding of findings) {
      if (finding.level === ERROR) {
        errors.push(finding);
      } else {
        reviews.push(finding);
      }
    }
  }

  const added = [...cur.artifacts.keys()]
    .filter((name) => !base.artifacts.has(name))
    .sort(compareStrings);
  if (added.length > 0) {
    print(`new contracts (not checked): ${added.join(", ")}`);
  }

  report(results, errors, reviews, options.verbose, print);

  if (errors.length > 0) {
    const affected = new Set(errors.map((finding) => finding.name));
    print(`\n${errors.length} incompatibility(ies) across ${affected.size} contract(s)`);
    return 1;
  }
  print(`\ncompatible with the baseline (${reviews.length} item(s) flagged for review)`);
  return 0;
}

function isEntryPoint(): boolean {
  const invoked = process.argv[1];
  if (invoked === undefined) {
    return false;
  }
  try {
    return import.meta.url === pathToFileURL(fs.realpathSync(invoked)).href;
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  process.exitCode = main(process.argv.slice(2));
}
