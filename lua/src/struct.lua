-- Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.

-- VERSION: @voxgig/struct 0.0.9

--[[
  Voxgig Struct
  =============

  Utility functions to manipulate in-memory JSON-like data
  structures. These structures assumed to be composed of nested
  "nodes", where a node is a list or map, and has named or indexed
  fields.  The general design principle is "by-example". Transform
  specifications mirror the desired output. This implementation is
  designed for porting to multiple language, and to be tolerant of
  undefined values.

  Main utilities
  - getpath: get the value at a key path deep inside an object.
  - merge: merge multiple nodes, overriding values in earlier nodes.
  - walk: walk a node tree, applying a function at each node and leaf.
  - inject: inject values from a data store into a new data structure.
  - transform: transform a data structure to an example structure.
  - validate: validate a data structure against a shape specification.

  Minor utilities
  - isnode, islist, ismap, iskey, isfunc: identify value kinds.
  - isempty: undefined values, or empty nodes.
  - keysof: sorted list of node keys (ascending).
  - haskey: true if key value is defined.
  - clone: create a copy of a JSON-like data structure.
  - items: list entries of a map or list as [key, value] pairs.
  - getprop: safely get a property value by key.
  - setprop: safely set a property value by key.
  - stringify: human-friendly string version of a value.
  - escre: escape a regular expresion string.
  - escurl: escape a url.
  - joinurl: join parts of a url, merging forward slashes.

  This set of functions and supporting utilities is designed to work
  uniformly across many languages, meaning that some code that may be
  functionally redundant in specific languages is still retained to
  keep the code human comparable.

  NOTE: Lists are assumed to be mutable and reference stable.

  NOTE: In this code JSON nulls are in general *not* considered the
  same as undefined values in the given language. However most
  JSON parsers do use the undefined value to represent JSON
  null. This is ambiguous as JSON null is a separate value, not an
  undefined value. You should convert such values to a special value
  to represent JSON null, if this ambiguity creates issues
  (thankfully in most APIs, JSON nulls are not used). For example,
  the unit tests use the string "__NULL__" where necessary.
]] ----------------------------------------------------------
-- String constants are explicitly defined.
----------------------------------------------------------

-- Mode value for inject step.
local S_MKEYPRE = 'key:pre'
local S_MKEYPOST = 'key:post'
local S_MVAL = 'val'
local S_MKEY = 'key'

-- Special strings.
local S_BKEY = '`$KEY`'
local S_BANNO = '`$ANNO`'
local S_BEXACT = '`$EXACT`'
local S_BVAL = '`$VAL`'

local S_DKEY = '$KEY'
local S_DTOP = '$TOP'
local S_DERRS = '$ERRS'
local S_DSPEC = '$SPEC'

-- General strings.
local S_list = 'list'
local S_base = 'base'
local S_boolean = 'boolean'
local S_function = 'function'
local S_symbol = 'symbol'
local S_instance = 'instance'
local S_key = 'key'
local S_any = 'any'
local S_nil = 'nil'
local S_null = 'null'
local S_number = 'number'
local S_object = 'object'
local S_string = 'string'
local S_decimal = 'decimal'
local S_integer = 'integer'
local S_map = 'map'
local S_scalar = 'scalar'
local S_node = 'node'

-- Character strings.
local S_BT = '`'
local S_CN = ':'
local S_CS = ']'
local S_DS = '$'
local S_DT = '.'
local S_FS = '/'
local S_KEY = 'KEY'
local S_MT = ''
local S_OS = '['
local S_SP = ' '
local S_VIZ = ': '


-- Types (bit flags)
-- Using explicit bit positions to match TS implementation
local T_any = (1 << 31) - 1        -- All bits set
local T_noval = 1 << 30            -- Property absent, undefined
local T_boolean = 1 << 29
local T_decimal = 1 << 28
local T_integer = 1 << 27
local T_number = 1 << 26
local T_string = 1 << 25
local T_function = 1 << 24
local T_symbol = 1 << 23
local T_null = 1 << 22             -- Actual JSON null value
-- gap of 7
local T_list = 1 << 14
local T_map = 1 << 13
local T_instance = 1 << 12
-- gap of 4
local T_scalar = 1 << 7
local T_node = 1 << 6

local TYPENAME = {
  S_any,
  S_nil,
  S_boolean,
  S_decimal,
  S_integer,
  S_number,
  S_string,
  S_function,
  S_symbol,
  S_null,
  '', '', '',
  '', '', '', '',
  S_list,
  S_map,
  S_instance,
  '', '', '', '',
  S_scalar,
  S_node,
}


-- The standard undefined value for this language.
local NONE = nil

-- Private marker to indicate a skippable value.
local SKIP = { ['`$SKIP`'] = true }

local DELETE = { ['`$DELETE`'] = true }

local MAXDEPTH = 32

----------------------------------------------------------
-- Forward declarations to work around the lack of function hoisting
----------------------------------------------------------
local _injectstr
local _injecthandler
local _validatehandler
local _invalidTypeMsg
local _validation
local ismap
local islist
local getpath


-- Return type string for narrowest type.
local function typename(t)
  -- Math.clz32 equivalent: count leading zeros in a 32-bit integer
  local function clz32(x)
    if x == 0 then return 32 end
    local n = 0
    if (x & 0xFFFF0000) == 0 then n = n + 16; x = x << 16 end
    if (x & 0xFF000000) == 0 then n = n + 8; x = x << 8 end
    if (x & 0xF0000000) == 0 then n = n + 4; x = x << 4 end
    if (x & 0xC0000000) == 0 then n = n + 2; x = x << 2 end
    if (x & 0x80000000) == 0 then n = n + 1 end
    return n
  end
  local idx = clz32(t) + 1  -- 1-based index
  if idx >= 1 and idx <= #TYPENAME then
    return TYPENAME[idx]
  end
  return TYPENAME[1]  -- S_any
end

-- Value is a node - defined, and a map (hash) or list (array).
-- @param val (any) The value to check
-- @return (boolean) True if value is a node
local function isnode(val)
  if val == nil then
    return false
  end

  return ismap(val) or islist(val)
end


-- Value is a defined map (hash) with string keys.
-- @param val (any) The value to check
-- @return (boolean) True if value is a map
ismap = function(val)
  -- Check if the value is a table
  if type(val) ~= "table" or
      (getmetatable(val) and getmetatable(val).__jsontype == "array") then
    return false
  end

  -- Check for explicit object metatable
  if getmetatable(val) and getmetatable(val).__jsontype == "object" then
    return true
  end

  -- Iterate over the table to check if it has string keys
  for k, _ in pairs(val) do
    if type(k) ~= "string" then
      return false
    end
  end

  return true
end


-- Value is a defined list (array) with integer keys (indexes).
-- @param val (any) The value to check
-- @return (boolean) True if value is a list
islist = function(val)
  -- First check metatable indicators (preferred approach)
  if getmetatable(val) and ((getmetatable(val).__jsontype == "array") or
        (getmetatable(val).__jsontype and getmetatable(val).__jsontype.type ==
          "array")) then
    return true
  end

  -- Check if it's a table
  if type(val) ~= "table" or
      (getmetatable(val) and getmetatable(val).__jsontype == "object") then
    return false
  end

  -- Count total elements and max integer key
  local count = 0
  local max = 0
  for k, _ in pairs(val) do
    if type(k) == S_number then
      if k > max then
        max = k
      end
      count = count + 1
    end
  end

  -- Check if all keys are consecutive integers starting from 1
  return count > 0 and max == count
end


-- Value is a defined string (non-empty) or integer key.
-- @param key (any) The key to check
-- @return (boolean) True if key is valid
local function iskey(key)
  local keytype = type(key)
  return (keytype == S_string and key ~= S_MT and key ~= S_null) or keytype ==
      S_number
end


-- Get a defined value. Returns alt if val is nil.
local function getdef(val, alt)
  if nil == val then
    return alt
  end
  return val
end


-- The integer size of the value.
local function size(val)
  if islist(val) then
    return #val
  elseif ismap(val) then
    local count = 0
    for _ in pairs(val) do count = count + 1 end
    return count
  end

  local valtype = type(val)

  if S_string == valtype then
    return #val
  elseif S_number == valtype then
    return math.floor(val)
  elseif S_boolean == valtype then
    return val and 1 or 0
  else
    return 0
  end
end


-- Check for an "empty" value - nil, empty string, array, object.
-- @param val (any) The value to check
-- @return (boolean) True if value is empty
local function isempty(val)
  -- Check if the value is nil
  if val == nil or val == S_null then
    return true
  end

  -- Check if the value is an empty string
  if type(val) == "string" and val == S_MT then
    return true
  end

  -- Check if the value is an empty table (array or map)
  if type(val) == "table" then
    return next(val) == nil
  end

  -- If none of the above, the value is not empty
  return false
