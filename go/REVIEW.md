# Go (go) - Review vs TypeScript Canonical

## Overview

The Go version is one of the most extensive implementations, with **50+ exported functions** - actually exceeding the TypeScript canonical in some areas. It uses the unified `*Injection` struct pattern and has comprehensive type constants. The main differences stem from Go's static type system, lack of generics (prior to 1.18), and explicit error handling.

---

## Extra Functions (Not in TS)

| Function | Purpose | Notes |
|----------|---------|-------|
| `CloneFlags` | Clone with options (func, wrap, unwrap) | TS `clone` is simpler |
| `WalkDescend` | Walk with explicit path tracking | TS combines this into `walk` |
| `TransformModify` | Transform with modify function | TS uses `injdef.modify` |
| `TransformModifyHandler` | Transform with handler+modify | TS uses `injdef` |
| `TransformCollect` | Transform returning errors | TS uses `injdef.errs` |
| `ItemsApply` | Items with apply function | TS overloads `items` |
| `ListRefCreate` | Generic list reference | Go-specific utility |

These extra functions exist because Go cannot use optional parameters or function overloading. They are acceptable language adaptations.

---

## Missing Functions

| Function | Category | Impact |
|----------|----------|--------|
| `replace` | String | No unified string replace wrapper |
| `jm` | JSON builders | Named `Jo` instead |
| `jt` | JSON builders | Named `Ja` instead |

---

## Naming Differences

| TS Name | Go Name | Notes |
|---------|---------|-------|
| `jm` | `Jo` | Go convention: exported, but different name |
| `jt` | `Ja` | Go convention: exported, but different name |
| `joinurl` | `JoinUrl` | Capitalized per Go convention |
| All functions | PascalCase | Go requires exported names to be capitalized |

---

## API Signature Differences

### 1. `Injection` is a struct with pointer semantics

- **TS**: `Injection` is a class with methods.
- **Go**: `*Injection` is a struct passed by pointer with methods.
- **Notes**: Functionally equivalent. Go's approach is idiomatic.

### 2. `Validate` returns `(any, error)` tuple

- **TS**: Returns data; throws on error or collects in `injdef.errs`.
- **Go**: Returns `(any, error)` - Go's standard error pattern.
- **Notes**: Idiomatic Go adaptation. The `error` return replaces throwing.

### 3. `Walk` takes `WalkApply` function type with `*string` key

- **TS**: `WalkApply = (key: string | number | undefined, val, parent, path) => any`
- **Go**: `WalkApply func(key *string, val any, parent any, path []string) any`
- **Notes**: Go uses `*string` (pointer) to represent optional key (nil = no key). This is a reasonable adaptation since Go has no union types.

### 4. Variadic parameters replace optional parameters

- **TS**: `getprop(val, key, alt?)` with optional `alt`.
- **Go**: `GetProp(val any, key any, alts ...any)` with variadic.
- **Notes**: Go doesn't support optional parameters; variadic is the idiomatic replacement.

### 5. `ListRef` generic wrapper for mutable list references

- **TS**: Uses plain arrays, passed by reference (JS semantics).
- **Go**: Uses `ListRef[T]` struct with `Append`/`Prepend` methods for `Keys`, `Path`, `Nodes`, `Errs` in the Injection struct.
- **Notes**: Required because Go slices are value types. This is a necessary language adaptation.

### 6. `Items` returns `[][2]any` instead of `[string, any][]`

- **TS**: Returns array of `[string, any]` tuples.
- **Go**: Returns `[][2]any` (array of 2-element arrays).
- **Notes**: Go has no tuple type; fixed-size array is the closest equivalent.

---

## Significant Language Difference Issues

### 1. No `undefined` vs `null` Distinction

- **Issue**: Go has only `nil`. There is no way to distinguish "absent" from "null" at the type level.
- **Workaround**: The test runner uses `NULLMARK`/`UNDEFMARK` string markers.
- **Impact**: Same as Python - inherent limitation requiring careful handling.

### 2. Type Assertions Required for Dynamic Access

- **Issue**: Go's static type system requires type assertions (`val.(map[string]any)`) for dynamic JSON-like data. This adds verbosity and runtime panic risk.
- **Impact**: The implementation uses `any` extensively, trading type safety for flexibility. This is the standard Go approach for JSON manipulation.

### 3. No Function Overloading

- **Issue**: Go doesn't support function overloading, leading to separate functions like `Items`/`ItemsApply`, `Walk`/`WalkDescend`, and multiple `Transform*` variants.
- **Impact**: API surface is larger but each function is simpler. Acceptable trade-off.

### 4. Map Iteration Order is Non-deterministic

- **Issue**: Go maps don't guarantee iteration order.
- **Workaround**: `KeysOf` sorts keys, and operations that iterate maps use sorted keys.
- **Impact**: Correctly handled.

### 5. No Generics for JSON Value Types (Pre-1.18)

- **Issue**: JSON values are `any` (interface{}), requiring type switches/assertions everywhere.
- **Impact**: More verbose code but functionally equivalent. `ListRef[T]` uses generics (Go 1.18+).

### 6. Integer Types

- **Issue**: Go has multiple integer types (`int`, `int64`, `float64`). JSON numbers from `encoding/json` decode as `float64` by default.
- **Impact**: Must carefully handle `float64` vs `int` conversions. The `typify` function needs to check if a `float64` is actually an integer.

### 7. No Regular Expression Literals

- **Issue**: Go uses `regexp.Compile()` instead of `/pattern/` literals.
- **Impact**: Regex operations in `select` and string matching work differently but are functionally equivalent.

---

## Test Coverage

Go tests are comprehensive, covering all categories:
- Minor functions, walk, merge, getpath, inject, transform, validate, select.
- Uses shared `test.json` spec via the test runner framework.
- Has additional test infrastructure (`testutil` package) with SDK, Runner, and Direct testing.

---

## Alignment Plan

### Phase 1: Naming Alignment (Low Priority)
1. Consider adding `Jm`/`Jt` aliases for `Jo`/`Ja` to match TS naming
2. Add `Replace(s, from, to)` function if missing

### Phase 2: API Review
3. Verify all `Transform*` variants produce identical results to TS `transform` with `injdef`
4. Review `Validate` error messages match TS format exactly
5. Ensure `Select` operator behavior matches TS for all edge cases

### Phase 3: Type System Verification
6. Verify `Typify` correctly distinguishes `float64` integers from true floats
7. Ensure type constant values match TS exactly (same bit positions)
8. Test `T_instance` detection for Go struct types

### Phase 4: Edge Case Alignment
9. Run full test suite comparison against TS test.json
10. Verify `nil` handling matches TS `undefined`/`null` semantics in all contexts
11. Check `Clone`/`CloneFlags` behavior matches TS `clone` for functions and nested structures

### Phase 5: Simplification (Optional)
12. Consider whether `TransformModify`, `TransformModifyHandler`, `TransformCollect` can be consolidated with a more Go-idiomatic options pattern
13. Document the rationale for `ListRef` and other Go-specific adaptations
