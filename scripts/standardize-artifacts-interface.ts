export interface BuildInfoInterface {
  id: string;
  _format: string;
  solcVersion: string;
  solcLongVersion: string;
  input: Input;
  output: Output;
}

export interface Input {
  language: string;
  sources: Record<string, any>;
  settings: Settings;
}

export interface Settings {
  evmVersion: string;
  metadata: Metadata;
  optimizer: Optimizer;
  outputSelection: OutputSelection;
}

export interface Metadata {
  useLiteralContent: boolean;
}

export interface Optimizer {
  enabled: boolean;
  runs: number;
}

export interface OutputSelection {
  "*": GeneratedType;
}

export interface GeneratedType {
  "*": string[];
  "": string[];
}

export interface Output {
  contracts: Record<string, Record<string, any>>;
  sources: Record<string, OutputSource>;
}

export interface OutputSource {
  ast: any;
  id: number;
}

export interface ArtifactInterface {
  contractName: string;
  abi: Abi[];
  metadata: string;
  bytecode: string;
  deployedBytecode: string;
  immutableReferences?: ImmutableReferences;
  generatedSources?: any[];
  deployedGeneratedSources?: any[];
  sourceMap?: string;
  deployedSourceMap?: string;
  source: string;
  sourcePath?: string;
  ast: Ast;
  compiler: Compiler;
  networks?: Networks;
  schemaVersion?: string;
  updatedAt?: string;
  devdoc?: Devdoc;
  userdoc?: Userdoc;
}

export interface Abi {
  anonymous?: boolean;
  inputs: Input[];
  name: string;
  type: string;
  outputs?: Output[];
  stateMutability?: string;
}

export interface Input {
  indexed?: boolean;
  internalType: string;
  name: string;
  type: string;
}

export interface Output {
  internalType: string;
  name: string;
  type: string;
}

export interface ImmutableReferences {}

export interface Ast {
  absolutePath: string;
  exportedSymbols: ExportedSymbols;
  id: number;
  license: string;
  nodeType: string;
  nodes: Node[];
  src: string;
}

export interface ExportedSymbols {
  Context: number[];
  Ownable: number[];
}

export interface Node {
  id: number;
  literals?: string[];
  nodeType: string;
  src: string;
  absolutePath?: string;
  file?: string;
  scope?: number;
  sourceUnit?: number;
  symbolAliases?: any[];
  unitAlias?: string;
  abstract?: boolean;
  baseContracts?: BaseContract[];
  contractDependencies?: number[];
  contractKind?: string;
  documentation?: Documentation;
  fullyImplemented?: boolean;
  linearizedBaseContracts?: number[];
  name?: string;
  nodes?: Node2[];
}

export interface BaseContract {
  baseName: BaseName;
  id: number;
  nodeType: string;
  src: string;
}

export interface BaseName {
  id: number;
  name: string;
  nodeType: string;
  referencedDeclaration: number;
  src: string;
}

export interface Documentation {
  id: number;
  nodeType: string;
  src: string;
  text: string;
}

export interface Node2 {
  constant?: boolean;
  id: number;
  mutability?: string;
  name: string;
  nodeType: string;
  scope?: number;
  src: string;
  stateVariable?: boolean;
  storageLocation?: string;
  typeDescriptions?: TypeDescriptions;
  typeName?: TypeName;
  visibility?: string;
  anonymous?: boolean;
  parameters?: Parameters;
  body?: Body;
  documentation?: Documentation2;
  implemented?: boolean;
  kind?: string;
  modifiers?: Modifier[];
  returnParameters?: ReturnParameters;
  stateMutability?: string;
  virtual?: boolean;
  functionSelector?: string;
}

