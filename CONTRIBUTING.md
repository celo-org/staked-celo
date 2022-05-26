# Contributing

## Solidity Style

### Structure of a file

1. `// SPDX-License-Identifier: XXX`
2. Pragmas
3. Imports - grouped by category, separated by a new line, and sorted alphabetically within categories. Categories:
   1. External dependencies (e.g. `import "@openzeppelin/contracts/access/Ownable.sol";`)
   2. In-repo dependencies (e.g. `import "./libraries/AddressLinkedList.sol";`)
4. Contract contents - ordered logically within categories. Categories:
   1. Using X for Y;
   2. Constants / immutables
   3. Enums
   4. Structs
   5. State variables
   6. Events
   7. Errors
   8. Modifiers
   9. Constructor
   10. Receive function (if exists)
   11. Fallback function (if exists)
   12. External functions - ordered state modifying -> view -> pure
   13. Public functions - ordered state modifying -> view -> pure
   14. Internal functions - ordered state modifying -> view -> pure
   15. Private functions - ordered state modifying -> view -> pure

## Functions
1. Well named and without abbreviations (e.g. `voteForGroup` instead of `voteForGrp`, etc).
2. Function names are generally not prefixed with an underscore.
3. Parameters are generally ordered with "identifying" information first. E.g. `function voteFor(address group, uint256 amount)` instead of `function voteFor(uint256 amount, address group)`.
4. Constructor or setter parameters that must be disambiguated, e.g. `setFoo(uint _foo) { foo = _foo; }` may be prefixed with an underscore. All other function parameters should not be prefixed with underscores.

## Variables
1. Well named and without abbreviations (e.g. `votesForGroup` instead of `votesForGrp`, etc).
2. No underscore prefixing, even for private variables.

## Comments and NatSpec
1. Natspec used for all structs, state variables, errors, events, modifiers, constructors, and functions. `///` syntax may be used for single-line natspec comments-- e.g. if there is only an `@notice`, but multi-line natspec comments should use `/**` syntax.
2. Comments are grammatically and syntactically close to normal sentences-- e.g. first words are capitalized and always end with periods.

## Events
1. Generally of the form: `SomethingHappened`, rather than `Something` (e.g. `CeloDeposited` instead of `CeloDeposit`).
2. When a primitive state variable has been updated via a setter (most often as a result of an owner changing the value), an event of the form `VariableNameUpdated` should be emitted with the new value-- e.g. `event GroupVoterUpdated(address groupVoter)`.
3. Should contain enough information such that if all events were streamed from the beginning of time, the current state could theoretically be reconstructed.
4. Parameters are not prefixed with an underscore.
5. Parameters are indexed if they are likely to be searched for — e.g. `event CeloDeposited(address indexed group, uint256 amount)`, where it's likely that deposits for a group will be searched for but not likely that the exact amount of a deposit will ever be searched for.

## Errors
1. Should have descriptive names.
2. Should contain relevant parameters, e.g. `error GroupAlreadyDeprecated(address group);` includes the group that is already deprecated.
3. When something has failed, the event should be of the form: `SomethingFailed`.
