# Java (java) - Review vs TypeScript Canonical

## Overview

The Java version is **severely incomplete**. It implements only ~20 basic functions out of the 40+ in the TypeScript canonical. Major subsystems (`getpath`, `setpath`, `inject`, `transform`, `validate`, `select`) are either missing or only partially stubbed. The test suite is a minimal placeholder. This is the **least mature** implementation alongside C++.

---

## Missing Functions

### Critical (Core Operations)
| Function | Category | Impact |
|----------|----------|--------|
| `getpath` | Path operations | Cannot navigate nested structures by path |
| `setpath` | Path operations | Cannot set values at nested paths |
| `inject` | Injection | No value injection from store |
| `transform` | Transform | No data transformation capability |
| `validate` | Validation | No data validation capability |
| `select` | Query | No query/filter on children |
| `merge` | Data manipulation | No multi-object merging |

### Minor Utilities
| Function | Category | Impact |
|----------|----------|--------|
| `getelem` | Property access | No negative-index list access |
| `getdef` | Property access | No defined-or-default helper |
| `delprop` | Property access | No dedicated property deletion |
| `size` | Collection | No unified size function |
| `slice` | Collection | No array/string slicing |
| `flatten` | Collection | No array flattening |
| `filter` | Collection | No predicate filtering |
| `pad` | String | No string padding |
| `replace` | String | No unified string replace |
| `join` | String | No general join function |
| `jsonify` | Serialization | No JSON serialization with formatting |
| `strkey` | String | No key-to-string conversion |
| `typename` | Type system | No type name function |
| `typify` | Type system | No type identification function |
| `jm`/`jt` | JSON builders | No JSON builder functions |
| `checkPlacement` | Advanced | No placement validation |
| `injectorArgs` | Advanced | No injector argument validation |
| `injectChild` | Advanced | No child injection helper |

---

## Existing Function Differences

### 1. `isFunc` checks for `Runnable` instead of general callable

- **TS**: `isfunc(val)` checks `typeof val === 'function'`.
- **Java**: `isFunc(val)` checks `val instanceof Runnable`.
- **Impact**: Misses `Callable`, `Function`, lambda expressions, and method references. Should check for `java.util.function.Function` or a custom functional interface.

### 2. `items` returns `List<Map.Entry<Object, Object>>` 

- **TS**: Returns `[string, any][]` - array of tuples with string keys.
- **Java**: Returns `List<Map.Entry<Object, Object>>` - Map entries with Object keys.
- **Impact**: Keys are not consistently strings. List indices should be returned as string keys to match TS.

### 3. `keysof` returns zeros for lists

- **TS**: Returns string indices (`["0", "1", "2"]`) for lists.
- **Java**: Returns a list of zeros sized to the list length.
- **Impact**: **Incorrect behavior**. This is a bug.

### 4. `hasKey` delegates to `getProp` null check

- **TS**: Checks if property is defined (not undefined).
- **Java**: Checks if `getProp` returns non-null.
- **Impact**: Cannot distinguish "key exists with null value" from "key doesn't exist".

### 5. `setProp` deletes on null

- **TS**: Has separate `delprop`; `setprop` with `DELETE` sentinel deletes.
- **Java**: `setProp` with `null` value deletes the key.
- **Impact**: Cannot set a property to `null` (JSON null).

### 6. `pathify` has different default `from` parameter

- **TS**: `pathify(val, startin=0, endin=0)` - starts from index 0 by default.
- **Java**: `pathify(val, from)` with `from` defaulting to 1 in usage.
- **Impact**: Off-by-one behavior difference.

### 7. `walk` is post-order only

- **TS**: `walk(val, before?, after?, maxdepth?)` - supports pre-order and post-order.
- **Java**: `walk(val, apply, key, parent, path)` - post-order only, no `maxdepth`.
- **Impact**: Cannot do pre-order transformations; no depth protection.

### 8. `clone` does not use JSON round-trip

- **TS**: Uses `JSON.parse(JSON.stringify(val))` with function preservation.
- **Java**: Recursively copies Maps and Lists; primitives returned as references.
- **Impact**: May not correctly deep-clone nested objects that aren't Map/List.

### 9. `escapeRegex` uses `Pattern.quote()`

- **TS**: Manually escapes special regex characters.
- **Java**: Uses `Pattern.quote()` which wraps in `\Q...\E`.
- **Impact**: Different escaping mechanism; may behave differently in edge cases.

### 10. `stringify` uses `Objects.toString()`

- **TS**: Custom implementation with sorted keys, quote removal, depth handling.
- **Java**: Simple `Objects.toString()` with quote removal.
- **Impact**: Output format will differ significantly for complex objects.

---

## Structural/Architectural Gaps

### No Injection System
- No `Injection` class or equivalent.
- `InjectMode` enum exists but is unused.
- No injection state management.

