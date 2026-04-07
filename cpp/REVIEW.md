# C++ (cpp) - Review vs TypeScript Canonical

## Overview

The C++ version is the **most incomplete** implementation, with only **~18 functions** out of 40+. It covers basic type checking, property access, walk, merge, stringify, and clone. All major subsystems (getpath, setpath, inject, transform, validate, select) are **entirely missing**. The API design uses an unusual pattern where all functions take `args_container&&` (vector of JSON values), which differs significantly from all other implementations.

---

## Missing Functions

### Critical (Core Operations - All Missing)
| Function | Category | Impact |
|----------|----------|--------|
| `getpath` | Path operations | Cannot navigate nested structures by path |
| `setpath` | Path operations | Cannot set values at nested paths |
| `inject` | Injection | No value injection from store |
| `transform` | Transform | No data transformation capability |
| `validate` | Validation | No data validation capability |
| `select` | Query | No query/filter on children |

### Minor Utilities (All Missing)
| Function | Category | Impact |
|----------|----------|--------|
| `getelem` | Property access | No negative-index element access |
| `getdef` | Property access | No defined-or-default helper |
| `delprop` | Property access | No dedicated property deletion |
| `size` | Collection | No unified size function |
| `slice` | Collection | No array/string slicing |
| `flatten` | Collection | No array flattening |
| `filter` | Collection | No predicate filtering |
| `pad` | String | No string padding |
| `replace` | String | No unified string replace |
| `join` | String | No general join function |
| `jsonify` | Serialization | No JSON formatting |
| `strkey` | String | No key-to-string conversion |
| `typename` | Type system | No type name function |
| `typify` | Type system | No type identification function |
| `pathify` | String | No path-to-string conversion |
| `jm`/`jt` | JSON builders | No JSON builder functions |
| `checkPlacement` | Advanced | No placement validation |
| `injectorArgs` | Advanced | No injector argument validation |
| `injectChild` | Advanced | No child injection helper |

---

## Architectural Issues

### 1. All Functions Take `args_container&&`

- **TS**: Functions have named, typed parameters (e.g., `isnode(val: any)`).
- **C++**: All functions take `args_container&&` (aka `std::vector<json>&&`), extracting parameters by position from the vector.
- **Impact**: 
  - No compile-time parameter validation.
  - No IDE autocompletion for parameters.
  - Runtime errors for wrong argument count/types.
  - Cannot distinguish between functions by signature.
  - Makes the API feel like a scripting language dispatch table rather than a C++ library.
- **Recommendation**: Consider proper C++ function signatures with typed parameters. The `args_container` pattern should only be used for the test runner dispatch, not for the public API.

### 2. `walk` Uses `intptr_t` to Pass Function Pointers Through JSON

- **TS**: `walk(val, apply)` where `apply` is a function.
- **C++**: The apply function pointer is cast to `intptr_t`, stored in a JSON number, and cast back when needed.
- **Impact**: 
  - **Extremely unsafe** - pointer-as-integer casting through JSON is undefined behavior.
  - Breaks if JSON library modifies the number (e.g., float conversion).
  - Not portable across architectures.
  - No type safety for the callback.
- **Recommendation**: Redesign walk to take the callback as a separate parameter, not embedded in the args vector.

### 3. No Injection System

- No `Injection` class or equivalent.
- No injection state management.
- No type constants.
- No `SKIP`/`DELETE` sentinels.

### 4. `clone` Is Shallow

- **TS**: Deep clones via `JSON.parse(JSON.stringify(val))`.
- **C++**: Simple JSON copy (which is deep for nlohmann::json, but the implementation returns `nullptr` for null, suggesting it may not be handling all cases).

---

## Existing Function Issues

### 1. `isfunc` Uses Template Specialization

- **TS**: Simple `typeof val === 'function'` check.
- **C++**: Complex template specialization that returns `true` for `std::function<json(args_container&&)>` and `false` for everything else.
- **Impact**: Only detects one specific function type. Cannot detect lambdas, function pointers, or other callables.

### 2. `iskey` Handles Booleans

- The C++ version explicitly returns `false` for booleans in `iskey`, which is correct (matching TS behavior since `typeof true` is not `"string"` or `"number"` in JS). Good.

### 3. `setprop` Array Handling

- Uses direct vector pointer manipulation (`(*it).data()`) for array operations.
- **Impact**: May have memory safety issues with iterator invalidation.

### 4. `stringify` Is Minimal

- Basic `dump()` call with quote stripping and optional truncation.
- Missing: sorted keys, custom formatting, depth handling.

---

## Significant Language Difference Issues

### 1. No Dynamic Typing

- **Issue**: C++ is statically typed. The library uses `nlohmann::json` to provide dynamic JSON values, but C++ has no native equivalent of JavaScript's dynamic typing.
- **Impact**: Every operation requires type checking at runtime through the JSON library's type system. This is verbose but functional.

### 2. No `undefined` vs `null` Distinction

- **Issue**: `nlohmann::json` has `null` but no `undefined`.
- **Impact**: Same as all other non-JS implementations.

### 3. Memory Management

