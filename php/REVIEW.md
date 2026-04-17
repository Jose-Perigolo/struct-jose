# PHP (php) - Review vs TypeScript Canonical

## Overview

The PHP version is a comprehensive implementation with **40+ functions** as static methods on the `Struct` class. It covers all major operations (inject, transform, validate, select) and has an extensive test suite (75+ test methods). The main differences are an older API pattern (positional parameters for inject/transform instead of unified `injdef`), reversed parameter order for `select`, and PHP-specific type handling.

---

## Missing Functions

| Function | Category | Impact |
|----------|----------|--------|
| `replace` | String | No unified string replace wrapper |
| `getdef` | Property access | No defined-or-default helper |
| `jm`/`jt` | JSON builders | No JSON builder functions |
| `typename` | Type system | Exists but verify alignment |

---

## Naming Differences

| TS Name | PHP Name | Notes |
|---------|----------|-------|
| All functions | `Struct::functionName` | Static methods on class |
| `escre` | `escre` (was `escapeRegex` in older version) | May have been renamed |
| `escurl` | `escurl` (was `escapeUrl` in older version) | May have been renamed |

---

## API Signature Differences

### 1. `inject` uses positional parameters instead of `injdef`

- **TS**: `inject(val, store, injdef?)` where `injdef` is `Partial<Injection>`.
- **PHP**: `inject($val, $store, $modify, $current, $injdef)` - separate positional params.
- **Impact**: Less extensible; harder to add new options.

### 2. `transform` uses positional parameters instead of `injdef`

- **TS**: `transform(data, spec, injdef?)`.
- **PHP**: `transform($data, $spec, $extra, $modify)` - separate params.
- **Impact**: Same extensibility concern.

### 3. `validate` uses `injdef` but partially

- **TS**: `validate(data, spec, injdef?)`.
- **PHP**: `validate($data, $spec, $injdef)` - closer to TS but `injdef` may be differently structured.

### 4. `select` has reversed parameter order

- **TS**: `select(children, query)` - children first, then query.
- **PHP**: `select($query, $children)` - query first, then children.
- **Impact**: **Breaking API difference**. Must be aligned.

### 5. `getpath` uses older positional parameters

- **TS**: `getpath(store, path, injdef?)`.
- **PHP**: `getpath($path, $store, $current, $state)` - path first, positional params.
- **Impact**: Different parameter order from TS canonical.

### 6. `walk` signature

- **TS**: `walk(val, before?, after?, maxdepth?, key?, parent?, path?)`.
- **PHP**: `walk($val, $before, $after, $maxdepth, $key, $parent, $path)` - matching TS.
- **Notes**: Correctly aligned with before/after/maxdepth pattern.

---

## Validation Differences

### Validator Names
- **TS**: `$MAP`, `$LIST`, `$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`, `$BOOLEAN`, `$NULL`, `$NIL`, `$FUNCTION`, `$INSTANCE`, `$ANY`, `$CHILD`, `$ONE`, `$EXACT`.
- **PHP**: `$OBJECT`, `$ARRAY`, `$STRING`, `$NUMBER`, `$BOOLEAN`, `$FUNCTION`, `$ANY`, `$CHILD`, `$ONE`, `$EXACT`.
- **Missing**: `$MAP` (uses `$OBJECT`), `$LIST` (uses `$ARRAY`), `$INTEGER`, `$DECIMAL`, `$NULL`, `$NIL`, `$INSTANCE`.
- **Impact**: Cannot distinguish integer from decimal validation; no null/nil validators.

---

## Transform Differences

- **TS**: `$DELETE`, `$COPY`, `$KEY`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`, `$FORMAT`, `$APPLY`, `$BT`, `$DS`, `$WHEN`.
- **PHP**: `$DELETE`, `$COPY`, `$KEY`, `$META`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`. Missing: `$FORMAT`, `$APPLY`, `$BT`, `$DS`, `$WHEN`.
- **Impact**: Cannot format strings or apply custom functions in transforms; no backtick/dollar escaping.

---

## Significant Language Difference Issues

### 1. `UNDEF` Is a String Constant

- **Issue**: PHP uses `const UNDEF = '__UNDEFINED__'` (a string) as sentinel for absent values.
- **Impact**: If a real data value happens to be the string `'__UNDEFINED__'`, it will be misinterpreted as absent. This is unlikely but theoretically possible.
- **Recommendation**: Consider using a unique object instance (e.g., `new \stdClass()`) as sentinel instead of a string.