export interface TypeDescriptions {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeName {
  id: number;
  name: string;
  nodeType: string;
  src: string;
  stateMutability: string;
  typeDescriptions: TypeDescriptions2;
}

export interface TypeDescriptions2 {
  typeIdentifier: string;
  typeString: string;
}

export interface Parameters {
  id: number;
  nodeType: string;
  parameters: Parameter[];
  src: string;
}

export interface Parameter {
  constant: boolean;
  id: number;
  mutability: string;
  name: string;
  nodeType: string;
  scope: number;
  src: string;
  stateVariable: boolean;
  storageLocation: string;
  typeDescriptions: TypeDescriptions3;
  typeName: TypeName2;
  visibility: string;
  indexed?: boolean;
}

export interface TypeDescriptions3 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeName2 {
  id: number;
  name: string;
  nodeType: string;
  src: string;
  stateMutability: string;
  typeDescriptions: TypeDescriptions4;
}

export interface TypeDescriptions4 {
  typeIdentifier: string;
  typeString: string;
}

export interface Body {
  id: number;
  nodeType: string;
  src: string;
  statements: Statement[];
}

export interface Statement {
  expression?: Expression;
  id: number;
  nodeType: string;
  src: string;
  functionReturnParameters?: number;
  assignments?: number[];
  declarations?: Declaration[];
  initialValue?: InitialValue;
  eventCall?: EventCall;
}

export interface Expression {
  id: number;
  isConstant?: boolean;
  isLValue?: boolean;
  isPure?: boolean;
  lValueRequested?: boolean;
  leftHandSide?: LeftHandSide;
  nodeType: string;
  operator?: string;
  rightHandSide?: RightHandSide;
  src: string;
  typeDescriptions: TypeDescriptions7;
  arguments?: Argument[];
  expression?: Expression5;
  kind?: string;
  names?: any[];
  tryCall?: boolean;
  name?: string;
  overloadedDeclarations?: any[];
  referencedDeclaration?: number;
}

export interface LeftHandSide {
  id: number;
  name: string;
  nodeType: string;
  overloadedDeclarations: any[];
  referencedDeclaration: number;
  src: string;
  typeDescriptions: TypeDescriptions5;
}

export interface TypeDescriptions5 {
  typeIdentifier: string;
  typeString: string;
}

export interface RightHandSide {
  id: number;
  name: string;
  nodeType: string;
  overloadedDeclarations: any[];
  referencedDeclaration: number;
  src: string;
  typeDescriptions: TypeDescriptions6;
}

export interface TypeDescriptions6 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeDescriptions7 {
  typeIdentifier: string;
  typeString: string;
}

export interface Argument {
  id: number;
  name?: string;
  nodeType: string;
  overloadedDeclarations?: any[];
  referencedDeclaration?: number;
  src: string;
  typeDescriptions: TypeDescriptions8;
  commonType?: CommonType;
  isConstant?: boolean;
  isLValue?: boolean;
  isPure?: boolean;
  lValueRequested?: boolean;
  leftExpression?: LeftExpression;
  operator?: string;
  rightExpression?: RightExpression;
  hexValue?: string;
  kind?: string;
  value?: string;
  arguments?: Argument3[];
  expression?: Expression4;
  names?: any[];
  tryCall?: boolean;
}

export interface TypeDescriptions8 {
  typeIdentifier: string;
  typeString: string;
}

export interface CommonType {
  typeIdentifier: string;
  typeString: string;
}

export interface LeftExpression {
  arguments?: any[];
  expression?: Expression2;
  id: number;
  isConstant?: boolean;
  isLValue?: boolean;
  isPure?: boolean;
  kind?: string;
  lValueRequested?: boolean;
  names?: any[];
  nodeType: string;
  src: string;
  tryCall?: boolean;
  typeDescriptions: TypeDescriptions10;
  name?: string;
  overloadedDeclarations?: any[];
  referencedDeclaration?: number;
}

export interface Expression2 {
  argumentTypes: any[];
  id: number;
  name: string;
  nodeType: string;
  overloadedDeclarations: any[];
  referencedDeclaration: number;
  src: string;
  typeDescriptions: TypeDescriptions9;
}

export interface TypeDescriptions9 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeDescriptions10 {
  typeIdentifier: string;
  typeString: string;
}

export interface RightExpression {
  arguments: Argument2[];
  expression: Expression3;
  id: number;
  isConstant: boolean;
  isLValue: boolean;
  isPure: boolean;
  kind: string;
  lValueRequested: boolean;
  names: any[];
  nodeType: string;
  src: string;
  tryCall: boolean;
  typeDescriptions: TypeDescriptions14;
}

export interface Argument2 {
  hexValue: string;
  id: number;
  isConstant: boolean;
  isLValue: boolean;
  isPure: boolean;
  kind: string;
  lValueRequested: boolean;
  nodeType: string;
  src: string;
  typeDescriptions: TypeDescriptions11;
  value: string;
}

export interface TypeDescriptions11 {
  typeIdentifier: string;
  typeString: string;
}

export interface Expression3 {
  argumentTypes: ArgumentType[];
  id: number;
  name?: string;
  nodeType: string;
  overloadedDeclarations?: any[];
  referencedDeclaration?: number;
  src: string;
  typeDescriptions: TypeDescriptions12;
  isConstant?: boolean;
  isLValue?: boolean;
  isPure?: boolean;
  lValueRequested?: boolean;
  typeName?: TypeName3;
}

export interface ArgumentType {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeDescriptions12 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeName3 {
  id: number;
  name: string;
  nodeType: string;
  src: string;
  typeDescriptions: TypeDescriptions13;
}

export interface TypeDescriptions13 {}

export interface TypeDescriptions14 {
  typeIdentifier: string;
  typeString: string;
}

export interface Argument3 {
  hexValue: string;
  id: number;
  isConstant: boolean;
  isLValue: boolean;
  isPure: boolean;
  kind: string;
  lValueRequested: boolean;
  nodeType: string;
  src: string;
  typeDescriptions: TypeDescriptions15;
  value: string;
}

export interface TypeDescriptions15 {
  typeIdentifier: string;
  typeString: string;
}

export interface Expression4 {
  argumentTypes: ArgumentType2[];
  id: number;
  isConstant?: boolean;
  isLValue?: boolean;
  isPure?: boolean;
  lValueRequested?: boolean;
  nodeType: string;
  src: string;
  typeDescriptions: TypeDescriptions16;
  typeName?: TypeName4;
  name?: string;
  overloadedDeclarations?: any[];
  referencedDeclaration?: number;
}

export interface ArgumentType2 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeDescriptions16 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeName4 {
  id: number;
  name: string;
  nodeType: string;
  src: string;
  typeDescriptions: TypeDescriptions17;
}

export interface TypeDescriptions17 {}

export interface Expression5 {
  argumentTypes: ArgumentType3[];
  id: number;
  name: string;
  nodeType: string;
  overloadedDeclarations: number[];
  referencedDeclaration: number;
  src: string;
  typeDescriptions: TypeDescriptions18;
}

export interface ArgumentType3 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeDescriptions18 {
  typeIdentifier: string;
  typeString: string;
}

export interface Declaration {
  constant: boolean;
  id: number;
  mutability: string;
  name: string;
  nodeType: string;
  scope: number;
  src: string;
  stateVariable: boolean;
  storageLocation: string;
  typeDescriptions: TypeDescriptions19;
  typeName: TypeName5;
  visibility: string;
}

export interface TypeDescriptions19 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeName5 {
  id: number;
  name: string;
  nodeType: string;
  src: string;
  stateMutability: string;
  typeDescriptions: TypeDescriptions20;
}

export interface TypeDescriptions20 {
  typeIdentifier: string;
  typeString: string;
}

export interface InitialValue {
  id: number;
  name: string;
  nodeType: string;
  overloadedDeclarations: any[];
  referencedDeclaration: number;
  src: string;
  typeDescriptions: TypeDescriptions21;
}

export interface TypeDescriptions21 {
  typeIdentifier: string;
  typeString: string;
}

export interface EventCall {
  arguments: Argument4[];
  expression: Expression6;
  id: number;
  isConstant: boolean;
  isLValue: boolean;
  isPure: boolean;
  kind: string;
  lValueRequested: boolean;
  names: any[];
  nodeType: string;
  src: string;
  tryCall: boolean;
  typeDescriptions: TypeDescriptions24;
}

export interface Argument4 {
  id: number;
  name: string;
  nodeType: string;
  overloadedDeclarations: any[];
  referencedDeclaration: number;
  src: string;
  typeDescriptions: TypeDescriptions22;
}

export interface TypeDescriptions22 {
  typeIdentifier: string;
  typeString: string;
}

export interface Expression6 {
  argumentTypes: ArgumentType4[];
  id: number;
  name: string;
  nodeType: string;
  overloadedDeclarations: any[];
  referencedDeclaration: number;
  src: string;
  typeDescriptions: TypeDescriptions23;
}

export interface ArgumentType4 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeDescriptions23 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeDescriptions24 {
  typeIdentifier: string;
  typeString: string;
}

export interface Documentation2 {
  id: number;
  nodeType: string;
  src: string;
  text: string;
}

export interface Modifier {
  id: number;
  modifierName: ModifierName;
  nodeType: string;
  src: string;
}

export interface ModifierName {
  id: number;
  name: string;
  nodeType: string;
  referencedDeclaration: number;
  src: string;
}

export interface ReturnParameters {
  id: number;
  nodeType: string;
  parameters: Parameter2[];
  src: string;
}

export interface Parameter2 {
  constant: boolean;
  id: number;
  mutability: string;
  name: string;
  nodeType: string;
  scope: number;
  src: string;
  stateVariable: boolean;
  storageLocation: string;
  typeDescriptions: TypeDescriptions25;
  typeName: TypeName6;
  visibility: string;
}

export interface TypeDescriptions25 {
  typeIdentifier: string;
  typeString: string;
}

export interface TypeName6 {
  id: number;
  name: string;
  nodeType: string;
  src: string;
  stateMutability: string;
  typeDescriptions: TypeDescriptions26;
}

export interface TypeDescriptions26 {
  typeIdentifier: string;
  typeString: string;
}

export interface Compiler {
  name: string;
  version: string;
}

export interface Networks {}

export interface Devdoc {
  details: string;
  kind: string;
  methods: Methods;
  version: number;
}

export interface Methods {
  constructor: Constructor;
  "owner()": Owner;
  "renounceOwnership()": RenounceOwnership;
  "transferOwnership(address)": TransferOwnershipAddress;
}

export interface Constructor {
  details: string;
}

export interface Owner {
  details: string;
}

export interface RenounceOwnership {
  details: string;
}

export interface TransferOwnershipAddress {
  details: string;
}

export interface Userdoc {
  kind: string;
  methods: Methods2;
  version: number;
}

export interface Methods2 {}

export interface Contract {
  name: string;
  relativePath: string;
  dbg: string;
  artifact: string;
}

export interface Dbg {
  buildInfo: string;
}
