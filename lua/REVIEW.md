# Lua (lua) - Review vs TypeScript Canonical

## Overview

The Lua version is a comprehensive implementation with **39 exported functions**, closely tracking the TypeScript canonical. It uses the unified `injdef` table pattern, has full type constants, and supports all major operations (inject, transform, validate, select). The primary challenges come from Lua's fundamental language differences: 1-based indexing, tables for both maps and lists, and no native distinction between arrays and objects.

---

## Missing Functions

| Function | Category | Impact |
|----------|----------|--------|
| `replace` | String | No unified string replace wrapper |
| `jm`/`jt` | JSON builders | No JSON builder functions (less needed in Lua since tables are flexible) |

---

## Naming Differences

All function names are lowercase in Lua (matching TS convention). No significant naming differences.

---

## API Signature Differences

### 1. `injdef` is a plain table

- **TS**: `injdef` is `Partial<Injection>` with typed fields.
- **Lua**: `injdef` is a plain table with the same field names.
- **Notes**: Functionally equivalent; Lua doesn't have typed interfaces.

### 2. `items` returns `{key, val}` tables instead of `[key, val]` arrays

- **TS**: Returns `[string, any][]` - array of 2-element tuples.
- **Lua**: Returns array of `{key, val}` tables (named fields).
- **Impact**: Different access pattern: `item[1]`/`item[2]` in TS vs `item.key`/`item.val` in Lua. May complicate cross-language test alignment.

### 3. `clone` accepts `flags` table

- **TS**: `clone(val)` - no flags.
- **Lua**: `clone(val, flags)` where `flags.func` controls function cloning.
- **Notes**: Extra feature, not a divergence.

---

## Significant Language Difference Issues

### 1. 1-Based Indexing (Critical)

- **Issue**: Lua arrays are 1-based, while JavaScript/TypeScript arrays are 0-based. This affects every function that deals with list indices.
- **Areas affected**:
  - `getprop`/`setprop`/`getelem` must translate between 0-based external API and 1-based internal Lua tables.
  - `slice` start/end parameters use 0-based convention externally but 1-based internally.
  - Path arrays use 0-based string indices to match the cross-language test.json format.
  - `keysof` for lists returns 0-based string indices (`"0"`, `"1"`, `"2"`) to match TS, despite Lua tables being 1-based internally.
- **Impact**: This is the single largest source of potential bugs. Every index translation is an off-by-one risk. The implementation handles this via explicit `+ 1` / `- 1` adjustments.
- **Recommendation**: Thorough edge case testing for all index boundary conditions (empty lists, single-element lists, negative indices, out-of-bounds indices).

### 2. Tables Are Both Maps and Lists (Critical)

- **Issue**: Lua has a single `table` type for both arrays (sequential integer keys) and maps (string keys). There is no native way to distinguish an empty array `[]` from an empty object `{}`.
- **Workaround**: Uses metatables with `__jsontype` field (`"array"` or `"object"`) to tag tables.
- **Impact**: 
  - `ismap` and `islist` must check metatables or infer from key types.
  - JSON serialization must preserve the array/object distinction.
  - `isnode` must handle both cases.
  - Empty tables are ambiguous without metatable tagging.
- **Recommendation**: Ensure all functions that create tables set appropriate metatables. Test empty table edge cases thoroughly.

### 3. No `undefined` vs `null` Distinction

- **Issue**: Lua has only `nil`. Setting a table key to `nil` removes it entirely.
- **Impact**: 
  - Cannot store `nil` as a value in a table (it deletes the key).
  - Cannot distinguish "key absent" from "key set to null".
  - The `NULLMARK`/`UNDEFMARK` marker system in the test runner handles this for testing.
- **Recommendation**: Consider a sentinel value for JSON null (e.g., `json.null` or a special table) to distinguish from absent keys.

### 4. No Native JSON Type

- **Issue**: Lua has no built-in JSON support. Relies on external JSON library (e.g., `cjson`, `dkjson`).
- **Impact**: JSON encoding/decoding behavior depends on which library is used. Different libraries handle edge cases differently (e.g., sparse arrays, special float values).

