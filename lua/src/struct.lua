-- JSON-like Utilities Module
local M = {}

local S = {
  -- Mode value for inject step.
  ["MKEYPRE"]  = "key:pre",
  ["MKEYPOST"] = "key:post",
  ["MVAL"]     = "val",
  ["MKEY"]     = "key",

  -- Special keys.
  ["DKEY"]     = "`$KEY`",
  ["DTOP"]     = "$TOP",
  ["DERRS"]    = "$ERRS",
  ["DMETA"]    = "`$META`",

  -- General strings.
  ["array"]    = "table",
  ["base"]     = "base",
  ["boolean"]  = "boolean",
  ["empty"]    = "",
  ["function"] = "function",
  ["number"]   = "number",
  ["object"]   = "table",
  ["string"]   = "string",
  ["null"]     = "none",
  ["key"]      = "key",
  ["parent"]   = "parent",
  ["BT"]       = "`",
  ["DS"]       = "$",
  ["DT"]       = ".",
  ["KEY"]      = "KEY",
}

-- The standard undefined value for this language.
local UNDEF = nil

--[[
  Checks if a value is a JSON-like node (table that is a list or map).
  @param value any  The value to check.
  @return boolean  True if the value is a table (list or map), false otherwise.
]]
function M.isnode(val)
  return S["object"] == type(val)
end

--[[
  Checks if a value is a JSON-like list (array).
  A list is defined as a table with consecutive integer keys starting at 1.
  @param value any  The value to check.
  @return boolean  True if the value is a list (array), false otherwise.
]]
function M.islist(val)
  if type(val) ~= S["array"] then return false end
  local count = 0
  for k, _ in pairs(val) do
    if type(k) ~= S["number"] then
      return false -- found a non-numeric key, so not a list
    end
    count = count + 1
  end
  -- ensure keys 1..count exist with no gaps
  for i = 1, count do
    if val[i] == UNDEF then return false end
  end
  return true
end

--[[
  Checks if a value is a JSON-like map (object with string keys).
  A map is a table that is not identified as a list.
  @param value any  The value to check.
  @return boolean  True if the value is a map (object), false otherwise.
]]
function M.ismap(val)
  if type(val) ~= S["object"] then return false end
  return not M.islist(val)
end

--[[
  Checks if a given key is a valid JSON-like key.
  In JSON, keys are typically strings (or can be numeric indices for arrays).
  @param key any  The key to check.
  @return boolean  True if the key is a string (non-empty) or number, false otherwise.
]]
function M.iskey(key)
  local keytype = type(key)

  return (S["string"] == keytype and S["empty"] ~= key) or S["number"] == keytype
end

--[[
  Checks if a value is a function.
  @param value any  The value to check.
  @return boolean  True if the value is of type 'function', false otherwise.
]]
function M.isfunc(val)
  return S["function"] == type(val)
end

--[[
  Checks if a given value (node or primitive) is "empty".
  - For lists: returns true if the list has length 0.
  - For maps: returns true if the map has no keys.
  - For other types (including nil): returns true if the value is nil or an empty string.
  @param value any  The value to check.
  @return boolean  True if the value is empty as per above rules.
]]
function M.isempty(val)
  if type(val) == S["object"] or type(val) == S["array"] then
    return next(val) == UNDEF
  elseif val == UNDEF or val == S["empty"] then
    return true
  end
  return false
end

--[[
  Returns an array of keys for a given JSON-like node.
  @param node table  The map or list to extract keys from.
  @return table  Array of keys (numeric indices for lists, string keys for maps). Returns empty table for non-table inputs.
]]
function M.keysof(val)
  if not M.isnode(val) then
    return {}
  elseif M.ismap(val) then
    local pairs = {}
    for k, v in pairs(val) do
      table.insert(pairs, { key = k, value = v })
    end

    table.sort(pairs, function(a, b) return a.key < b.key end)

    local sorted = {}
    for _, pair in ipairs(pairs) do
      sorted[pair.key] = pair.value
    end

    return sorted
  else
    local indices = {}
    for i = 1, #val do
      table.insert(indices, i)
    end
    return indices
  end
end

--[[
  Checks if a given table (map or list) contains a specific key.
  @param node table  The table to check.
  @param key any  The key to look for.
  @return boolean  True if the key exists in the table (and maps to a non-nil value), false otherwise.
]]
function M.haskey(node, key)
  if type(node) ~= "table" then return false end
  return node[key] ~= UNDEF