end


-- Value is a function.
-- @param val (any) The value to check
-- @return (boolean) True if value is a function
local function isfunc(val)
  return type(val) == 'function'
end


-- Determine the type of a value as a bit code.
-- @param value (any) The value to check
-- @return (number) The type as a bit flag
local function typify(value)
  if value == nil then
    return T_noval
  end

  local luatype = type(value)

  if luatype == S_number then
    if value ~= value then  -- NaN check
      return T_noval
    elseif math.type(value) == 'integer' or (value % 1 == 0) then
      return T_scalar | T_number | T_integer
    else
      return T_scalar | T_number | T_decimal
    end
  elseif luatype == S_string then
    return T_scalar | T_string
  elseif luatype == S_boolean then
    return T_scalar | T_boolean
  elseif luatype == S_function then
    return T_scalar | T_function
  elseif luatype == 'table' then
    if islist(value) then
      return T_node | T_list
    elseif ismap(value) then
      return T_node | T_map
    end
    return T_node | T_map
  end

  -- Anything else is considered T_any
  return T_any
end


-- Safely get a property of a node. Nil arguments return nil.
-- If the key is not found, return the alternative value, if any.
-- @param val (any) The parent object/table
-- @param key (any) The key to access
-- @param alt (any) The alternative value if key not found
-- @return (any) The property value or alternative
local function getprop(val, key, alt)
  -- Handle nil arguments
  if val == NONE or key == NONE then
    return alt
  end

  local out = nil

  -- Handle tables (maps and arrays in Lua)
  if type(val) == "table" then
    -- Convert key to string if it's a number
    local lookup_key = key
    if type(key) == "number" then
      -- Lua arrays are 1-based
      lookup_key = tostring(math.floor(key))
    elseif type(key) ~= "string" then
      -- Convert other types to string
      lookup_key = tostring(key)
    end
    if islist(val) then
      -- Lua arrays are 1-based, so we need to adjust the index
      for i = 1, #val do
        local zero_based_index = i - 1
        if lookup_key == tostring(zero_based_index) then
          out = val[i]
          break
        end
      end
    else
      out = val[lookup_key]
    end
  end

  -- Return alternative if out is nil
  if out == nil then
    return alt
  end

  return out
end


-- Get a list element. The key should be an integer, or a string
-- that can parse to an integer only. Negative integers count from the end of the list.
local function getelem(val, key, alt)
  local out = NONE

  if NONE == val or NONE == key then
    return alt
  end

  if islist(val) then
    local nkey = tonumber(key)
    if nkey ~= nil and nkey == math.floor(nkey) then
      if nkey < 0 then
        nkey = #val + nkey
      end
      -- Convert 0-based to 1-based
      out = val[nkey + 1]
    end
  end

  if NONE == out then
    if NONE ~= alt and type(alt) == S_function then
      return alt()
    end
    return alt
  end

  return out
end


-- Convert different types of keys to string representation.
-- String keys are returned as is.
-- Number keys are converted to strings.
-- Floats are truncated to integers.
-- Booleans, objects, arrays, null, undefined all return empty string.
-- @param key (any) The key to convert
-- @return (string) The string representation of the key
local function strkey(key)
  if key == NONE or key == S_null then
    return S_MT
  end

  if type(key) == S_string then
    return key
  end

  if type(key) == S_boolean then
    return S_MT
  end

  if type(key) == S_number then
    return key % 1 == 0 and tostring(key) or tostring(math.floor(key))
  end

  return S_MT
end


-- Sorted keys of a map, or indexes of a list.
-- @param val (any) The object or array to get keys from
-- @return (table) Array of keys as strings
local function keysof(val)
  if not isnode(val) then
    return {}
  end

  if ismap(val) then
    -- For maps, collect all keys and sort them
    local keys = {}
    for k, _ in pairs(val) do
      table.insert(keys, k)
    end
    table.sort(keys)
    return keys
  else
    -- For lists, create array of stringified indices (0-based to match JS/Go)
    local indexes = {}
    for i = 1, #val do
      -- Subtract 1 to convert from Lua's 1-based to 0-based indexing
      table.insert(indexes, tostring(i - 1))
    end
    return indexes
  end
end


-- Value of property with name key in node val is defined.
-- @param val (any) The object to check
-- @param key (any) The key to check
-- @return (boolean) True if key exists in val
local function haskey(val, key)
  return getprop(val, key) ~= NONE
end


-- List the sorted keys of a map or list as an array of tuples of the form {key, value}
-- @param val (any) The object or array to convert to key-value pairs
-- @return (table) Array of {key, value} pairs
local function items(val)
  if type(val) ~= "table" then
    return {}
  end

  local result = {}

  if islist(val) then
    -- Handle array-like tables
    for i, v in ipairs(val) do
      -- Lua is 1-indexed, so we need to adjust the index
      table.insert(result, { i - 1, v })
    end
  else
    local keys = {}
    for k in pairs(val) do
      table.insert(keys, k)
    end
    table.sort(keys)

    for _, k in ipairs(keys) do
      table.insert(result, { k, val[k] })
    end
  end

  return result
end


-- Escape regular expression.
-- @param s (string) The string to escape
-- @return (string) The escaped string
local function escre(s)
  s = s or S_MT
  local result, _ = s:gsub("([.*+?^${}%(%)%[%]\\|])", "\\%1")
  return result
end