### 2. PHP Arrays Are Both Lists and Maps

- **Issue**: PHP arrays serve as both sequential lists and associative maps. `array(1, 2, 3)` and `array('a' => 1)` are the same type.
- **Impact**: `islist` must check for sequential integer keys starting at 0. `ismap` must detect non-sequential or string keys. This is fragile - operations that delete elements can turn a list into a map (non-sequential indices).
- **Recommendation**: Ensure `delprop` on lists re-indexes to maintain sequential keys.

### 3. Objects vs Arrays for Maps

- **Issue**: PHP can represent JSON objects as either `stdClass` objects or associative arrays. The library appears to use `stdClass` for maps in some contexts and arrays in others.
- **Impact**: `ismap` must handle both `is_object($val)` and associative arrays. Inconsistent representation can cause type-check failures.
- **Recommendation**: Standardize on one representation (preferably `stdClass` for maps to avoid list/map ambiguity).

### 4. No `undefined` vs `null` Distinction

- **Issue**: PHP has only `null`. The `UNDEF` string constant is used as a workaround.
- **Impact**: Same fundamental issue as Python/Lua/Go. Property access cannot distinguish "key absent" from "key is null".

### 5. Pass-by-Value Semantics for Arrays

- **Issue**: PHP arrays are copy-on-write. `setprop` uses `&$parent` (pass by reference) to modify in place.
- **Impact**: Callers must be careful about reference semantics. Some functions may unexpectedly create copies.

### 6. No Function Overloading

- **Issue**: PHP doesn't support function overloading. The `items` function uses an optional `$apply` callback parameter.
- **Notes**: This matches the TS approach (overloaded signatures compiled to single implementation).

### 7. Weak Typing in Comparisons

- **Issue**: PHP's `==` operator performs type coercion (`0 == ""` is true, `0 == "0"` is true).
- **Impact**: Comparisons in `select`, `validate`, and `haskey` must use `===` strict equality where appropriate.
- **Recommendation**: Audit all equality comparisons for strict vs loose equality usage.

### 8. No Symbol Type

- **Issue**: PHP has no equivalent of JavaScript Symbol.
- **Impact**: `T_symbol` type constant exists but `typify` will never return it. Minimal impact.

---

## Test Coverage

PHP has comprehensive test coverage (75+ test methods) covering:
- All minor functions, walk, merge, getpath, inject, transform, validate, select.
- Edge case tests for most functions.
- Uses shared `test.json` spec via PHPUnit.

### Minor Gaps
- Some newer TS test categories may not be present (e.g., `transform-format`, `transform-apply` if those commands aren't implemented).

---

## Alignment Plan

### Phase 1: Critical API Fixes
1. Fix `select` parameter order to `select($children, $query)` to match TS
2. Align `getpath` parameter order to `getpath($store, $path, $injdef)`
3. Refactor `inject` to use `$injdef` object parameter instead of positional params
4. Refactor `transform` to use `$injdef` object parameter

### Phase 2: Missing Validators
5. Add `$MAP` validator (alias or replacement for `$OBJECT`)
6. Add `$LIST` validator (alias or replacement for `$ARRAY`)
7. Add `$INTEGER` validator
8. Add `$DECIMAL` validator
9. Add `$NULL` and `$NIL` validators
10. Add `$INSTANCE` validator

### Phase 3: Missing Transform Commands
11. Add `$FORMAT` transform command
12. Add `$APPLY` transform command
13. Add `$BT` (backtick escape) transform command
14. Add `$DS` (dollar sign escape) transform command
15. Add `$WHEN` (timestamp) transform command

### Phase 4: Missing Functions
16. Add `getdef($val, $alt)` function
17. Add `replace($s, $from, $to)` function
18. Consider adding `jm`/`jt` JSON builder functions

### Phase 5: UNDEF Sentinel Improvement
19. Consider replacing string `UNDEF` with object sentinel
20. Audit all `UNDEF` comparisons for correctness

### Phase 6: Type System Alignment
21. Verify `typify` returns matching bitfield values
22. Verify `typename` output matches TS
23. Add any missing type constants

### Phase 7: Test Alignment
24. Add tests for new validators and transform commands
25. Verify all test categories from TS `test.json` are covered
26. Fix any test failures from API changes