### No Type System
- No bitfield type constants (`T_any`, `T_string`, etc.).
- No `typify` or `typename` functions.
- No type discrimination beyond basic `instanceof`.

### No SKIP/DELETE Sentinels
- No `SKIP` sentinel.
- `DELETE` sentinel is missing (deletion via null in `setProp`).

### Minimal Test Infrastructure
- `StructTest.java` is a placeholder (prints "1").
- `Runner.java` has framework code but `TestSubject.invoke()` only handles `isNode`.
- No actual test execution against `test.json`.

---

## Significant Language Difference Issues

### 1. No Equivalent of `undefined`

- **Issue**: Java has only `null`. Cannot distinguish "absent" from "JSON null".
- **Recommendation**: Use a sentinel object (e.g., `static final Object UNDEF = new Object()`) similar to the Python approach.

### 2. Type Erasure with Generics

- **Issue**: Java generics are erased at runtime. Cannot distinguish `List<String>` from `List<Integer>` at runtime.
- **Impact**: Type checking in `typify` must use `instanceof` checks on values, not generic type parameters.

### 3. No Dynamic Property Access

- **Issue**: Java objects don't support dynamic property access. Must use `Map<String, Object>` for JSON-like structures.
- **Impact**: All "map" operations must work with `Map` interface. No dot-notation property access.

### 4. No First-Class Functions (Pre-Java 8)

- **Issue**: Java uses functional interfaces (`Function<T,R>`, `BiFunction`, custom interfaces) instead of first-class functions.
- **Impact**: Callbacks for `walk`, `inject`, `transform` need well-designed functional interfaces. Current `Runnable` check in `isFunc` is wrong.

### 5. Checked Exceptions

- **Issue**: `escapeUrl` declares `throws UnsupportedEncodingException` (which can't actually happen with UTF-8).
- **Impact**: Forces callers to handle checked exceptions unnecessarily.

### 6. No Spread/Rest Parameters

- **Issue**: Java has varargs (`Object...`) but they're less flexible than JS spread.
- **Impact**: Functions like `jm`/`jt` need different idioms.

### 7. Primitive vs Object Types

- **Issue**: Java distinguishes `int`/`Integer`, `boolean`/`Boolean`, etc. JSON deserialization typically uses boxed types.
- **Impact**: Type checking must handle both primitive and boxed types.

---

## Test Coverage

**Almost no functional tests exist.** The test runner framework is partially built but only `isNode` is wired up as a test subject. This is the most critical gap.

---

## Alignment Plan

### Phase 1: Foundation (Critical)
1. Define `UNDEF` sentinel object for undefined/absent distinction
2. Define `SKIP` and `DELETE` sentinel objects
3. Add all type constants (`T_any`, `T_noval`, `T_boolean`, etc.)
4. Fix `isFunc` to check for `java.util.function.Function` or custom functional interface
5. Fix `keysof` to return string indices for lists (not zeros)
6. Fix `hasKey` to distinguish null values from absent keys
7. Add `strkey`, `typify`, `typename` functions

### Phase 2: Missing Minor Functions
8. Add `getelem(val, key, alt)` with negative index support
9. Add `getdef(val, alt)` helper
10. Add `delprop(parent, key)` function
11. Add `size(val)` function
12. Add `slice(val, start, end)` function
13. Add `flatten(list, depth)` function
14. Add `filter(val, check)` function
15. Add `pad(str, padding, padchar)` function
16. Add `join(arr, sep, url)` function
17. Add `replace(s, from, to)` function
18. Add `jsonify(val, flags)` function
19. Add `jm(...kv)` and `jt(...v)` JSON builders

### Phase 3: Core Operations (Critical)
20. Implement `Injection` class with `descend()`, `child()`, `setval()` methods
21. Implement `getpath(store, path, injdef)` function
22. Implement `setpath(store, path, val, injdef)` function
23. Implement `merge(val, maxdepth)` function
24. Implement `inject(val, store, injdef)` function with full injection system
25. Implement `transform(data, spec, injdef)` with all transform commands
26. Implement `validate(data, spec, injdef)` with all validators
27. Implement `select(children, query)` with all operators

### Phase 4: Fix Existing Functions
28. Fix `walk` to support `before`/`after` callbacks and `maxdepth`
29. Fix `stringify` to produce output matching TS format
30. Fix `clone` to handle all JSON-like types correctly
31. Fix `escapeRegex` to match TS escaping behavior (not `Pattern.quote`)
32. Fix `pathify` default index parameter
33. Fix `items` to return string keys consistently

### Phase 5: Test Infrastructure
34. Wire up `TestSubject.invoke()` for all functions
35. Complete test runner to execute full `test.json` spec
36. Add all test categories matching TS test suite
37. Ensure all tests pass against shared `test.json`

### Phase 6: Advanced Features
38. Add `checkPlacement`, `injectorArgs`, `injectChild` functions
39. Add custom validator/transform extension support via `injdef.extra`
