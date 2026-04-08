# Go Implementation Notes

## undefined vs null

Go has only `nil` — there is no native distinction between "absent" and "null".
For this library:
- `nil` is used to represent **property absence** (the TypeScript `undefined` equivalent).
- TypeScript tests relating to `undefined` should be treated as **property absence**: the key
  does not exist in the map, or the function parameter was not provided.
- JSON null is ambiguous with `nil`. Where the distinction matters, the test runner uses
  marker strings: `NULLMARK = "__NULL__"` for JSON null and `UNDEFMARK = "__UNDEF__"` for absent values.
- In practice, most APIs do not use JSON null, so this ambiguity rarely causes issues.

## Type System

This implementation uses bitfield integers for the type system, matching the TypeScript canonical.
Type constants (`T_any`, `T_noval`, `T_boolean`, etc.) are exported and `Typify()` returns
integer bitfields. Use `Typename()` to get the human-readable name for error messages.
Bitwise operations allow composite type checks (e.g., `T_scalar | T_string`).