-- Escape URLs.
-- @param s (string) The string to escape
-- @return (string) The URL-encoded string
local function escurl(s)
  s = s or S_MT
  -- Exact match for encodeURIComponent behavior
  local result, _ = s:gsub("([^%w-_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return result
end


-- Return a sub-array. Start and end are 0-based, end is exclusive.
local function slice(val, start, endidx)
  if not islist(val) then
    if S_string == type(val) then
      start = start or 0
      endidx = endidx or #val
      return string.sub(val, start + 1, endidx)
    end
    return {}
  end
  local len = #val
  start = start or 0
  endidx = endidx or len

  if start < 0 then start = len + start end
  if endidx < 0 then endidx = len + endidx end

  local result = {}
  setmetatable(result, { __jsontype = "array" })
  for i = start + 1, endidx do
    if i >= 1 and i <= len then
      table.insert(result, val[i])
    end
  end
  return result
end


-- Flatten nested lists to a given depth.
local function flatten(val, depth)
  if not islist(val) then
    return val
  end
  depth = depth or 1
  local result = {}
  setmetatable(result, { __jsontype = "array" })

  for _, item in ipairs(val) do
    if islist(item) and depth > 0 then
      local sub = flatten(item, depth - 1)
      for _, v in ipairs(sub) do
        table.insert(result, v)
      end
    else
      table.insert(result, item)
    end
  end
  return result
end


-- Pad a string or number.
local function pad(val, padlen, padchar)
  padlen = padlen or 0
  padchar = padchar or S_SP
  val = tostring(val or S_MT)
  while #val < padlen do
    val = padchar .. val
  end
  return val
end


-- Delete a property from a node.
local function delprop(parent, key)
  if not iskey(key) then
    return parent
  end

  if ismap(parent) then
    key = tostring(key)
    parent[key] = nil
  elseif islist(parent) then
    local keyI = tonumber(key)
    if keyI ~= nil then
      keyI = math.floor(keyI)
      -- Convert 0-based to 1-based
      local luaIndex = keyI + 1
      if luaIndex >= 1 and luaIndex <= #parent then
        table.remove(parent, luaIndex)
      end
    end
  end

  return parent
end


-- Build a JSON map from alternating key, value arguments.
local function jm(...)
  local args = { ... }
  local out = {}
  local i = 1
  while i <= #args do
    local k = args[i]
    local v = nil
    if i + 1 <= #args then
      v = args[i + 1]
    end
    -- Keys must be strings
    if type(k) ~= S_string then
      -- Stringify non-string keys
      k = tostring(k)
    end
    out[k] = v
    i = i + 2
  end
  return out
end


-- Build a JSON tuple (list) from arguments.
local function jt(...)
  local args = { ... }
  local out = {}
  setmetatable(out, { __jsontype = "array" })
  for _, v in ipairs(args) do
    table.insert(out, v)
  end
  return out
end


-- Concatenate url part strings, merging forward slashes as needed.
-- @param sarr (table) Array of URL parts to join
-- @return (string) The combined URL
local function joinurl(sarr)
  -- Filter out nil, empty strings, and "null" values and convert non-strings to strings
  local filtered = {}
  for _, p in ipairs(sarr) do
    if p ~= nil and p ~= '' and p ~= 'null' then
      if type(p) == 'string' then
        -- Skip if the string is "null"
        if p ~= "null" then
          table.insert(filtered, p)
        end
      else
        -- Convert non-string values using stringify and skip if result is "null"
        local str = stringify(p)
        if str ~= "null" then
          table.insert(filtered, str)
        end
      end
    end
  end

  -- Process each part to handle slashes correctly
  for i = 1, #filtered do
    local s = filtered[i]


    if i == 1 then
      -- For first element, only remove trailing slashes
      s = s:gsub("/+$", "")
    else
      -- Replace multiple slashes after non-slash with single slash
      s = s:gsub("([^/])/+", "%1/")

      -- For other elements, remove both leading and trailing slashes
      s = s:gsub("^/+", "")
      s = s:gsub("/+$", "")
    end

    filtered[i] = s
  end

  -- Filter out empty strings after processing
  local finalParts = {}
  for _, s in ipairs(filtered) do
    if s ~= '' then
      table.insert(finalParts, s)
    end
  end

  -- Join the parts with single slashes
  return table.concat(finalParts, "/")
end


-- Safely stringify a value for humans (NOT JSON!)
-- Strings are returned as-is (not quoted).
-- @param val (any) The value to stringify
-- @param maxlen (number) Optional maximum length for result
-- @param pretty (boolean) Optional pretty mode with ANSI colors
-- @return (string) String representation of the value
local function stringify(val, maxlen, pretty)
  local valstr = S_MT
  pretty = pretty and true or false

  if val == nil then
    return pretty and '<>' or valstr
  end

  if type(val) == S_string then
    valstr = val
  else
    local function sort_keys(t)
      local keys = {}
      for k in pairs(t) do
        table.insert(keys, k)
      end
      table.sort(keys)
      return keys
    end

    local function serialize(obj, seen)
      seen = seen or {}

      if type(obj) == 'table' and seen[obj] then
        return '...'
      end

      local obj_type = type(obj)

      if obj == nil then
        return 'null'
      elseif obj_type == S_number then
        if obj ~= obj then return 'null' end  -- NaN
        -- Use integer representation for whole numbers
        if obj % 1 == 0 then
          return string.format('%d', obj)
        end
        return tostring(obj)
      elseif obj_type == S_boolean then
        return tostring(obj)
      elseif obj_type == S_function then
        return 'null'
      elseif obj_type ~= 'table' then
        return tostring(obj)
      end

      seen[obj] = true

      local parts = {}
      local is_arr = islist(obj)

      if is_arr then
        for i = 1, #obj do
          table.insert(parts, serialize(obj[i], seen))
        end
      else
        local keys = sort_keys(obj)
        for _, k in ipairs(keys) do
          table.insert(parts, k .. S_CN .. serialize(obj[k], seen))
        end
      end

      seen[obj] = nil

      if is_arr then
        return S_OS .. table.concat(parts, ',') .. S_CS
      else
        return '{' .. table.concat(parts, ',') .. '}'
      end
    end

    local success, result = pcall(function()
      return serialize(val)
    end)

    if success then
      valstr = result
    else
      valstr = '__STRINGIFY_FAILED__'
    end
  end

  -- Handle maxlen
  if maxlen ~= nil and maxlen > -1 then
    if maxlen < #valstr then
      valstr = string.sub(valstr, 1, maxlen - 3) .. '...'
    end
  end

  if pretty then
    local c = { 81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69 }
    local r = '\x1b[0m'
    local d = 0
    local function cc(n) return '\x1b[38;5;' .. n .. 'm' end
    local o = cc(c[1])
    local t = o
    for i = 1, #valstr do
      local ch = valstr:sub(i, i)
      if ch == '{' or ch == S_OS then
        d = d + 1
        o = cc(c[(d % #c) + 1])
        t = t .. o .. ch
      elseif ch == '}' or ch == S_CS then
        t = t .. o .. ch
        d = d - 1
        o = cc(c[(d % #c) + 1])
      else
        t = t .. o .. ch
      end
    end
    return t .. r
  end

  return valstr
end


-- Convert a value to JSON string representation.
local function jsonify(val, flags)
  local str = S_null

  if val ~= nil then
    local ok, result = pcall(function()
      local dkjson = require("dkjson")
      local indent = getprop(flags, 'indent', 2)
      if indent == 0 then
        return dkjson.encode(val)
      end

      -- For indented output, use dkjson's indentation
      local jsonstr = dkjson.encode(val, { indent = true, keyorder = nil })
      if jsonstr == nil then
        return S_null
      end
      return jsonstr
    end)

    if ok and result ~= nil then
      str = result
    else
      str = '__JSONIFY_FAILED__'
    end
  end

  return str
end


-- Build a human friendly path string.
-- @param val (any) The path as array or string
-- @param startin (number) Optional start index
-- @param endin (number) Optional end index
-- @return (string) Formatted path string
local function pathify(val, startin, endin)
  local pathstr = NONE
  local path = NONE

  -- Convert input to path array
  if islist(val) then
    path = val
  elseif type(val) == S_string then
    path = { val }
    setmetatable(path, {
      __jsontype = "array"
    })
  elseif type(val) == S_number then
    path = { val }
    setmetatable(path, {
      __jsontype = "array"
    })
  end

  -- Calculate start and end indices
  local start = startin == nil and 0 or startin >= 0 and startin or 0
  local endidx = endin == nil and 0 or endin >= 0 and endin or 0

  if path ~= NONE and start >= 0 then
    -- Slice path array from start to end
    local sliced = {}
    for i = start + 1, #path - endidx do
      table.insert(sliced, path[i])
    end
    path = sliced

    if #path == 0 then
      pathstr = '<root>'
    else
      -- Filter valid path elements using iskey
      local filtered = {}
      for _, p in ipairs(path) do
        if iskey(p) then
          table.insert(filtered, p)
        end
      end

      -- Map elements to strings with special handling
      local mapped = {}
      for _, p in ipairs(filtered) do
        if type(p) == S_number then
          -- Floor number and convert to string
          table.insert(mapped, S_MT .. tostring(math.floor(p)))
        else
          -- Replace dots with S_MT for strings
          local replacedP = string.gsub(p, "%.", S_MT)
          table.insert(mapped, replacedP)
        end
      end

      -- Join with dots
      pathstr = table.concat(mapped, S_DT)
    end
  end

  -- Handle unknown paths
  if pathstr == NONE then
    pathstr = '<unknown-path'
    if val == NONE then
      pathstr = pathstr .. S_MT
    else
      pathstr = pathstr .. (S_CN .. stringify(val, 47))
    end
    pathstr = pathstr .. '>'
  end

  return pathstr
end


-- Set a value deep inside a node at a key path.
local function setpath(store, path, val, injdef)
  local pathType = typify(path)

  local parts
  if 0 < (T_list & pathType) then
    parts = path
  elseif 0 < (T_string & pathType) then
    parts = {}
    for part in string.gmatch(path, "([^%.]+)") do
      table.insert(parts, part)
    end
  elseif 0 < (T_number & pathType) then
    parts = { path }
    setmetatable(parts, { __jsontype = "array" })
  else
    return NONE
  end

  local base = getprop(injdef, S_base)
  local numparts = size(parts)
  local parent = getprop(store, base, store)

  for pI = 0, numparts - 2 do
    local partKey = getelem(parts, pI)
    local nextParent = getprop(parent, partKey)
    if not isnode(nextParent) then
      local nextKey = getelem(parts, pI + 1)
      if 0 < (T_number & typify(nextKey)) then
        nextParent = {}
        setmetatable(nextParent, { __jsontype = "array" })
      else
        nextParent = {}
      end
      setprop(parent, partKey, nextParent)
    end
    parent = nextParent
  end

  local lastKey = getelem(parts, -1)

  if type(val) == 'table' and val['`$DELETE`'] then
    delprop(parent, lastKey)
  else
    setprop(parent, lastKey, val)
  end

  return parent
end


-- Clone a JSON-like data structure.
-- NOTE: function value references are copied, *not* cloned.
-- @param val (any) The value to clone
-- @param flags (table) Optional flags to control cloning behavior
-- @return (any) Deep copy of the value
local function clone(val, flags)
  -- Handle nil value
  if val == nil then
    return nil
  end

  -- Initialize flags if not provided
  flags = flags or {}
  if flags.func == nil then
    flags.func = true
  end

  -- Handle functions
  if type(val) == "function" then
    if flags.func then
      return val
    end
    return nil
  end

  -- Handle tables (both arrays and objects)
  if type(val) == "table" then
    local refs = {} -- To store function references
    local new_table = {}

    -- Get the original metatable if any
    local mt = getmetatable(val)

    -- Clone table contents
    for k, v in pairs(val) do
      -- Handle function values specially
      if type(v) == "function" then
        if flags.func then
          refs[#refs + 1] = v
          new_table[k] = ("$FUNCTION:" .. #refs)
        end
      else
        new_table[k] = clone(v, flags)
      end
    end

    -- If we have function references, we need to restore them
    if #refs > 0 then
      -- Replace function placeholders with actual functions
      for k, v in pairs(new_table) do
        if type(v) == "string" then
          local func_idx = v:match("^%$FUNCTION:(%d+)$")
          if func_idx then
            new_table[k] = refs[tonumber(func_idx)]
          end
        end
      end
    end

    -- Restore the original metatable if it existed
    if mt then
      setmetatable(new_table, mt)
    end

    return new_table
  end

  -- For all other types (numbers, strings, booleans), return as is
  return val
end


-- Safely set a property. Undefined arguments and invalid keys are ignored.
-- Returns the (possibly modified) parent.
-- If the parent is a list, and the key is negative, prepend the value.
-- NOTE: If the key is above the list size, append the value; below, prepend.
-- @param parent (table) The parent object or array
-- @param key (any) The key to set
-- @param val (any) The value to set
-- @return (table) The modified parent
local function setprop(parent, key, val)
  if not iskey(key) then
    return parent
  end

  if ismap(parent) then
    key = tostring(key)
    parent[key] = val
  elseif islist(parent) then
    -- Ensure key is an integer
    local keyI = tonumber(key)

    if keyI == nil then
      return parent
    end

    keyI = math.floor(keyI)

    -- Set or append value at position keyI
    if keyI >= 0 then
      -- Convert from 0-based indexing to Lua 1-based indexing
      local luaIndex = keyI + 1

      -- Clamp: if index is beyond current length, append to end
      if luaIndex > #parent + 1 then
        luaIndex = #parent + 1
      end
      parent[luaIndex] = val
    -- Prepend value if keyI is negative
    else
      table.insert(parent, 1, val)
    end
  end

  return parent
end


-- Walk a data structure depth first, applying a function to each value.
-- @param val (any) The value to walk
-- @param before (function) Applied before descending into a node
-- @param after (function) Applied after descending into a node
-- @param maxdepth (number) Maximum recursive depth (default MAXDEPTH)
-- @param key (any) Current key (for recursive calls)
-- @param parent (table) Current parent (for recursive calls)
-- @param path (table) Current path (for recursive calls)
-- @return (any) The transformed value
local function walk(val, before, after, maxdepth,
                    key, parent, path)
  if NONE == path then
    path = {}
    setmetatable(path, { __jsontype = "array" })
  end

  local out = (nil == before) and val or before(key, val, parent, path)

  maxdepth = (maxdepth ~= nil and maxdepth >= 0) and maxdepth or MAXDEPTH
  if 0 == maxdepth or (path ~= nil and 0 < maxdepth and maxdepth <= #path) then
    return out
  end

  if isnode(out) then
    for _, item in ipairs(items(out)) do
      local ckey, child = item[1], item[2]

      local childPath = flatten({ getdef(path, {}), S_MT .. tostring(ckey) })
      setmetatable(childPath, { __jsontype = "array" })

      setprop(out, ckey, walk(child, before, after, maxdepth, ckey, out, childPath))
    end
  end

  out = (nil == after) and out or after(key, out, parent, path)

  return out
end


-- Merge a list of values into each other. Later values have
-- precedence. Nodes override scalars. Node kinds (list or map)
-- override each other, and do *not* merge. The first element is
-- modified.
-- @param val (any) Array of values to merge
-- @param maxdepth (number) Optional maximum depth for merge
-- @return (any) The merged result
local function merge(val, maxdepth)
  local md = slice(getdef(maxdepth, MAXDEPTH), 0)
  local out = NONE

  -- Handle edge cases
  if not islist(val) then
    return val
  end

  local list = val
  local lenlist = #list

  if lenlist == 0 then
    return NONE
  elseif lenlist == 1 then
    return list[1]
  end

  out = getprop(list, 0, {})

  for oI = 2, lenlist do
    local obj = list[oI]

    if not isnode(obj) then
      -- Nodes win
      out = obj
    else
      -- Current value at path end in overriding node.
      local cur = { out }

      -- Current value at path end in destination node.
      local dst = { out }

      local function before(key, bval, _parent, path)
        local pI = size(path)

        if md <= pI then
          setprop(cur[pI], key, bval)

        -- Scalars just override directly.
        elseif not isnode(bval) then
          cur[pI + 1] = bval

        -- Descend into override node.
        else
          -- Descend into destination node using same key.
          dst[pI + 1] = 0 < pI and getprop(dst[pI], key) or dst[pI + 1]
          local tval = dst[pI + 1]

          -- Destination empty, so create node (unless override is class instance).
          if NONE == tval and 0 == (T_instance & typify(bval)) then
            cur[pI + 1] = islist(bval) and
              setmetatable({}, { __jsontype = "array" }) or {}

          -- Matching override and destination so continue with their values.
          elseif typify(bval) == typify(tval) then
            cur[pI + 1] = tval

          -- Override wins.
          else
            cur[pI + 1] = bval
            -- No need to descend when override wins.
            bval = NONE
          end
        end

        return bval
      end

      local function after(key, _aval, _parent, path)
        local cI = size(path)
        local target = cur[cI]
        local value = cur[cI + 1]

        setprop(target, key, value)
        return value
      end

      -- Walk overriding node, creating paths in output as needed.
      out = walk(obj, before, after, maxdepth)
    end
  end

  if 0 == md then
    out = getelem(list, -1)
    out = islist(out) and setmetatable({}, { __jsontype = "array" })
      or ismap(out) and {} or out
  end

  return out
end


-- Get a value deep inside a node using a key path.
-- @param store (table) The data store to search in
-- @param path (string|table|number) The path to the value
-- @param injdef (table) Optional injection definition
-- @return (any) The value at the path
getpath = function(store, path, injdef)
  -- Operate on a string array.
  local parts
  if islist(path) then
    parts = path
  elseif type(path) == S_string then
    parts = {}
    for part in string.gmatch(path, "([^%.]*)(%.?)") do
      table.insert(parts, part)
    end
    -- Remove trailing empty from the split
    if #parts > 0 and parts[#parts] == S_MT then
      table.remove(parts, #parts)
    end
    if path == S_MT then
      parts = { S_MT }
    end
  elseif type(path) == S_number then
    parts = { strkey(path) }
  else
    return NONE
  end

  local val = store
  local base = getprop(injdef, S_base)
  local src = getprop(store, base, store)
  local numparts = #parts
  local dparent = getprop(injdef, 'dparent')

  -- An empty path (incl empty string) just finds the store.
  if path == nil or store == nil or (1 == numparts and S_MT == parts[1]) then
    val = src
  elseif 0 < numparts then

    -- Check for $ACTIONs
    if 1 == numparts then
      val = getprop(store, parts[1])
    end

    if not isfunc(val) then
      val = src

      -- Check for $META path prefix (e.g., "$meta.path")
      local meta_match = parts[1]:match("^(%$)([A-Z]+)(.*)")
      if meta_match and injdef and injdef.meta then
        -- TODO: $META path prefix handling
      end

      local dpath = getprop(injdef, 'dpath')

      local pI = 0
      while NONE ~= val and pI < numparts do
        local part = parts[pI + 1]  -- Lua 1-based

        if injdef and S_DKEY == part then
          part = getprop(injdef, S_key)
        elseif injdef and part and #part > 5 and part:sub(1, 5) == '$GET:' then
          -- $GET:path -> get store value, use as path part
          part = stringify(getpath(src, part:sub(6, -1)))
        elseif injdef and part and #part > 5 and part:sub(1, 5) == '$REF:' then
          -- $REF:refpath -> get spec value, use as path part
          part = stringify(getpath(getprop(store, S_DSPEC), part:sub(6, -1)))
        elseif injdef and part and #part > 6 and part:sub(1, 6) == '$META:' then
          -- $META:metapath -> get meta value, use as path part
          part = stringify(getpath(getprop(injdef, 'meta'), part:sub(7, -1)))
        end

        -- $$ escapes $
        if part and type(part) == S_string then
          part = part:gsub('%$%$', '$')
        end

        if S_MT == part then
          local ascends = 0
          while pI + 1 < numparts and S_MT == parts[pI + 2] do
            ascends = ascends + 1
            pI = pI + 1
          end

          if injdef and 0 < ascends then
            if pI == numparts - 1 then
              ascends = ascends - 1
            end

            if 0 == ascends then
              val = dparent
            else
              local remaining = {}
              for ri = pI + 2, numparts do
                table.insert(remaining, parts[ri])
              end
              local fullpath = flatten({ slice(dpath, 0 - ascends), remaining })

              if ascends <= size(dpath) then
                val = getpath(store, fullpath)
              else
                val = NONE
              end
              break
            end
          else
            val = dparent
          end
        else
          val = getprop(val, part)
        end

        pI = pI + 1
      end
    end
  end

  -- Injdef may provide a custom handler to modify found value.
  local handler = getprop(injdef, 'handler')
  if nil ~= injdef and isfunc(handler) then
    local ref = pathify(path)
    val = handler(injdef, val, ref, store)
  end

  return val
end


-- Injection "class" for managing injection state.
-- Methods: descend, child, setval

local Injection = {}
Injection.__index = Injection

function Injection:new(val, parent)
  local o = {
    mode = S_MVAL,
    full = false,
    keyI = 0,
    keys = { S_DTOP },
    key = S_DTOP,
    val = val,
    parent = parent,
    path = { S_DTOP },
    nodes = { parent },
    handler = _injecthandler,
    errs = {},
    meta = {},
    dparent = NONE,
    dpath = { S_DTOP },
    base = S_DTOP,
    modify = NONE,
    prior = NONE,
    extra = NONE,
  }
  setmetatable(o, self)
  return o
end


function Injection:descend()
  if self.meta.__d == nil then self.meta.__d = 0 end
  self.meta.__d = self.meta.__d + 1

  local parentkey = getelem(self.path, -2)

  if NONE == self.dparent then
    if 1 < size(self.dpath) then
      self.dpath = flatten({ self.dpath, parentkey })
    end
  else
    if parentkey ~= nil then
      self.dparent = getprop(self.dparent, parentkey)

      local lastpart = getelem(self.dpath, -1)
      if lastpart == '$:' .. tostring(parentkey) then
        self.dpath = slice(self.dpath, -1)
      else
        self.dpath = flatten({ self.dpath, parentkey })
      end
    end
  end

  return self.dparent
end


function Injection:child(keyI, keys)
  local key = strkey(keys[keyI + 1])  -- Lua 1-based
  local val = self.val

  local cinj = Injection:new(getprop(val, key), val)
  cinj.keyI = keyI
  cinj.keys = keys
  cinj.key = key

  cinj.path = flatten({ getdef(self.path, {}), key })
  cinj.nodes = flatten({ getdef(self.nodes, {}), { val } })

  cinj.mode = self.mode
  cinj.handler = self.handler
  cinj.modify = self.modify
  cinj.base = self.base
  cinj.meta = self.meta
  cinj.errs = self.errs
  cinj.prior = self

  cinj.dpath = flatten({ self.dpath })
  cinj.dparent = self.dparent

  return cinj
end


function Injection:setval(val, ancestor)
  if ancestor == nil or ancestor < 2 then
    if NONE == val then
      delprop(self.parent, self.key)
    else
      setprop(self.parent, self.key, val)
    end
  else
    local aval = getelem(self.nodes, 0 - ancestor)
    local akey = getelem(self.path, 0 - ancestor)
    if NONE == val then
      delprop(aval, akey)
    else
      setprop(aval, akey, val)
    end
  end
  return self.parent
end


-- Inject values from a data store into a node recursively.
-- @param val (any) The value to inject into
-- @param store (table) The data store
-- @param injdef (table) Optional injection definition
-- @return (any) The injected result
local function inject(val, store, injdef)
  local valtype = type(val)
  local inj = injdef

  -- Create state if at root of injection.
  if NONE == injdef or (injdef and injdef.mode == nil) then
    local parent = { [S_DTOP] = val }
    inj = Injection:new(val, parent)
    inj.dparent = store
    inj.errs = getprop(store, S_DERRS, {})
    inj.meta.__d = 0

    if NONE ~= injdef then
      inj.modify = injdef.modify ~= nil and injdef.modify or inj.modify
      inj.extra = injdef.extra ~= nil and injdef.extra or inj.extra
      inj.meta = injdef.meta ~= nil and injdef.meta or inj.meta
      inj.handler = injdef.handler ~= nil and injdef.handler or inj.handler
    end
  end

  inj:descend()

  -- Descend into node.
  if isnode(val) then
    local nodekeys

    if ismap(val) then
      local regular_keys = {}
      local ds_keys = {}
      for k, _ in pairs(val) do
        if type(k) == S_string and k:find(S_DS) then
          table.insert(ds_keys, k)
        else
          table.insert(regular_keys, k)
        end
      end
      table.sort(regular_keys)
      table.sort(ds_keys)
      nodekeys = flatten({ regular_keys, ds_keys })
    else
      nodekeys = {}
      for i = 1, #val do
        table.insert(nodekeys, i - 1)  -- 0-based indices
      end
    end

    local nkI = 0
    while nkI < #nodekeys do
      local childinj = inj:child(nkI, nodekeys)
      local nodekey = childinj.key
      childinj.mode = S_MKEYPRE

      -- Perform key:pre mode injection
      local prekey = _injectstr(nodekey, store, childinj)

      -- The injection may modify child processing.
      nkI = childinj.keyI
      nodekeys = childinj.keys

      -- Prevent further processing by returning undefined prekey
      if prekey ~= NONE then
        childinj.val = getprop(val, prekey)
        childinj.mode = S_MVAL

        -- Perform val mode injection
        inject(childinj.val, store, childinj)

        -- The injection may modify child processing.
        nkI = childinj.keyI
        nodekeys = childinj.keys

        -- Perform key:post mode injection
        childinj.mode = S_MKEYPOST
        _injectstr(nodekey, store, childinj)

        nkI = childinj.keyI
        nodekeys = childinj.keys
      end

      nkI = nkI + 1
    end

  elseif S_string == valtype then
    inj.mode = S_MVAL
    val = _injectstr(val, store, inj)
    if SKIP ~= val then
      inj:setval(val)
    end
  end

  -- Custom modification
  if inj.modify and SKIP ~= val then
    local mkey = inj.key
    local mparent = inj.parent
    local mval = getprop(mparent, mkey)
    inj.modify(mval, mkey, mparent, inj, store)
  end

  inj.val = val

  return getprop(inj.parent, S_DTOP)
end


-- Delete a key from a map or list.
local function transform_DELETE(inj)
  inj:setval(NONE)
  return NONE
end


-- Copy value from source data.
local function transform_COPY(inj, _val)
  if S_MVAL ~= inj.mode then
    return NONE
  end

  local out = getprop(inj.dparent, inj.key)
  inj:setval(out)
  return out
end


-- As a value, inject the key of the parent node.
local function transform_KEY(inj)
  local mode, path, parent = inj.mode, inj.path, inj.parent

  if S_MVAL ~= mode then
    return NONE
  end

  -- Key is defined by $KEY meta property.
  local keyspec = getprop(parent, S_BKEY)
  if keyspec ~= NONE then
    delprop(parent, S_BKEY)
    return getprop(inj.dparent, keyspec)
  end

  return getprop(getprop(parent, S_BANNO), S_KEY, getelem(path, -2))
end


-- Store annotation data about a node.
local function transform_ANNO(inj)
  delprop(inj.parent, S_BANNO)
  return NONE
end


-- Merge a list of objects into the current object.
local function transform_MERGE(inj)
  local mode, key, parent = inj.mode, inj.key, inj.parent

  local out = NONE

  if S_MKEYPRE == mode then
    out = key

  elseif S_MKEYPOST == mode then
    out = key

    local args = getprop(parent, key)
    if not islist(args) then
      args = { args }
      setmetatable(args, { __jsontype = "array" })
    end

    -- Remove the $MERGE command from parent.
    inj:setval(NONE)

    local mergelist = flatten({ { parent }, args, { clone(parent) } })
    setmetatable(mergelist, { __jsontype = "array" })
    merge(mergelist)
  end

  return out
end


-- Helper: injectChild
local function injectChild(child, store, inj)
  local cinj = inj

  if nil ~= inj.prior then
    if nil ~= inj.prior.prior then
      cinj = inj.prior.prior:child(inj.prior.keyI, inj.prior.keys)
      cinj.val = child
      setprop(cinj.parent, inj.prior.key, child)
    else
      cinj = inj.prior:child(inj.keyI, inj.keys)
      cinj.val = child
      setprop(cinj.parent, inj.key, child)
    end
  end

  inject(child, store, cinj)
  return cinj
end


-- Convert a node to a list.
-- Format: ['`$EACH`', '`source-path-of-node`', child-template]
local function transform_EACH(inj, _val, _ref, store)
  if S_MVAL ~= inj.mode then
    return NONE
  end

  -- Remove remaining keys to avoid spurious processing.
  local trimmed = slice(inj.keys, 0, 1)
  -- Replace keys in-place
  for i = #inj.keys, 1, -1 do inj.keys[i] = nil end
  for i, v in ipairs(trimmed) do inj.keys[i] = v end

  -- Get arguments: ['`$EACH`', 'source-path', child-template]
  local srcpath = getprop(inj.parent, 1)
  local child = clone(getprop(inj.parent, 2))

  -- Source data.
  local srcstore = getprop(store, inj.base, store)
  local src = getpath(srcstore, srcpath, inj)
  local srctype = typify(src)

  local tcur = {}
  local tval = {}
  setmetatable(tval, { __jsontype = "array" })

  local tkey = getelem(inj.path, -2)
  local target = getelem(inj.nodes, -2, function() return getelem(inj.nodes, -1) end)

  -- Create clones of the child template for each value of the source.
  if 0 < (T_list & srctype) then
    for _, item in ipairs(items(src)) do
      table.insert(tval, clone(child))
    end
  elseif 0 < (T_map & srctype) then
    for _, item in ipairs(items(src)) do
      local merged = merge({ clone(child), { [S_BANNO] = { KEY = item[1] } } }, 1)
      table.insert(tval, merged)
    end
  end

  local rval = {}
  setmetatable(rval, { __jsontype = "array" })

  if 0 < size(tval) then
    -- Get source values
    local srcvals = {}
    setmetatable(srcvals, { __jsontype = "array" })
    if islist(src) then
      for i = 1, #src do table.insert(srcvals, src[i]) end
    elseif ismap(src) then
      for _, item in ipairs(items(src)) do
        table.insert(srcvals, item[2])
      end
    end

    local ckey = getelem(inj.path, -2)
    local tpath = slice(inj.path, -1)

    -- Split srcpath into parts
    local srcparts = {}
    if type(srcpath) == S_string then
      for p in srcpath:gmatch("([^%.]+)") do
        table.insert(srcparts, p)
      end
    end
    local dpath = flatten({ S_DTOP, srcparts, '$:' .. tostring(ckey) })

    tcur = { [ckey] = srcvals }

    if 1 < size(tpath) then
      local pkey = getelem(inj.path, -3, S_DTOP)
      tcur = { [pkey] = tcur }
      table.insert(dpath, '$:' .. tostring(pkey))
    end

    local tinj = inj:child(0, { ckey })
    tinj.path = tpath
    tinj.nodes = slice(inj.nodes, -1)
    tinj.parent = getelem(tinj.nodes, -1)
    setprop(tinj.parent, ckey, tval)
    tinj.val = tval
    tinj.dpath = dpath
    tinj.dparent = tcur

    inject(tval, store, tinj)
    rval = tinj.val
  end

  setprop(target, tkey, rval)

  -- Prevent callee from damaging first list entry.
  return getelem(rval, 0)
end


-- Convert a node to a map.
-- Format: { '`$PACK`':['`source-path`', child-template]}
local function transform_PACK(inj, _val, _ref, store)
  local mode, key, path, parent, nodes = inj.mode, inj.key, inj.path,
      inj.parent, inj.nodes

  if S_MKEYPRE ~= mode then
    return NONE
  end

  -- Get arguments.
  local args = getprop(parent, key)
  local srcpath = getprop(args, 0)
  local origchildspec = getprop(args, 1)

  -- Find key and target node.
  local tkey = getelem(path, -2)
  local pathsize = size(path)
  local target = getelem(nodes, pathsize - 2, function()
    return getelem(nodes, pathsize - 1)
  end)

  -- Source data
  local srcstore = getprop(store, inj.base, store)
  local src = getpath(srcstore, srcpath, inj)

  -- Prepare source as a list.
  if not islist(src) then
    if ismap(src) then
      local newsrc = {}
      setmetatable(newsrc, { __jsontype = "array" })
      for _, item in ipairs(items(src)) do
        setprop(item[2], S_BANNO, { KEY = item[1] })
        table.insert(newsrc, item[2])
      end
      src = newsrc
    else
      src = NONE
    end
  end

  if src == nil then
    return NONE
  end

  -- Get keypath.
  local keypath = getprop(origchildspec, S_BKEY)
  delprop(origchildspec, S_BKEY)

  local child = getprop(origchildspec, S_BVAL, origchildspec)

  -- Build parallel target object.
  local tval = {}

  for _, item in ipairs(items(src)) do
    local srckey = item[1]
    local srcnode = item[2]

    local kn = srckey
    if NONE ~= keypath then
      if type(keypath) == S_string and keypath:sub(1, 1) == S_BT then
        kn = inject(keypath, merge({ {}, store, { [S_DTOP] = srcnode } }, 1))
      else
        kn = getpath(srcnode, keypath, inj)
      end
    end

    local tchild = clone(child)
    setprop(tval, kn, tchild)

    local anno = getprop(srcnode, S_BANNO)
    if NONE == anno then
      delprop(tchild, S_BANNO)
    else
      setprop(tchild, S_BANNO, anno)
    end
  end

  local rval = {}

  if not isempty(tval) then
    -- Build parallel source object.
    local tsrc = {}
    for srcI, item in ipairs(items(src)) do
      local srcnode = item[2]
      local kn
      if keypath == nil then
        kn = srcI - 1  -- 0-based
      elseif type(keypath) == S_string and keypath:sub(1, 1) == S_BT then
        kn = inject(keypath, merge({ {}, store, { [S_DTOP] = srcnode } }, 1))
      else
        kn = getpath(srcnode, keypath, inj)
      end
      setprop(tsrc, kn, srcnode)
    end

    local tpath = slice(inj.path, -1)
    local ckey = getelem(inj.path, -2)

    local srcparts = {}
    if type(srcpath) == S_string then
      for p in srcpath:gmatch("([^%.]+)") do
        table.insert(srcparts, p)
      end
    end
    local dpath = flatten({ S_DTOP, srcparts, '$:' .. tostring(ckey) })

    local tcur = { [ckey] = tsrc }

    if 1 < size(tpath) then
      local pkey = getelem(inj.path, -3, S_DTOP)
      tcur = { [pkey] = tcur }
      table.insert(dpath, '$:' .. tostring(pkey))
    end

    local tinj = inj:child(0, { ckey })
    tinj.path = tpath
    tinj.nodes = slice(inj.nodes, -1)
    tinj.parent = getelem(tinj.nodes, -1)
    tinj.val = tval
    tinj.dpath = dpath
    tinj.dparent = tcur

    inject(tval, store, tinj)
    rval = tinj.val
  end

  setprop(target, tkey, rval)

  -- Drop transform key.
  return NONE
end


-- Apply a function to a value.
-- Format: ['`$APPLY`', function, child]
local function transform_APPLY(inj, _val, _ref, store)
  if S_MVAL ~= inj.mode then
    return NONE
  end

  local apply = getprop(inj.parent, 1)
  local child = getprop(inj.parent, 2)

  if not isfunc(apply) then
    return NONE
  end

  local tkey = getelem(inj.path, -2)
  local target = getelem(inj.nodes, -2, function() return getelem(inj.nodes, -1) end)

  local cinj = injectChild(child, store, inj)
  local resolved = cinj.val

  local out = apply(resolved, store, cinj)

  setprop(target, tkey, out)
  return out
end


-- Transform data using spec.
-- @param data (any) Source data to transform
-- @param spec (any) Transform specification
-- @param injdef (table) Optional injection definition with modify, extra, errs
-- @return (any) The transformed data
local function transform(data, spec, injdef)
  local origspec = spec
  spec = clone(origspec)

  local extra = injdef and injdef.extra or NONE
  local collect = injdef ~= nil and injdef.errs ~= nil
  local errs = (injdef and injdef.errs) or {}

  local extraTransforms = {}
  local extraData = NONE

  if extra ~= nil then
    extraData = {}
    for _, item in ipairs(items(extra)) do
      local k, v = item[1], item[2]
      if type(k) == S_string and k:sub(1, 1) == S_DS then
        extraTransforms[k] = v
      else
        extraData[k] = v
      end
    end
  end

  local dataClone = merge({
    isempty(extraData) and NONE or clone(extraData),
    clone(data),
  })

  -- Define a top level store that provides transform operations.
  local store = merge({
    {
      [S_DTOP] = dataClone,

      [S_DSPEC] = function() return origspec end,

      ['$BT'] = function() return S_BT end,
      ['$DS'] = function() return S_DS end,
      ['$WHEN'] = function() return os.date('!%Y-%m-%dT%H:%M:%S.000Z') end,

      ['$DELETE'] = transform_DELETE,
      ['$COPY'] = transform_COPY,
      ['$KEY'] = transform_KEY,
      ['$ANNO'] = transform_ANNO,
      ['$MERGE'] = transform_MERGE,
      ['$EACH'] = transform_EACH,
      ['$PACK'] = transform_PACK,
      ['$APPLY'] = transform_APPLY,
    },
    extraTransforms,
    { ['$ERRS'] = errs },
  }, 1)

  local out = inject(spec, store, injdef)

  local generr = 0 < size(errs) and not collect
  if generr then
    error(table.concat(errs, ' | '))
  end

  return out
end


-- A required string value. NOTE: Rejects empty strings.
local function validate_STRING(inj)
  local out = getprop(inj.dparent, inj.key)

  local t = typify(out)
  if 0 == (T_string & t) then
    local msg = _invalidTypeMsg(inj.path, S_string, t, out, 'V1010')
    table.insert(inj.errs, msg)
    return NONE
  end

  if S_MT == out then
    local msg = 'Empty string at ' .. pathify(inj.path, 1)
    table.insert(inj.errs, msg)
    return NONE
  end

  return out
end


-- A generic type validator. Ref is used to determine which type to check.
local function validate_TYPE(inj, _val, ref)
  local tname = slice(ref, 1):lower()

  -- Find type index in TYPENAME
  local typev = 0
  for i, tn in ipairs(TYPENAME) do
    if tn == tname then
      typev = 1 << (32 - i)
      break
    end
  end

  local out = getprop(inj.dparent, inj.key)

  local t = typify(out)
  if 0 == (t & typev) then
    table.insert(inj.errs, _invalidTypeMsg(inj.path, tname, t, out, 'V1001'))
    return NONE
  end

  return out
end


-- Allow any value.
local function validate_ANY(inj)
  local out = getprop(inj.dparent, inj.key)
  return out
end


-- Specify child values for map or list.
-- Map syntax: {'`$CHILD`': child-template }
-- List syntax: ['`$CHILD`', child-template ]
local function validate_CHILD(inj)
  local mode, key, parent, keys, path = inj.mode, inj.key, inj.parent,
      inj.keys, inj.path

  -- Map syntax.
  if S_MKEYPRE == mode then
    local childtm = getprop(parent, key)

    -- Get corresponding current object.
    local pkey = getelem(path, -2)
    local tval = getprop(inj.dparent, pkey)

    if NONE == tval then
      tval = {}
    elseif not ismap(tval) then
      table.insert(inj.errs, _invalidTypeMsg(
        slice(inj.path, 0, -1), S_object, typify(tval), tval, 'V0220'))
      return NONE
    end

    local ckeys = keysof(tval)
    for _, ckey in ipairs(ckeys) do
      setprop(parent, ckey, clone(childtm))

      -- NOTE: modifying inj! This extends the child value loop in inject.
      table.insert(keys, ckey)
    end

    -- Remove $CHILD to cleanup output.
    inj:setval(NONE)
    return NONE
  end

  -- List syntax.
  if S_MVAL == mode then
    if not islist(parent) then
      -- $CHILD was not inside a list.
      table.insert(inj.errs, 'Invalid $CHILD as value')
      return NONE
    end

    local childtm = getprop(parent, 1)

    if NONE == inj.dparent then
      -- Empty list as default.
      slice(parent, 0, 0, true)
      return NONE
    end

    if not islist(inj.dparent) then
      local msg = _invalidTypeMsg(
        slice(inj.path, 0, -1), S_list, typify(inj.dparent), inj.dparent, 'V0230')
      table.insert(inj.errs, msg)
      inj.keyI = size(parent)
      return inj.dparent
    end

    -- Clone children and reset inj key index.
    for i = 1, #inj.dparent do
      parent[i] = clone(childtm)
    end
    slice(parent, 0, #inj.dparent, true)
    inj.keyI = 0

    local out = getprop(inj.dparent, 0)
    return out
  end

  return NONE
end


----------------------------------------------------------
-- Forward declaration for validate to resolve lack of function hoisting
----------------------------------------------------------
local validate


-- Match at least one of the specified shapes.
-- Syntax: ['`$ONE`', alt0, alt1, ...]
local function validate_ONE(inj, _val, _ref, store)
  local mode, parent, keyI = inj.mode, inj.parent, inj.keyI

  -- Only operate in val mode, since parent is a list.
  if S_MVAL == mode then
    if not islist(parent) or 0 ~= keyI then
      table.insert(inj.errs,
        'The $ONE validator at field ' .. pathify(inj.path, 1, 1) ..
        ' must be the first element of an array.')
      return
    end

    inj.keyI = size(inj.keys)

    -- Clean up structure, replacing [$ONE, ...] with current
    inj:setval(inj.dparent, 2)

    inj.path = slice(inj.path, 0, -1)
    inj.key = getelem(inj.path, -1)

    local tvals = slice(parent, 1)
    if 0 == size(tvals) then
      table.insert(inj.errs,
        'The $ONE validator at field ' .. pathify(inj.path, 1, 1) ..
        ' must have at least one argument.')
      return
    end

    -- See if we can find a match.
    for _, tval in ipairs(tvals) do
      local terrs = {}
      setmetatable(terrs, { __jsontype = "array" })

      local vstore = merge({ {}, store }, 1)
      vstore["$TOP"] = inj.dparent

      local vcurrent = validate(inj.dparent, tval, {
        extra = vstore,
        errs = terrs,
        meta = inj.meta,
      })

      inj:setval(vcurrent, -2)

      -- Accept current value if there was a match
      if 0 == size(terrs) then
        return
      end
    end

    -- There was no match.
    local valdesc = {}
    for _, v in ipairs(tvals) do
      table.insert(valdesc, stringify(v))
    end
    local valdesc_str = table.concat(valdesc, ', ')
    valdesc_str = valdesc_str:gsub('`%$([A-Z]+)`', function(p1)
      return string.lower(p1)
    end)

    table.insert(inj.errs,
      _invalidTypeMsg(inj.path,
        (1 < size(tvals) and 'one of ' or '') .. valdesc_str, typify(inj.dparent),
        inj.dparent, 'V0210'))
  end
end


-- Match exactly one of the specified values.
-- Syntax: ['`$EXACT`', val1, val2, ...]
local function validate_EXACT(inj)
  local mode, parent, key, keyI = inj.mode, inj.parent, inj.key, inj.keyI

  -- Only operate in val mode, since parent is a list.
  if S_MVAL == mode then
    if not islist(parent) or 0 ~= keyI then
      table.insert(inj.errs, 'The $EXACT validator at field ' ..
        pathify(inj.path, 1, 1) ..
        ' must be the first element of an array.')
      return
    end

    inj.keyI = size(inj.keys)

    -- Clean up structure, replacing [$EXACT, ...] with current data parent
    inj:setval(inj.dparent, 2)

    inj.path = slice(inj.path, 0, -1)
    inj.key = getelem(inj.path, -1)

    local tvals = slice(parent, 1)
    if 0 == size(tvals) then
      table.insert(inj.errs, 'The $EXACT validator at field ' ..
        pathify(inj.path, 1, 1) ..
        ' must have at least one argument.')
      return
    end

    -- See if we can find an exact value match.
    local currentstr = nil
    for _, tval in ipairs(tvals) do
      local exactmatch = tval == inj.dparent

      if not exactmatch and isnode(tval) then
        if currentstr == nil then
          currentstr = stringify(inj.dparent)
        end
        local tvalstr = stringify(tval)
        exactmatch = tvalstr == currentstr
      end

      if exactmatch then
        return
      end
    end

    local valdesc = {}
    for _, v in ipairs(tvals) do
      table.insert(valdesc, stringify(v))
    end
    local valdesc_str = table.concat(valdesc, ', ')

    table.insert(inj.errs, _invalidTypeMsg(
      inj.path,
      (1 < size(inj.path) and '' or 'value ') ..
      'exactly equal to ' .. (1 == size(tvals) and '' or 'one of ') .. valdesc_str,
      typify(inj.dparent), inj.dparent, 'V0110'))
  else
    delprop(parent, key)
  end
end


-- This is the "modify" argument to inject. Use this to perform
-- generic validation. Runs *after* any special commands.
_validation = function(pval, key, parent, inj)
  if NONE == inj then
    return
  end

  if SKIP == pval then
    return
  end

  -- select needs exact matches
  local exact = getprop(inj.meta, S_BEXACT, false)

  -- Current val to verify.
  local cval = getprop(inj.dparent, key)

  if NONE == inj or (not exact and NONE == cval) then
    return
  end

  local ptype = typify(pval)

  -- Delete any special commands remaining.
  if 0 < (T_string & ptype) and string.find(pval, S_DS, 1, true) then
    return
  end

  local ctype = typify(cval)

  -- Type mismatch.
  if ptype ~= ctype and NONE ~= pval then
    table.insert(inj.errs, _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0010'))
    return
  end

  if ismap(cval) then
    if not ismap(pval) then
      table.insert(inj.errs, _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0020'))
      return
    end

    local ckeys = keysof(cval)
    local pkeys = keysof(pval)

    -- Empty spec object {} means object can be open (any keys).
    if 0 < size(pkeys) and true ~= getprop(pval, '`$OPEN`') then
      local badkeys = {}

      for _, ckey in ipairs(ckeys) do
        if not haskey(pval, ckey) then
          table.insert(badkeys, ckey)
        end
      end

      -- Closed object, so reject extra keys not in shape.
      if 0 < size(badkeys) then
        local msg =
          'Unexpected keys at field ' .. pathify(inj.path, 1) .. S_VIZ .. table.concat(badkeys, ', ')
        table.insert(inj.errs, msg)
      end
    else
      -- Object is open, so merge in extra keys.
      merge({ pval, cval })
      if isnode(pval) then
        delprop(pval, '`$OPEN`')
      end
    end
  elseif islist(cval) then
    if not islist(pval) then
      table.insert(inj.errs, _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0030'))
    end
  elseif exact then
    if cval ~= pval then
      local pathmsg = 1 < size(inj.path)
        and ('at field ' .. pathify(inj.path, 1) .. S_VIZ) or S_MT
      table.insert(inj.errs, 'Value ' .. pathmsg .. tostring(cval) ..
        ' should equal ' .. tostring(pval) .. '.')
    end
  else
    -- Spec value was a default, copy over data
    setprop(parent, key, cval)
  end
end


-- Validate a data structure against a shape specification.  The shape
-- specification follows the "by example" principle.  Plain data in
-- the shape is treated as default values that also specify the
-- required type.  Thus shape {a=1} validates {a=2}, since the types
-- (number) match, but not {a='A'}.  Shape {a=1} against data {}
-- returns {a=1} as a=1 is the default value of the a key.  Special
-- validation commands (in the same syntax as transform) are also
-- provided to specify required values.  Thus shape {a='`$STRING`'}
-- validates {a='A'} but not {a=1}. Empty map or list means the node
-- is open, and if missing an empty default is inserted.
-- @param data (any) Source data to validate
-- @param spec (any) Validation specification
-- @param extra (any) Additional custom checks
-- @param collecterrs (table) Optional array to collect error messages
-- @return (any) The validated data
validate = function(data, spec, injdef)
  local extra = injdef and injdef.extra or nil

  local collect = injdef ~= nil and injdef.errs ~= nil
  local errs = (injdef and injdef.errs) or {}
  setmetatable(errs, { __jsontype = "array" })

  local store = merge({
    {
      -- Remove the transform commands.
      ["$DELETE"] = false,
      ["$COPY"] = false,
      ["$KEY"] = false,
      ["$META"] = false,
      ["$MERGE"] = false,
      ["$EACH"] = false,
      ["$PACK"] = false,

      -- Validation functions
      ["$STRING"] = validate_STRING,
      ["$NUMBER"] = validate_TYPE,
      ["$INTEGER"] = validate_TYPE,
      ["$DECIMAL"] = validate_TYPE,
      ["$BOOLEAN"] = validate_TYPE,
      ["$NULL"] = validate_TYPE,
      ["$NIL"] = validate_TYPE,
      ["$MAP"] = validate_TYPE,
      ["$LIST"] = validate_TYPE,
      ["$FUNCTION"] = validate_TYPE,
      ["$INSTANCE"] = validate_TYPE,
      ["$ANY"] = validate_ANY,
      ["$CHILD"] = validate_CHILD,
      ["$ONE"] = validate_ONE,
      ["$EXACT"] = validate_EXACT,
    },

    getdef(extra, {}),

    -- A special top level value to collect errors.
    {
      ["$ERRS"] = errs,
    }
  }, 1)

  local meta = (injdef and injdef.meta) or {}
  setprop(meta, S_BEXACT, getprop(meta, S_BEXACT, false))

  local out = transform(data, spec, {
    meta = meta,
    extra = store,
    modify = _validation,
    handler = _validatehandler,
    errs = errs,
  })

  local generr = (0 < size(errs) and not collect)

  if generr then
    error(table.concat(errs, ' | '))
  end

  return out
end


-- Internal utilities
-- ==================


-- Build a type validation error message.
_invalidTypeMsg = function(path, needtype, vt, v, _whence)
  local vs = (v == nil or v == S_null) and 'no value' or stringify(v)
  local vtname = type(vt) == S_number and typename(vt) or tostring(vt)

  local msg = 'Expected ' .. (1 < #path and ('field ' .. pathify(path, 1)
    .. ' to be ') or '') .. needtype .. ', but found ' .. ((v ~= nil and v ~= S_null)
    and (vtname .. S_VIZ) or '') .. vs

  msg = msg .. '.'
  return msg
end


-- Default inject handler for transforms.
_injecthandler = function(inj, val, ref, store)
  local out = val
  local iscmd = isfunc(val) and (NONE == ref or (type(ref) == S_string and ref:sub(1, 1) == S_DS))

  -- Only call val function if it is a special command ($NAME format).
  if iscmd then
    out = val(inj, val, ref, store)

  -- Update parent with value. Ensures references remain in node tree.
  elseif S_MVAL == inj.mode and inj.full then
    inj:setval(val)
  end

  return out
end


-- Validate handler - intercepts meta paths for validation.
_validatehandler = function(inj, val, ref, store)
  local out = val

  -- Check for meta path syntax: field$=value or field$~value
  local m = ref:match("^([^$]+)%$([=~])(.+)$")
  local ismetapath = m ~= nil

  if ismetapath then
    local eq = ref:match("^[^$]+%$(.)") -- '=' or '~'
    if '=' == eq then
      inj:setval({ S_BEXACT, val })
    else
      inj:setval(val)
    end
    inj.keyI = -1

    out = SKIP
  else
    out = _injecthandler(inj, val, ref, store)
  end

  return out
end


-- Inject store values into a string.
_injectstr = function(val, store, inj)
  -- Can't inject into non-strings
  if type(val) ~= S_string or val == S_MT then
    return S_MT
  end

  local out = val

  -- Full value wrapped in backticks
  local full_match = val:match("^`([^`]+)`$")

  if full_match then
    if inj then
      inj.full = true
    end

    local pathref = full_match

    if #pathref > 3 then
      pathref = pathref:gsub("%$BT", S_BT):gsub("%$DS", S_DS)
    end

    out = getpath(store, pathref, inj)
  else
    -- Check for partial injections within the string.
    out = val:gsub("`([^`]+)`", function(ref)
      if #ref > 3 then
        ref = ref:gsub("%$BT", S_BT):gsub("%$DS", S_DS)
      end

      if inj then
        inj.full = false
      end

      local found = getpath(store, ref, inj)

      if found == NONE then
        return S_MT
      elseif type(found) == S_string then
        return found
      elseif type(found) == 'table' then
        local dkjson = require("dkjson")
        local ok, result = pcall(dkjson.encode, found)
        if ok and result then return result end
        return islist(found) and '[...]' or '{...}'
      else
        return tostring(found)
      end
    end)

    -- Also call the inj handler on the entire string.
    if nil ~= inj and isfunc(inj.handler) then
      inj.full = true
      out = inj.handler(inj, out, val, store)
    end
  end

  return out
end


-- Define the StructUtility "class"
local StructUtility = {
  clone = clone,
  escre = escre,
  escurl = escurl,
  getpath = getpath,
  getprop = getprop,
  haskey = haskey,
  inject = inject,
  isempty = isempty,
  isfunc = isfunc,
  iskey = iskey,
  islist = islist,
  ismap = ismap,
  isnode = isnode,
  items = items,
  joinurl = joinurl,
  keysof = keysof,
  merge = merge,
  pathify = pathify,
  setprop = setprop,
  strkey = strkey,
  stringify = stringify,
  transform = transform,
  typify = typify,
  validate = validate,
  walk = walk,
}
StructUtility.__index = StructUtility

-- Constructor for StructUtility
function StructUtility:new(o)
  o = o or {}
  setmetatable(o, self)
  return o
end

return {
  StructUtility = StructUtility,
  clone = clone,
  escre = escre,
  escurl = escurl,
  getpath = getpath,
  getprop = getprop,
  haskey = haskey,
  inject = inject,
  isempty = isempty,
  isfunc = isfunc,
  iskey = iskey,
  islist = islist,
  ismap = ismap,
  isnode = isnode,
  items = items,
  joinurl = joinurl,
  keysof = keysof,
  merge = merge,
  pathify = pathify,
  setprop = setprop,
  strkey = strkey,
  stringify = stringify,
  transform = transform,
  typify = typify,
  validate = validate,
  walk = walk,
}
