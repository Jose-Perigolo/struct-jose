# C++ Implementation Notes

## undefined vs null

C++ (via nlohmann::json) has only `null` (JSON null) — there is no native distinction between
"absent" and "null".
For this library:
- `nullptr` / `json(nullptr)` is used to represent **property absence** (the TypeScript
  `undefined` equivalent).
- TypeScript tests relating to `undefined` should be treated as **property absence**: the key
  does not exist in the JSON object, or the function parameter was not provided.
- JSON null is ambiguous with absent. Where the distinction matters, the test runner should use
  marker strings: `NULLMARK = "__NULL__"` for JSON null and `UNDEFMARK = "__UNDEF__"` for absent values.
- Consider using `std::optional<json>` to distinguish absent from null where needed.
- In practice, most APIs do not use JSON null, so this ambiguity rarely causes issues.

## Type System

This implementation uses bitfield integers for the type system, matching the TypeScript canonical.
Type constants (`T_any`, `T_noval`, `T_boolean`, etc.) are defined in the `VoxgigStruct` namespace
and `typify()` returns integer bitfields. Use `typename()` to get the human-readable name for
error messages. Bitwise operations allow composite type checks (e.g., `T_scalar | T_string`).
