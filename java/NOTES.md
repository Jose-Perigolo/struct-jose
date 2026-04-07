# Java Implementation Notes

## undefined vs null

Java has only `null` — there is no native distinction between "absent" and "null".
For this library:
- `null` is used to represent **property absence** (the TypeScript `undefined` equivalent).
- TypeScript tests relating to `undefined` should be treated as **property absence**: the key
  does not exist in the Map, or the function parameter was not provided.
- JSON null is ambiguous with `null`. Where the distinction matters, the test runner should use
  marker strings: `NULLMARK = "__NULL__"` for JSON null and `UNDEFMARK = "__UNDEF__"` for absent values.
- A sentinel object (e.g., `static final Object UNDEF = new Object()`) may be used internally
  to distinguish absent from null where required.
- In practice, most APIs do not use JSON null, so this ambiguity rarely causes issues.

## Type System

This implementation uses bitfield integers for the type system, matching the TypeScript canonical.
Type constants (`T_any`, `T_noval`, `T_boolean`, etc.) are defined as static fields and `typify()`
returns integer bitfields. Use `typename()` to get the human-readable name for error messages.
Bitwise operations allow composite type checks (e.g., `T_scalar | T_string`).