### 5. String Patterns vs Regular Expressions

- **Issue**: Lua uses its own pattern matching syntax, not POSIX or PCRE regular expressions.
- **Impact**: 
  - `escre` must escape Lua pattern special characters (`^$()%.[]*+-?`), which differ from regex special characters.
  - `select` query with `$LIKE` operator must use Lua patterns, not regex.
  - String matching in the test runner uses Lua patterns.
- **Recommendation**: Document that `escre` escapes Lua patterns, not standard regex. Consider if this behavioral difference is acceptable or if a regex library should be used.

### 6. No Integer Type (Pre-Lua 5.3)

- **Issue**: Lua 5.1/5.2 have only `number` (double-precision float). Lua 5.3+ added integer subtype.
- **Impact**: `typify` must detect whether a number is an integer or decimal. On Lua 5.3+, `math.type()` helps. On older versions, must check `val == math.floor(val)`.
- **Recommendation**: Ensure compatibility with target Lua version.

### 7. No Closures as "Functions" for `isfunc`

- **Issue**: Lua functions and closures are both type `"function"`, which aligns well with TS. However, callable tables (with `__call` metamethod) may or may not be detected.
- **Impact**: `isfunc` using `type(val) == "function"` won't detect callable tables.

### 8. Table Length Operator `#` Unreliable for Sparse Arrays

- **Issue**: The `#` operator on tables with holes (nil gaps) has undefined behavior.
- **Impact**: `size` for lists must be careful about sparse arrays. The implementation likely uses explicit iteration.

---

## Validation Differences

- **TS**: Uses `$MAP`, `$LIST`, `$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`, `$BOOLEAN`, `$NULL`, `$NIL`, `$FUNCTION`, `$INSTANCE`, `$ANY`, `$CHILD`, `$ONE`, `$EXACT`.
- **Lua**: Same validator set present.
- **Notes**: Aligned.

---

## Transform Differences

- **TS**: Full set of transform commands.
- **Lua**: Full set including `$DELETE`, `$COPY`, `$KEY`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`, `$FORMAT`, `$APPLY`.
- **Notes**: Aligned.

---

## Test Coverage

Lua tests cover all major categories:
- Existence tests (116 checks), minor functions, walk, merge, getpath, inject, transform, validate, select, JSON builders.
- Uses shared `test.json` spec via `busted` test framework.
- Comprehensive test organization matching TS.

---

## Alignment Plan

### Phase 1: Index Boundary Verification (High Priority)
1. Audit all 0-based/1-based index translations in `getprop`, `setprop`, `getelem`, `delprop`
2. Add edge case tests for: empty list, single-element list, negative indices, boundary indices
3. Verify `slice` parameter translation matches TS behavior exactly
4. Verify `keysof` returns 0-based string indices for lists

### Phase 2: Table Type Disambiguation
5. Audit metatable usage for array/object distinction
6. Ensure all table-creating functions set correct `__jsontype` metatable
7. Test empty table edge cases: `ismap({})`, `islist({})`, `isempty({})`
8. Verify `clone` preserves metatable tags

### Phase 3: Missing Functions
9. Add `replace(s, from, to)` function
10. Consider adding `jm`/`jt` builders (may alias table constructors)

### Phase 4: Pattern vs Regex Alignment
11. Document that `escre` escapes Lua patterns, not standard regex
12. Verify `select` `$LIKE` operator uses consistent pattern syntax
13. Consider adding a PCRE wrapper for cross-language consistency

### Phase 5: Null Handling
14. Review JSON null representation throughout the codebase
15. Ensure nil-in-table edge cases are handled correctly
16. Test `inject`/`transform`/`validate` with null values in various positions

### Phase 6: Full Test Suite Verification
17. Run complete test suite against shared `test.json`
18. Compare results with TS output for any discrepancies
19. Document any intentional Lua-specific behavioral differences
