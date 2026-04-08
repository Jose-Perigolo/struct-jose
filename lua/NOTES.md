# Lua Implementation Notes

## undefined vs null

Lua has only `nil` — there is no native distinction between "absent" and "null".
Additionally, setting a table key to `nil` removes the key entirely.
For this library:
- `nil` is used to represent **property absence** (the TypeScript `undefined` equivalent).
- TypeScript tests relating to `undefined` should be treated as **property absence**: the key
  does not exist in the table, or the function parameter was not provided.
- JSON null is ambiguous with `nil`. Where the distinction matters, the test runner uses
  marker strings: `NULLMARK = '__NULL__'` for JSON null and `UNDEFMARK = '__UNDEF__'` for absent values.
- Since `nil` cannot be stored as a table value (it deletes the key), a sentinel value
  (e.g., `json.null` from the JSON library) may be needed where JSON null must be preserved.
- In practice, most APIs do not use JSON null, so this ambiguity rarely causes issues.

## Type System

This implementation uses bitfield integers for the type system, matching the TypeScript canonical.
Type constants (`T_any`, `T_noval`, `T_boolean`, etc.) are exported and `typify()` returns
integer bitfields. Use `typename()` to get the human-readable name for error messages.
Bitwise operations allow composite type checks (e.g., `T_scalar | T_string`).

## 1-Based Indexing

Lua tables use 1-based indexing internally. The library translates to 0-based indexing at the
API boundary to match the cross-language test suite and TypeScript canonical behavior. All
external-facing index values (path arrays, `keysof` output, `getprop`/`setprop` keys) use
0-based integers.