end

--[[
  Deep-clones a JSON-like structure.
  Primitives (number, string, boolean, nil, function) are returned as-is (functions are not copied).
  Tables (lists or maps) are cloned recursively.
  @param value any  The value to clone.
  @return any  A new cloned value structurally identical to the input.
]]
function M.clone(value)
  if type(value) ~= "table" then
    -- primitive types and functions are returned directly
    return value
  end
  if M.islist(value) then
    local new_list = {}
    for i, v in ipairs(value) do
      new_list[i] = M.clone(v)
    end
    return new_list
  else
    local new_map = {}
    for k, v in pairs(value) do
      new_map[k] = M.clone(v)
    end
    return new_map
  end
end

--[[
  Returns a list of key-value pair entries for a given node.
  For lists, numeric indices (1-based) act as keys; for maps, string keys are used.
  @param node table  The JSON-like table to get items from.
  @return table  An array of two-element tables {key, value} for each entry in the node.
]]
function M.items(node)
  local entries = {}
  if type(node) == "table" then
    if M.islist(node) then
      for i, v in ipairs(node) do
        entries[#entries + 1] = { i, v }
      end
    else
      for k, v in pairs(node) do
        entries[#entries + 1] = { k, v }
      end
    end
  end
  return entries
end

--[[
  Safely gets a property from a map or list, with an optional default.
  @param node table  The table (map or list) to query.
  @param key any  The key or index to retrieve.
  @param default any  (Optional) Default value to return if the key is not present.
  @return any  The value at the given key, or the default value (or nil if not provided and key missing).
]]
function M.getprop(node, key, default)
  if type(node) ~= "table" then
    return default
  end
  local val = node[key]
  if val == UNDEF then
    return default
  end
  return val
end

--[[
  Sets a property on a map or list.
  @param node table  The table (map or list) to modify.
  @param key any  The key or index to set.
  @param value any  The value to set at the given key.
  @return table  The modified table (same as the input node).
]]
function M.setprop(node, key, value)
  if type(node) ~= "table" then
    return node -- not a table, nothing to set
  end
  node[key] = value
  return node
end

--[[
  Converts a JSON-like structure to a JSON string.
  Booleans, numbers, and strings are converted to their JSON representations.
  Lists and maps are converted recursively to JSON array and object syntax.
  The `nil` value is converted to JSON "null". Functions and unsupported types are omitted or represented as null.
  @param value any  The JSON-like value to stringify.
  @return string  A JSON-formatted string representing the input value.
]]
function M.stringify(value)
  -- Helper to escape special characters in JSON strings (quotes, backslashes, control chars)
  local function escape_str(str)
    -- Replace special characters with escape sequences
    str = str:gsub("\\", "\\\\")
        :gsub("\"", "\\\"")
        :gsub("\b", "\\b")
        :gsub("\f", "\\f")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
    -- Replace other control characters (0x00-0x1F) with \u00XX sequences
    str = str:gsub("([^%w%p%s])", function(ch)
      return string.format("\\u%04X", string.byte(ch))
    end)
    return str
  end

  local t = type(value)
  if value == UNDEF then
    return "null"
  elseif t == "boolean" or t == "number" then
    -- JSON booleans and numbers are same text representation as Lua
    if t == "number" then
      -- JSON does not allow NaN/Inf, represent them as null
      if value ~= value or value == math.huge or value == -math.huge then
        return "null"
      end
    end
    return tostring(value)
  elseif t == "string" then
    return "\"" .. escape_str(value) .. "\""
  elseif t == "function" or t == "userdata" or t == "thread" then
    -- Unsupported types in JSON; represent as null
    return "null"
  elseif M.islist(value) then
    local parts = {}
    for i, v in ipairs(value) do
      parts[#parts + 1] = M.stringify(v)
    end
    return "[" .. table.concat(parts, ",") .. "]"
  elseif M.ismap(value) then
    local parts = {}
    for k, v in pairs(value) do
      if type(k) == "string" then
        local keyStr = escape_str(k)
        parts[#parts + 1] = "\"" .. keyStr .. "\":" .. M.stringify(v)
      end
      -- Note: if key is not a string, it will be ignored (JSON object keys must be strings)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  else
    -- Fallback for any other type (should not happen in JSON-like data)
    return "null"
  end
end

--[[
  Escapes a string for safe use in a Lua pattern or regular expression.
  It prepends '%' to all magic characters.
  @param s string|nil  The input string to escape (nil is treated as empty string).
  @return string  The escaped string, safe for use in pattern matching.
]]
function M.escre(s)
  if s == UNDEF then return "" end
  -- Pattern of characters to escape: ^$()%.[]*+-?{}|
  return (tostring(s):gsub("([%^%$%(%)%[%]%.%*%+%-%?%{%}%|])", "%%%1"))
end

--[[
  Escapes a string for safe use in a URL (percent-encoding).
  Encodes all characters except alphanumeric and the characters - _ . ~
  @param s string|number  The input value to encode (will be converted to string).
  @return string  The URL-encoded string.
]]
function M.escurl(s)
  if s == UNDEF then return "" end
  s = tostring(s)
  return (s:gsub("([^%w%._~%-])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

--[[
  Joins multiple URL path segments into one, ensuring proper slashes.
  It trims any leading/trailing slashes from each segment and then joins them with a single '/'.
  (Note: It does not handle URL query '?' or fragment '#' specially; those should be passed as part of a segment if needed.)
  @param ... string  Multiple string arguments representing parts of a URL path.
  @return string  The joined URL path.
]]
function M.joinurl(...)
  local parts = {}
  for _, segment in ipairs { ... } do
    local seg = tostring(segment or "")
    -- Remove leading and trailing slashes
    seg = seg:gsub("^/*", ""):gsub("/*$", "")
    if seg ~= "" then
      parts[#parts + 1] = seg
    end
  end
  -- Special case: if first part was just "/" (root), retain it
  if select(1, ...) == "/" then
    return "/" .. table.concat(parts, "/")
  end
  return table.concat(parts, "/")
end

--[[
  Retrieves a nested value from a JSON-like structure using a path.
  The path can be provided as a string (dot-separated keys) or as an array of keys.
  @param node table        The root JSON-like structure (list or map) to traverse.
  @param path string|table The path to navigate, e.g. "user.address.city" or {"user","address","city"}.
  @param default any       (Optional) Default value to return if the path is not found.
  @return any  The value at the given path, or the default (or nil) if not found.
]]
function M.getpath(node, path, default)
  if node == UNDEF then return default end
  -- If path is a string, split it on dots to get components
  local keys = {}
  if type(path) == "string" then
    if path == "" then
      return node -- empty path returns the node itself
    end
    for key in string.gmatch(path, "[^%.]+") do
      keys[#keys + 1] = key
    end
  elseif type(path) == "table" then
    for _, key in ipairs(path) do
      keys[#keys + 1] = key
    end
  else
    -- unsupported path type
    return default
  end

  local current = node
  for _, key in ipairs(keys) do
    if type(current) ~= "table" then
      return default
    end
    current = current[key]
    if current == UNDEF then
      return default
    end
  end
  return current
end

-- Internal helper for merging two nodes (used by M.merge)
local function _merge_two(a, b)
  if M.islist(a) and M.islist(b) then
    -- Merge lists by concatenation (append elements of b into a)
    for _, v in ipairs(b) do
      a[#a + 1] = M.clone(v)
    end
    return a
  elseif M.ismap(a) and M.ismap(b) then
    -- Merge maps by key, deep merging any common sub-nodes
    for k, v in pairs(b) do
      if M.isnode(a[k]) and M.isnode(v) then
        -- Both are tables (nodes): merge recursively
        a[k] = _merge_two(a[k], M.clone(v))
      else
        -- Otherwise, overwrite or add new key (clone to avoid reference sharing)
        a[k] = M.clone(v)
      end
    end
    return a
  else
    -- If types differ or either is not a node, the second value overrides the first
    return M.clone(b)
  end
end

--[[
  Deep merges two or more JSON-like structures into a new one.
  - For maps: keys from later structures override or are combined with earlier ones. Nested tables are merged recursively.
  - For lists: elements from later lists are appended to the earlier list.
  - If a value in later structures is not a table (node), it overrides the previous value entirely.
  @param base any    The first structure to merge (will not be mutated).
  @param ...  any    Additional structures to merge into the base.
  @return any  A new merged JSON-like structure.
]]
function M.merge(base, ...)
  local result = M.clone(base)
  for _, nextStruct in ipairs({ ... }) do
    result = _merge_two(result, nextStruct)
  end
  return result
end

--[[
  Recursively walks a JSON-like structure, invoking a callback for each value.
  The callback is called for every value (including nested ones) with parameters (value, key, parent, path).
  - value: the current value at the node.
  - key: the key or index of this value in its parent (nil for the root).
  - parent: the parent table containing this value (nil for the root).
  - path: an array representing the path (keys) to this value from the root.
  @param node any                              The root of the JSON-like structure to walk.
  @param callback function(value, key, parent, path)  Function to call on each value.
]]
function M.walk(node, callback)
  local function _walk(value, key, parent, path)
    callback(value, key, parent, path)
    if type(value) ~= "table" then
      return
    end
    if M.islist(value) then
      for i, v in ipairs(value) do
        path[#path + 1] = i      -- push current key
        _walk(v, i, value, path) -- recurse into list element
        path[#path] = UNDEF      -- pop current key
      end
    else                         -- map
      for k, v in pairs(value) do
        path[#path + 1] = k
        _walk(v, k, value, path)
        path[#path] = UNDEF
      end
    end
  end
  _walk(node, UNDEF, UNDEF, {})
end

--[[
  Reduces a JSON-like structure to a single value by iterating over all values.
  The reducer function is called for each value in the structure (deeply nested included).
  @param node any             The root of the structure to reduce.
  @param initial any          The initial accumulator value.
  @param reducer function(acc, value, key, parent, path)  The reducing function.
  @return any  The final accumulated result after processing all values.
]]
function M.inject(node, initial, reducer)
  local acc = initial
  M.walk(node, function(val, key, parent, path)
    acc = reducer(acc, val, key, parent, path)
  end)
  return acc
end

--[[
  Transforms a JSON-like structure by applying a function to each value, returning a new structure.
  The transform function is applied to each non-table value and the result is placed into a new structure of the same shape.
  @param node any                           The root of the structure to transform.
  @param fn function(value, key, parent, path)  Function to transform each non-table value.
  @return any  A new JSON-like structure where every non-table value has been transformed by `fn`.
]]
function M.transform(node, fn)
  local function _transform(value, key, parent, path)
    if type(value) ~= "table" then
      -- Primitive or function value: apply transform function
      return fn(value, key, parent, path)
    end
    if M.islist(value) then
      local new_list = {}
      for i, v in ipairs(value) do
        path[#path + 1] = i
        new_list[i] = _transform(v, i, value, path)
        path[#path] = UNDEF
      end
      return new_list
    else -- map
      local new_map = {}
      for k, v in pairs(value) do
        path[#path + 1] = k
        new_map[k] = _transform(v, k, value, path)
        path[#path] = UNDEF
      end
      return new_map
    end
  end
  return _transform(node, UNDEF, UNDEF, {})
end

--[[
  Validates that a value is a proper JSON-like structure.
  Rules checked:
    - Primitives allowed: string, number (finite), boolean, nil (treated as null).
    - Tables must be either lists or maps as defined by islist/ismap.
    - Map keys must be strings (non-empty).
    - No functions, userdata, or thread values are allowed.
    - No circular references (cycles) in the structure.
  @param value any  The value to validate.
  @return boolean  True if the value is a valid JSON-like structure, false otherwise.
]]
function M.validate(value)
  local seen = {} -- for cycle detection
  local function _validate(x)
    local t = type(x)
    if x == UNDEF or t == "boolean" or t == "string" then
      return true
    elseif t == "number" then
      -- number must be finite and not NaN
      if x ~= x or x == math.huge or x == -math.huge then
        return false
      end
      return true
    elseif t == "function" or t == "userdata" or t == "thread" then
      return false -- invalid type for JSON
    elseif t == "table" then
      if seen[x] then
        return false -- cycle detected
      end
      seen[x] = true
      local valid
      if M.islist(x) then
        -- validate each element in the list
        valid = true
        for _, v in ipairs(x) do
          if not _validate(v) then
            valid = false
            break
          end
        end
      elseif M.ismap(x) then
        -- all keys must be strings, and values valid
        valid = true
        for k, v in pairs(x) do
          if type(k) ~= "string" or k == "" then
            valid = false
            break
          end
          if not _validate(v) then
            valid = false
            break
          end
        end
      else
        -- Table is neither a proper list nor map (mixed or sparse array)
        valid = false
      end
      seen[x] = UNDEF
      return valid
    else
      -- any other type (should not happen)
      return false
    end
  end
  return _validate(value)
end

-- Return the module table
return M