- **Issue**: C++ requires explicit memory management. The `nlohmann::json` type handles its own memory, but function pointers, callbacks, and the `Utility`/`Provider` classes have manual memory management.
- **Impact**: Potential for memory leaks or use-after-free in the `Provider` and `Utility` classes.

### 4. No Garbage Collection

- **Issue**: Circular references in data structures cannot be automatically collected.
- **Impact**: The `walk` function must be careful about reference cycles. The `inject` system (when implemented) must handle cycles explicitly.

### 5. No Regular Expression Literals

- **Issue**: C++ uses `<regex>` library with string-based patterns.
- **Impact**: `escre` manually escapes characters (correct approach).

### 6. No Closures as First-Class Citizens (Pre-C++11)

- **Issue**: C++11 lambdas exist but are not JSON-serializable. The current approach of casting function pointers to integers is extremely fragile.
- **Impact**: The callback/handler system needs a completely different design from TS.

### 7. No Exception-Safe Error Collection

- **Issue**: C++ exception handling is more expensive than JS try/catch. The validate system (when implemented) should prefer error collection over exceptions.
- **Impact**: Design consideration for future implementation.

### 8. Template Metaprogramming Complexity

- **Issue**: The `isfunc` template specialization pattern is complex and fragile. Adding new callable types requires new specializations.
- **Impact**: Consider using a simpler runtime check instead.

---

## Test Coverage

Minimal test coverage:
- Minor function tests: `isnode`, `ismap`, `islist`, `iskey`, `isempty`, `isfunc`, `getprop`, `keysof`, `haskey`, `items`, `escre`, `escurl`, `joinurl`, `stringify`, `clone`, `setprop`
- Walk: `walk-basic` only
- Merge: `merge-basic` only
- **No tests for**: getpath, setpath, inject, transform, validate, select (functions don't exist)

Uses Catch2-style test framework with shared `test.json` spec.

---

## Alignment Plan

### Phase 1: API Redesign (Critical - Do First)
1. **Redesign function signatures** to use proper C++ parameters instead of `args_container&&`
   - Example: `json isnode(const json& val)` instead of `json isnode(args_container&& args)`
   - Keep `args_container` dispatch only for the test runner
2. **Remove intptr_t function pointer casting** from `walk`
   - Pass callback as `std::function<json(const std::string&, const json&, const json&, const std::vector<std::string>&)>`
3. **Fix isfunc** to use a runtime callable check or a dedicated `JsonFunction` wrapper

### Phase 2: Missing Minor Functions
4. Add `typify(val)` returning bitfield integers
5. Add all type constants (`T_any`, `T_noval`, `T_boolean`, etc.)
6. Add `typename(t)` function
7. Add `strkey(key)` function
8. Add `getelem(val, key, alt)` with negative index support
9. Add `getdef(val, alt)` helper
10. Add `delprop(parent, key)` function
11. Add `size(val)` function
12. Add `slice(val, start, end)` function
13. Add `flatten(list, depth)` function
14. Add `filter(val, check)` function
15. Add `pad(str, padding, padchar)` function
16. Add `replace(s, from, to)` function
17. Add `join(arr, sep, url)` function
18. Add `jsonify(val, flags)` function
19. Add `pathify(val, startin, endin)` function
20. Add `jm`/`jt` JSON builder functions
21. Add `SKIP` and `DELETE` sentinel values

### Phase 3: Path Operations
22. Implement `getpath(store, path, injdef)` with full path syntax support
23. Implement `setpath(store, path, val, injdef)`

### Phase 4: Injection System
24. Design and implement `Injection` class/struct
25. Implement `inject(val, store, injdef)` with full injection system
26. Implement `injectChild(child, store, inj)`
27. Add `checkPlacement` and `injectorArgs` functions

### Phase 5: Transform
28. Implement `transform(data, spec, injdef)` with all commands:
    - `$DELETE`, `$COPY`, `$KEY`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`
    - `$REF`, `$FORMAT`, `$APPLY`, `$BT`, `$DS`, `$WHEN`

### Phase 6: Validate
29. Implement `validate(data, spec, injdef)` with all validators:
    - `$MAP`, `$LIST`, `$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`
    - `$BOOLEAN`, `$NULL`, `$NIL`, `$FUNCTION`, `$INSTANCE`, `$ANY`
    - `$CHILD`, `$ONE`, `$EXACT`

### Phase 7: Select
30. Implement `select(children, query)` with operators:
    - `$AND`, `$OR`, `$NOT`, `$GT`, `$LT`, `$GTE`, `$LTE`, `$LIKE`

### Phase 8: Walk Enhancement
31. Add `before`/`after` callback support to `walk`
32. Add `maxdepth` parameter

### Phase 9: Test Coverage
33. Add tests for all new functions using shared `test.json`
34. Add all test categories matching TS suite
35. Ensure memory safety (run with AddressSanitizer)
36. Ensure no undefined behavior (run with UBSan)

### Phase 10: Code Quality
37. Add proper error handling (not exceptions for expected cases)
38. Review memory management in Utility/Provider classes
39. Add const-correctness throughout
40. Consider using `std::optional` for absent values
