-- Copyright (c) 2025 Voxgig Ltd. MIT LICENSE.
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

  NOTE: In this code JSON nulls are in general *not* considered the
  same as undefined values in the given language. However most
  JSON parsers do use the undefined value to represent JSON
  null. This is ambiguous as JSON null is a separate value, not an
  undefined value. You should convert such values to a special value
  to represent JSON null, if this ambiguity creates issues
  (thankfully in most APIs, JSON nulls are not used). For example,
  the unit tests use the string "__NULL__" where necessary.
]] ----------------------------------------------------------
-- String constants
----------------------------------------------------------
-- Mode value for inject step
local S_MKEYPRE = 'key:pre'
local S_MKEYPOST = 'key:post'
local S_MVAL = 'val'
local S_MKEY = 'key'

-- Special keys
local S_DKEY = '`$KEY`'
local S_DMETA = '`$META`'
local S_DTOP = '$TOP'
local S_DERRS = '$ERRS'

-- General strings
local S_array = 'array'
local S_base = 'base'
local S_boolean = 'boolean'

local S_function = 'function'
local S_number = 'number'
local S_object = 'object'
local S_string = 'string'
local S_null = 'null'
local S_key = 'key'
local S_parent = 'parent'
local S_MT = ''
local S_BT = '`'
local S_DS = '$'
local S_DT = '.'
local S_CN = ':'
local S_KEY = 'KEY'

-- The standard undefined value for this language
local UNDEF = nil

----------------------------------------------------------
-- Forward declarations for internal functions
----------------------------------------------------------
local _injectstr
local _injecthandler
local _invalidTypeMsg
local _validation

----------------------------------------------------------
-- Core Type Detection Functions
----------------------------------------------------------

-- Value is a defined list (array) with integer keys (indexes).
-- @param val (any) The value to check
-- @return (boolean) True if value is a list
local function islist(val)
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

-- Value is a defined map (hash) with string keys.
-- @param val (any) The value to check
-- @return (boolean) True if value is a map
local function ismap(val)
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

-- Value is a node - defined, and a map (hash) or list (array).
-- @param val (any) The value to check
-- @return (boolean) True if value is a node
local function isnode(val)
  if val == nil then
    return false
  end

  return ismap(val) or islist(val)
end

-- Value is a defined string (non-empty) or integer key.
-- @param key (any) The key to check
-- @return (boolean) True if key is valid
local function iskey(key)
  local keytype = type(key)
  return (keytype == S_string and key ~= S_MT and key ~= S_null) or keytype ==
           S_number
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

-- Determine the type of a value as a string.
-- Returns one of: 'null', 'string', 'number', 'boolean', 'function', 'array', 'object'
-- Normalizes and simplifies Lua's type system for consistency.
-- @param value (any) The value to check
-- @return (string) The type as a string
local function typify(value)
  if value == nil or value == "null" then
    return "null"
  end

  local basicType = type(value)

  -- Handle basic types that map directly
  if basicType == "string" then
    return "string"
  elseif basicType == "number" then
    return "number"
  elseif basicType == "boolean" then
    return "boolean"
  elseif basicType == "function" then
    return "function"
  elseif basicType == "table" then
    if islist(value) then
      return "array"
    else
      return "object"
    end
  end

  return "object"
end

----------------------------------------------------------
-- Forward Declarations for Circular References
----------------------------------------------------------
local getpath

----------------------------------------------------------
-- Property Access and Manipulation
----------------------------------------------------------

-- Safely get a property of a node. Nil arguments return nil.
-- If the key is not found, return the alternative value, if any.
-- @param val (any) The parent object/table
-- @param key (any) The key to access
-- @param alt (any) The alternative value if key not found
-- @return (any) The property value or alternative
local function getprop(val, key, alt)
  -- Handle nil arguments
  if val == UNDEF or key == UNDEF then
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

-- Convert different types of keys to string representation.
-- String keys are returned as is.
-- Number keys are converted to strings.
-- Floats are truncated to integers.
-- Booleans, objects, arrays, null, undefined all return empty string.
-- @param key (any) The key to convert
-- @return (string) The string representation of the key
local function strkey(key)
  if key == UNDEF or key == S_null then
    return S_MT
  end

  if type(key) == S_string then
    return key
  end

  if type(key) == S_boolean then
    return S_MT
  end

  if type(key) == S_number then
    if key % 1 == 0 then
      return tostring(key)
    else
      return tostring(math.floor(key))
    end
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
  return getprop(val, key) ~= UNDEF
end

-- Helper function to get sorted keys from a table
-- @param t (table) The table to get keys from
-- @return (table) Array of sorted keys
local function getKeys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
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
      table.insert(result, {i - 1, v})
    end
  else
    -- Handle map-like tables
    local keys = getKeys(val)
    for _, k in ipairs(keys) do
      table.insert(result, {k, val[k]})
    end
  end

  return result
end

----------------------------------------------------------
-- String and URL Handling
----------------------------------------------------------

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
-- @param val (any) The value to stringify
-- @param maxlen (number) Optional maximum length for result
-- @return (string) String representation of the value
local function stringify(val, maxlen)
  -- Handle nil case
  if val == nil then
    return S_MT
  end

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

    -- Handle cycles in tables
    if seen[obj] then
      return "..."
    end

    local obj_type = type(obj)

    -- Handle basic types
    if obj_type == "string" then
      return string.format("%q", obj)
    elseif obj_type == "number" or obj_type == "boolean" then
      return tostring(obj)
    elseif obj_type ~= "table" then
      return tostring(obj)
    end

    -- Mark this table as seen
    seen[obj] = true

    -- Handle tables (arrays and objects)
    local parts = {}
    local is_array = islist(obj)

    if is_array then
      -- Array-like tables
      for i = 1, #obj do
        table.insert(parts, serialize(obj[i], seen))
      end
    else
      -- Object-like tables
      local keys = sort_keys(obj)
      for _, k in ipairs(keys) do
        local v = obj[k]
        table.insert(parts, string.format("%s:%s", k, serialize(v, seen)))
      end
    end

    -- Remove the seen mark
    seen[obj] = nil

    if is_array then
      return "[" .. table.concat(parts, ",") .. "]"
    else
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end

  -- Main stringify logic
  local str = ""
  local success, result = pcall(function()
    return serialize(val)
  end)

  if success then
    str = result
  else
    str = S_MT .. tostring(val)
  end

  -- Remove quotes
  str = str:gsub('"', '')

  -- Handle maxlen
  if maxlen and maxlen > 0 then
    if #str > maxlen then
      if maxlen >= 3 then
        str = string.sub(str, 1, maxlen - 3) .. "..."
      else
        str = string.sub(str, 1, maxlen)
      end
    end
  end

  return str
end

-- Build a human friendly path string.
-- @param val (any) The path as array or string
-- @param from (number) Optional start index
-- @return (string) Formatted path string
local function pathify(val, from)
  local pathstr = UNDEF
  local path = UNDEF

  if islist(val) then
    path = val
  elseif type(val) == 'string' then
    path = {val}
  elseif type(val) == 'number' then
    path = {val}
  end

  -- Calculate start index
  local start
  if from == nil then
    start = 0
  elseif from >= 0 then
    start = from
  else
    start = 0
  end

  if path ~= UNDEF and start >= 0 then
    -- Slice path array from start
    local sliced = {}
    for i = start + 1, #path do
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
  if pathstr == UNDEF then
    pathstr = '<unknown-path'
    if val == UNDEF then
      pathstr = pathstr .. S_MT
    else
      pathstr = pathstr .. (S_CN .. stringify(val, 47))
    end
    pathstr = pathstr .. '>'
  end

  return pathstr
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
      -- Make sure to deep copy the __metadata field to keep it intact
      if mt.__metadata then
        local new_mt = {}
        for k, v in pairs(mt) do
          if k == "__metadata" then
            new_mt[k] = {}
            for mk, mv in pairs(v) do
              new_mt[k][mk] = mv
            end
          else
            new_mt[k] = v
          end
        end
        setmetatable(new_table, new_mt)
      else
        setmetatable(new_table, mt)
      end
    end

    return new_table
  end

  -- For all other types (numbers, strings, booleans), return as is
  return val
end

-- Safely set a property. Undefined arguments and invalid keys are ignored.
-- Returns the (possible modified) parent.
-- If the value is undefined it the key will be deleted from the parent.
-- If the parent is a list, and the key is negative, prepend the value.
-- NOTE: If the key is above the list size, append the value; below, prepend.
-- If the value is undefined, remove the list element at index key, and shift the
-- remaining elements down. These rules avoids "holes" in the list.
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
    if val == UNDEF then
      parent[key] = nil -- Use nil to properly remove the key
    else
      parent[key] = val
    end
  elseif islist(parent) then
    -- Ensure key is an integer
    local keyI = tonumber(key)
    setmetatable(parent, {
      __jsontype = {
        type = 'array'
      }
    })

    if keyI == nil then
      return parent
    end

    keyI = math.floor(keyI)

    -- Delete list element at position keyI, shifting later elements down
    if val == UNDEF then
      -- TypeScript is 0-indexed, Lua is 1-indexed
      -- Convert from JavaScript 0-based indexing to Lua 1-based indexing
      local luaIndex = keyI + 1

      if luaIndex >= 1 and luaIndex <= #parent then
        -- Shift elements down
        for i = luaIndex, #parent - 1 do
          parent[i] = parent[i + 1]
        end
        -- Remove the last element
        parent[#parent] = nil
      end
      -- Set or append value at position keyI
    elseif keyI >= 0 then -- TypeScript checks (0 <= keyI)
      -- Convert from JavaScript 0-based indexing to Lua 1-based indexing
      local luaIndex = keyI + 1

      -- If index is beyond current length, append to end
      if #parent < luaIndex then
        parent[#parent + 1] = val
      else
        -- Otherwise set at the specific index
        parent[luaIndex] = val
      end
      -- Prepend value if keyI is negative
    else
      table.insert(parent, 1, val)
    end
  end

  return parent
end

----------------------------------------------------------
-- Complex Data Structure Operations
----------------------------------------------------------

-- Walk a data structure depth first, applying a function to each value.
-- @param val (any) The value to walk
-- @param apply (function) Function to apply to each node
-- @param key (any) Current key (for recursive calls)
-- @param parent (table) Current parent (for recursive calls)
-- @param path (table) Current path (for recursive calls)
-- @return (any) The transformed value
local function walk(val, apply, -- These arguments are the public interface.
key, parent, path -- These arguments are used for recursive state.
)
  path = path or {} -- Initialize path as empty table for root level
  setmetatable(path, {
    __jsontype = "array"
  })

  if isnode(val) then
    -- items(val) returns an array of {key, value} pairs
    for _, item in ipairs(items(val)) do
      local ckey, child = item[1], item[2]

      -- Create a new path array
      local childPath = {}
      setmetatable(childPath, {
        __jsontype = "array"
      })
      for _, p in ipairs(path) do
        table.insert(childPath, p)
      end
      table.insert(childPath, S_MT .. tostring(ckey))

      setprop(val, ckey, walk(child, apply, ckey, val, childPath))
    end
  end

  -- Nodes are applied *after* their children.
  return apply(key, val, parent, path)
end

-- Merge a list of values into each other. Later values have
-- precedence. Nodes override scalars. Node kinds (list or map)
-- override each other, and do *not* merge. The first element is
-- modified.
-- @param val (any) Array of values to merge
-- @return (any) The merged result
local function merge(val)
  local out = UNDEF

  -- Handle edge cases
  if not islist(val) then
    return val
  end

  local list = val
  local lenlist = #list

  if lenlist == 0 then
    return UNDEF
  elseif lenlist == 1 then
    return list[1]
  end

  -- getprop expects 0-indexed list, so we need to adjust
  out = getprop(list, 0, {})

  for oI = 2, lenlist do
    local obj = list[oI]

    if not isnode(obj) then
      -- Nodes win
      out = obj
    else
      -- Nodes win, also over nodes of a different kind
      if (not isnode(out) or (ismap(obj) and islist(out)) or
        (islist(obj) and ismap(out))) then
        out = obj
      else
        -- Node stack walking down the current obj
        local cur = {}
        cur[1] = out
        local cI = 1

        local function merger(key, val, parent, path)
          if key == nil then
            return val
          end

          -- Get the current value at the current path in obj
          local lenpath = #path
          cI = lenpath
          if cur[cI] == UNDEF then
            local pathSlice = {}
            for i = 1, lenpath - 1 do
              table.insert(pathSlice, path[i])
            end
            cur[cI] = getpath(pathSlice, out)
          end

          -- Create node if needed
          if not isnode(cur[cI]) then
            if islist(parent) then
              cur[cI] = {}
              setmetatable(cur[cI], {
                __jsontype = "array"
              })
            else
              cur[cI] = {}
            end
          end

          -- Node child is just ahead of us on the stack, since
          -- `walk` traverses leaves before nodes.
          if isnode(val) and not isempty(val) then
            setprop(cur[cI], key, cur[cI + 1])
            cur[cI + 1] = UNDEF
          else
            -- Scalar child
            setprop(cur[cI], key, val)
          end

          return val
        end

        -- Walk overriding node, creating paths in output as needed
        walk(obj, merger)
        out = cur[1]
      end
    end
  end

  return out
end

-- Get a value deep inside a node using a key path.  For example the
-- path `a.b` gets the value 1 from {a={b=1}}.  The path can specified
-- as a dotted string, or a string array.  If the path starts with a
-- dot (or the first element is ''), the path is considered local, and
-- resolved against the `current` argument, if defined.  Integer path
-- parts are used as array indexes.  The state argument allows for
-- custom handling when called from `inject` or `transform`.
-- @param path (string|table) The path to the value
-- @param store (table) The data store to search in
-- @param current (any) Current context for relative paths
-- @param state (table) Optional state for custom handling
-- @return (any) The value at the path
getpath = function(path, store, current, state)
  -- Operate on a string array
  local parts

  if islist(path) then
    parts = path
  elseif type(path) == S_string then
    parts = {}
    for part in string.gmatch(path .. S_DT,
      "([^" .. S_DT .. "]*)(" .. S_DT .. ")") do
      table.insert(parts, part)
    end
    if path == "" then
      parts = {S_MT}
    end
  else
    return nil
  end

  local root = store
  local val = store
  local base = state and state.base or nil

  -- An empty path (incl empty string) just finds the store
  if path == nil or store == nil or (#parts == 1 and parts[1] == S_MT) then
    -- The actual store data may be in a store sub property, defined by state.base
    val = getprop(store, base, store)
  elseif #parts > 0 then
    local pI = 1

    -- Relative path uses `current` argument
    if parts[1] == S_MT then
      pI = 2
      root = current
    end

    local part = pI <= #parts and parts[pI] or nil
    local first = getprop(root, part)

    -- At top level, check state.base, if provided
    if first == nil and pI == 1 then
      val = getprop(getprop(root, base), part)
    else
      val = first
    end

    -- Move along the path, trying to descend into the store
    pI = pI + 1
    while val ~= nil and pI <= #parts do
      val = getprop(val, parts[pI])
      pI = pI + 1
    end
  end

  -- State may provide a custom handler to modify found value
  if state ~= nil and isfunc(state.handler) then
    local ref = pathify(path)
    val = state.handler(state, val, current, ref, store)
  end

  return val
end

-- Set  state.key property of state.parent node, ensuring reference consistency
-- when needed by implementation language.
-- @param state (table) The injection state
-- @param val (any) The value to set
-- @return (any) The modified parent
_setparentprop = function(state, val)
  setprop(state.parent, state.key, val)
end


-- Default inject handler for transforms. If the path resolves to a function,
-- call the function passing the injection state. This is how transforms operate.
-- @param state (table) The injection state
-- @param val (any) The value being injected
-- @param current (any) The current context
-- @param ref (string) The reference string
-- @param store (table) The data store
-- @return (any) The processed value
_injecthandler = function(state, val, current, ref, store)
  -- Check if it's a command by checking if it's a function and starts with $
  local iscmd = isfunc(val) and (UNDEF == ref or ref:sub(1, 1) == S_DS)

  -- Handle commands with numeric suffixes (e.g., $COPY2, $MERGE3)
  if ref and not iscmd then
    -- Extract the base command name without numeric suffix
    local base_command = ref:match("^(%$[A-Z]+)%d*$")

    if base_command and store[base_command] then
      val = store[base_command]
      iscmd = true
    end
  end

  -- Only call val function if it is a special command ($NAME format).
  if iscmd then
    -- Execute the command function
    val = val(state, val, current, ref, store)

    -- Update parent with value. Ensures references remain in node tree.
  elseif S_MVAL == state.mode and state.full then
    setprop(state.parent, state.key, val)
  end

  return val
end

-- Inject store values into a string. Not a public utility - used by
-- `inject`.  Inject are marked with `path` where path is resolved
-- with getpath against the store or current (if defined)
-- arguments. See `getpath`.  Custom injection handling can be
-- provided by state.handler (this is used for transform functions).
-- The path can also have the special syntax $NAME999 where NAME is
-- upper case letters only, and 999 is any digits, which are
-- discarded. This syntax specifies the name of a transform, and
-- optionally allows transforms to be ordered by alphanumeric sorting.
-- @param val (string) The string to inject into
-- @param store (table) The data store
-- @param current (any) Current context
-- @param state (table) The injection state
-- @return (any) The injected result
_injectstr = function(val, store, current, state)
  -- Can't inject into non-strings
  if type(val) ~= S_string then
    return S_MT
  end

  -- Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`"
  -- Match for full value wrapped in backticks
  local full_match = val:match("^`([^`]+)`$")

  -- Full string of the val is an injection.
  if full_match then
    if state then
      state.full = true
    end

    local pathref = full_match

    -- Special escapes inside injection.
    if #pathref > 3 then
      pathref = pathref:gsub("%$BT", S_BT):gsub("%$DS", S_DS)
    end

    -- Get the extracted path reference.
    local out = getpath(pathref, store, current, state)
    return out
  end

  -- Handle partial injections in the string
  local out = val:gsub("`([^`]+)`", function(ref)
    -- Special escapes inside injection.
    if #ref > 3 then
      ref = ref:gsub("%$BT", S_BT):gsub("%$DS", S_DS)
    end

    if state then
      state.full = false
    end

    local found = getpath(ref, store, current, state)

    -- Ensure inject value is a string.
    if found == UNDEF then
      return S_MT
    elseif type(found) == "table" then
      -- Handle maps and arrays (tables in Lua) by converting to JSON
      local dkjson = require("dkjson")

      -- Ensure proper encoding based on the table type
      local mt = getmetatable(found)
      if mt and mt.__jsontype then
        -- Use the existing jsontype from metatable
      elseif islist(found) then
        -- Set array jsontype for list-like tables 
        setmetatable(found, {
          __jsontype = "array"
        })
      elseif ismap(found) then
        -- Set object jsontype for map-like tables
        setmetatable(found, {
          __jsontype = "object"
        })
      end

      -- Convert to JSON
      local ok, result = pcall(dkjson.encode, found)
      if ok and result then
        return result
      else
        -- More graceful fallback
        return (islist(found) and "[...]" or "{...}")
      end
    else
      return tostring(found)
    end
  end)

  -- Also call the state handler on the entire string
  if state ~= nil and isfunc(state.handler) then
    state.full = true
    out = state.handler(state, out, current, val, store)
  end

  return out
end

-- Inject values from a data store into a node recursively, resolving
-- paths against the store, or current if they are local. THe modify
-- argument allows custom modification of the result.  The state
-- (InjectState) argument is used to maintain recursive state.
-- @param val (any) The value to inject into
-- @param store (table) The data store
-- @param modify (function) Optional modifier function
-- @param current (any) Current context
-- @param state (table) The injection state
-- @return (any) The injected result
local function inject(val, store, modify, current, state)
  local valtype = type(val)

  -- Create state if at root of injection
  if state == UNDEF then
    local parent = {}
    parent[S_DTOP] = val

    -- Set up state starting in the virtual parent
    state = {
      mode = S_MVAL,
      full = false,
      keyI = 0,
      keys = {S_DTOP},
      key = S_DTOP,
      val = val,
      parent = parent,
      path = {S_DTOP},
      nodes = {parent},
      handler = _injecthandler,
      base = S_DTOP,
      modify = modify,
      errs = getprop(store, S_DERRS, {}),
      meta = {}
    }
  end

  -- Resolve current node in store for local paths
  if current == UNDEF then
    current = {
      ["$TOP"] = store
    }
  else
    local parentkey = #state.path > 1 and state.path[#state.path - 1] or nil
    current = parentkey == nil and current or getprop(current, parentkey)
  end

  -- Descend into node.
  if isnode(val) then
    -- Get sorted keys
    local nodekeys = {}

    if ismap(val) then
      -- First get keys that don't include S_DS
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

      -- Combine the keys (regular first, then $ keys)
      for _, k in ipairs(regular_keys) do
        table.insert(nodekeys, k)
      end

      for _, k in ipairs(ds_keys) do
        table.insert(nodekeys, k)
      end
    else
      -- For lists, use indices
      for i = 1, #val do
        table.insert(nodekeys, tostring(i - 1)) -- Adjust for 0-based indexing
      end
    end

    -- Process each key
    local nkI = 0
    while nkI < #nodekeys do
      local nodekey = nodekeys[nkI + 1]

      local childpath = {table.unpack(state.path)}
      table.insert(childpath, nodekey)

      local childnodes = {table.unpack(state.nodes)}
      table.insert(childnodes, val)

      local childval = getprop(val, nodekey)

      local childstate = {
        mode = S_MKEYPRE,
        full = false,
        keyI = nkI,
        keys = nodekeys,
        key = nodekey,
        val = childval,
        parent = val,
        path = childpath,
        nodes = childnodes,
        handler = _injecthandler,
        base = state.base,
        errs = state.errs,
        meta = state.meta
      }

      -- Perform key:pre mode injection
      local prekey = _injectstr(nodekey, store, current, childstate)

      -- Update in case of modification
      nkI = childstate.keyI
      nodekeys = childstate.keys

      -- Process if prekey is defined
      if prekey ~= UNDEF then
        childstate.val = getprop(val, prekey)
        childval = childstate.val
        childstate.mode = S_MVAL

        -- Perform val mode injection
        inject(childval, store, modify, current, childstate)

        -- Update again
        nkI = childstate.keyI
        nodekeys = childstate.keys

        -- Perform key:post mode injection
        childstate.mode = S_MKEYPOST
        _injectstr(nodekey, store, current, childstate)

        -- Final update
        nkI = childstate.keyI
        nodekeys = childstate.keys
      end

      nkI = nkI + 1
    end
  elseif valtype == S_string then
    -- Inject paths into string scalars
    state.mode = S_MVAL
    val = _injectstr(val, store, current, state)
    setprop(state.parent, state.key, val)
  end

  -- Custom modification
  if modify then
    local mkey = state.key
    local mparent = state.parent
    local mval = getprop(mparent, mkey)
    modify(mval, mkey, mparent, state, current, store)
  end

  -- Return the processed value
  return getprop(state.parent, S_DTOP)
end

----------------------------------------------------------
-- Transform Functions
----------------------------------------------------------

-- Delete a key from a map or list.
-- @param state (table) The injection state
-- @return (nil) Always returns nil
local function transform_DELETE(state)
  local key, parent = state.key, state.parent
  setprop(parent, key, UNDEF)
  return UNDEF
end

-- Copy value from source data.
-- @param state (table) The injection state
-- @param _val (any) The current value (unused)
-- @param current (any) The current context
-- @return (any) The copied value
local function transform_COPY(state, _val, current)
  local mode, key, parent = state.mode, state.key, state.parent

  local out = key
  if mode ~= S_MKEYPRE and mode ~= S_MKEYPOST then
    out = getprop(current, key)
    setprop(parent, key, out)
  end

  return out
end

-- As a value, inject the key of the parent node.
-- As a key, defined the name of the key property in the source object.
-- @param state (table) The injection state
-- @param _val (any) The current value (unused)
-- @param current (any) The current context
-- @return (any) The key value
local function transform_KEY(state, _val, current)
  local mode, path, parent = state.mode, state.path, state.parent

  -- Do nothing unless in val mode
  if mode ~= S_MVAL then
    return UNDEF
  end

  -- Key is defined by $KEY meta property
  local keyspec = getprop(parent, S_DKEY)
  if keyspec ~= UNDEF then
    setprop(parent, S_DKEY, UNDEF)
    return getprop(current, keyspec)
  end

  -- Try to get metadata from the parent metatable
  local mt = getmetatable(parent)
  if mt and mt.__metadata and mt.__metadata[S_KEY] then
    return mt.__metadata[S_KEY]
  end

  -- If not in parent, try to find it in the current object
  if current and type(current) == "table" then
    -- First try current itself
    mt = getmetatable(current)
    if mt and mt.__metadata and mt.__metadata[S_KEY] then
      return mt.__metadata[S_KEY]
    end

    -- Then try current[$TOP] if it exists
    local current_array = getprop(current, S_DTOP)
    if current_array and islist(current_array) and #current_array > 0 then
      -- Get the index from the path
      local idx_str = path[#path - 2]
      local idx = tonumber(idx_str)
      if idx and idx >= 0 and idx < #current_array then
        local item = current_array[idx + 1] -- Convert to 1-based index
        if item then
          mt = getmetatable(item)
          if mt and mt.__metadata and mt.__metadata[S_KEY] then
            return mt.__metadata[S_KEY]
          end
        end
      end
    end
  end

  -- Fallback to the original approach as a last resort
  return getprop(getprop(parent, S_DMETA), S_KEY, getprop(path, #path - 2))
end

-- Store meta data about a node.  Does nothing itself, just used by
-- other injectors, and is removed when called.
-- @param state (table) The injection state
-- @return (nil) Always returns nil
local function transform_META(state)
  local parent = state.parent
  setprop(parent, S_DMETA, UNDEF)
  return UNDEF
end

-- Merge a list of objects into the current object. 
-- Must be a key in an object. The value is merged over the current object.
-- If the value is an array, the elements are first merged using `merge`. 
-- If the value is the empty string, merge the top level store.
-- Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
-- @param state (table) The injection state
-- @param _val (any) The current value (unused)
-- @param current (any) The current context
-- @return (any) The key or nil depending on mode
local function transform_MERGE(state, _val, current)
  local mode, key, parent = state.mode, state.key, state.parent

  if mode == S_MKEYPRE then
    return key
  end

  -- Operate after child values have been transformed.
  if mode == S_MKEYPOST then
    local args = getprop(parent, key)

    if args == S_MT then
      args = {current["$TOP"]}
    else
      if islist(args) then
        -- Keep args as a list
      else
        args = {args}
      end
    end

    -- Add metadata for array 
    if islist(args) then
      setmetatable(args, {
        __jsontype = "array"
      })
    end

    -- Remove the $MERGE command from a parent map.
    setprop(parent, key, UNDEF)

    -- Build the mergelist explicitly
    local mergelist = {parent} -- Start with parent

    -- Add all items from args
    if islist(args) then
      for i = 1, #args do
        table.insert(mergelist, args[i])
      end
    else
      table.insert(mergelist, args)
    end

    table.insert(mergelist, clone(parent)) -- End with parent clone

    -- Apply the metadata
    setmetatable(mergelist, {
      __jsontype = "array"
    })

    -- Perform the merge
    merge(mergelist)

    return key
  end

  return UNDEF
end

-- Convert a node to a list.
-- Format: ['`$EACH`', '`source-path-of-node`', child-template]
-- @param state (table) The injection state
-- @param _val (any) The current value (unused)
-- @param current (any) The current context
-- @param _ref (string) The reference string (unused)
-- @param store (table) The data store
-- @return (any) The first item or nil
local function transform_EACH(state, _val, current, _ref, store)
  local mode, keys, path, parent, nodes = state.mode, state.keys, state.path,
    state.parent, state.nodes

  -- Remove arguments to avoid spurious processing.
  if keys then
    while #keys > 1 do
      table.remove(keys)
    end
  end

  if S_MVAL ~= mode then
    return UNDEF
  end

  -- Get arguments: ['`$EACH`', 'source-path', child-template]
  local srcpath = parent[2]
  local child = clone(parent[3])

  -- Source data
  local src = getpath(srcpath, store, current, state)

  -- Find the target key and parent to update
  local tkey = path[#path - 1]
  local target = nodes[#nodes - 1]

  -- Create parallel arrays for templates and source values
  local tval = {} -- Templates 
  setmetatable(tval, {
    __jsontype = "array"
  })
  local tcur = {} -- Source values
  setmetatable(tcur, {
    __jsontype = "array"
  })

  -- Extract values from source object/array with deterministic ordering
  if src ~= nil then
    if islist(src) then
      -- For arrays, create a template for each source item
      for i = 1, #src do
        local copy_child = clone(child)
        -- Add metadata with KEY for each item
        copy_child[S_DMETA] = {
          [S_KEY] = tostring(i - 1) -- Use 0-based index to match JS/Go
        }

        -- Use metatables to store metadata
        local mt = {
          __jsontype = "object",
          __metadata = {
            [S_KEY] = tostring(i - 1)
          }
        }
        setmetatable(copy_child, mt)

        table.insert(tval, copy_child)
        -- Add the corresponding source value to tcur
        table.insert(tcur, src[i])
      end
    elseif ismap(src) then
      -- For maps, extract values in key-sorted order for deterministic behavior
      local sortedKeys = {}
      for k in pairs(src) do
        table.insert(sortedKeys, k)
      end
      table.sort(sortedKeys) -- Sort keys alphabetically

      for _, k in ipairs(sortedKeys) do
        local copy_child = clone(child)
        -- Keep regular metadata for backward compatibility
        copy_child[S_DMETA] = {
          [S_KEY] = k -- Use the map key (e.g., "a")
        }

        -- Use metatables to store metadata
        local mt = {
          __jsontype = "object",
          __metadata = {
            [S_KEY] = k
          }
        }
        setmetatable(copy_child, mt)

        table.insert(tval, copy_child)
        table.insert(tcur, src[k])
      end
    end
  end

  -- Wrap source values exactly as TypeScript/Go do
  tcur = {
    [S_DTOP] = tcur
  }

  -- Process templates with source values
  tval = inject(tval, store, state.modify, tcur)

  -- Update the parent with the result
  setprop(target, tkey, tval)

  -- Return first entry if available
  if #tval > 0 then
    return tval[1]
  else
    return nil
  end
end

-- Convert a node to a map
-- Format: { '`$PACK`':['`source-path`', child-template]}
-- @param state (table) The injection state
-- @param _val (any) The current value (unused)
-- @param current (any) The current context
-- @param _ref (string) The reference string (unused)
-- @param store (table) The data store
-- @return (nil) Always returns nil
local function transform_PACK(state, _val, current, _ref, store)
  local mode, key, path, parent, nodes = state.mode, state.key, state.path,
    state.parent, state.nodes

  -- Defensive context checks
  if S_MKEYPRE ~= mode or type(key) ~= S_string or path == nil or nodes == nil then
    return UNDEF
  end

  -- Get arguments
  local args = parent[key]
  local srcpath = args[1] -- Path to source data
  local child = clone(args[2]) -- Child template

  -- Find key and target node
  local keyprop = child[S_DKEY]
  local tkey = path[#path - 1]
  local target = nodes[#path - 1] or nodes[#path]

  -- Source data
  local src = getpath(srcpath, store, current, state)

  -- Prepare source as a list
  local srclist = {}
  if islist(src) then
    srclist = src
  elseif ismap(src) then
    -- Transform map to array with metadata, similar to TypeScript's reduce
    for k, v in pairs(src) do
      -- Add metadata directly on the original value
      if v[S_DMETA] == nil then
        v[S_DMETA] = {}
      end
      v[S_DMETA][S_KEY] = k

      -- Lua specific: Also add to metatable to ensure KEY retrieval works
      setmetatable(v, {
        __jsontype = "object",
        __metadata = {
          [S_KEY] = k
        }
      })

      table.insert(srclist, v)
    end
  else
    return UNDEF
  end

  if #srclist == 0 then
    return UNDEF
  end

  -- Get key if specified
  local childkey = getprop(child, S_DKEY)
  local keyname = childkey == UNDEF and keyprop or childkey
  setprop(child, S_DKEY, UNDEF)

  -- Build target object using same pattern as TypeScript
  local tval = {}
  for _, n in ipairs(srclist) do
    local kn = getprop(n, keyname)
    if kn ~= UNDEF then
      setprop(tval, kn, clone(child))
      local nchild = getprop(tval, kn)
      setprop(nchild, S_DMETA, getprop(n, S_DMETA))

      -- Lua specific: Set metatable to ensure KEY retrieval works
      setmetatable(nchild, {
        __jsontype = "object",
        __metadata = getprop(n, S_DMETA)
      })
    end
  end

  -- Build parallel source object exactly like TypeScript
  local tcurrent = {}
  for _, n in ipairs(srclist) do
    local kn = getprop(n, keyname)
    if kn ~= UNDEF then
      setprop(tcurrent, kn, n)
    end
  end

  -- Wrap in $TOP exactly like TypeScript
  tcurrent = {
    [S_DTOP] = tcurrent
  }

  -- Process the structure
  tval = inject(tval, store, state.modify, tcurrent)

  -- Update target
  setprop(target, tkey, tval)

  -- Drop transform key
  return UNDEF
end

-- Transform data using spec.
-- Only operates on static JSON-like data.
-- Arrays are treated as if they are objects with indices as keys.
-- @param data (any) Source data to transform into new data (original not mutated)
-- @param spec (any) Transform specification; output follows this shape
-- @param extra (any) Additional store of data and transforms
-- @param modify (function) Optionally modify individual values
-- @return (any) The transformed data
local function transform(data, spec, extra, modify)
  -- Clone the spec so that the clone can be modified in place as the transform result
  spec = clone(spec)

  -- Split extra transforms from extra data
  local extraTransforms = {}
  local extraData = {}

  if extra ~= nil then
    for _, item in ipairs(items(extra)) do
      local k, v = item[1], item[2]
      if type(k) == 'string' and k:sub(1, 1) == S_DS then
        extraTransforms[k] = v
      else
        extraData[k] = v
      end
    end
  end

  -- Clone both extraData and data, then merge them
  -- The nil checks mirror the TypeScript UNDEF checks
  -- This creates our data source for transforms
  local extraDataClone = clone(extraData or {})
  local dataClone = clone(data or {})
  local mergedData = merge({extraDataClone, dataClone})

  -- Define a top level store that provides transform operations
  local store = {
    -- The inject function recognises this special location for the root of the source data.
    -- This exactly matches TypeScript and Go
    [S_DTOP] = mergedData,

    -- Escape backtick (works inside backticks too)
    [S_DS .. 'BT'] = function()
      return S_BT
    end,

    -- Escape dollar sign (works inside backticks too)
    [S_DS .. 'DS'] = function()
      return S_DS
    end,

    -- Insert current date and time as an ISO string
    [S_DS .. 'WHEN'] = function()
      return os.date('!%Y-%m-%dT%H:%M:%S.000Z')
    end,

    -- Built-in transform functions
    [S_DS .. 'DELETE'] = transform_DELETE,
    [S_DS .. 'COPY'] = transform_COPY,
    [S_DS .. 'KEY'] = transform_KEY,
    [S_DS .. 'META'] = transform_META,
    [S_DS .. 'MERGE'] = transform_MERGE,
    [S_DS .. 'EACH'] = transform_EACH,
    [S_DS .. 'PACK'] = transform_PACK
  }

  -- Add custom extra transforms, if any
  for k, v in pairs(extraTransforms) do
    store[k] = v
  end

  -- Build the transformed structure
  -- In Go, this passes 'nil' for the state parameter explicitly
  -- In Lua, we let inject handle creating the state
  local out = inject(spec, store, modify, store)

  return out
end

----------------------------------------------------------
-- Validation Functions
----------------------------------------------------------

-- Build a type validation error message.
-- @param path (any) Path to the invalid value
-- @param needtype (string) Expected type
-- @param vt (string) Actual type
-- @param v (any) The invalid value
-- @param whence (string) The source of the error
-- @return (string) Formatted error message
_invalidTypeMsg = function(path, needtype, vt, v, whence)
  local vs = nil == v and 'no value' or stringify(v)
  local msg = 'Expected ' .. (1 < #path and ('field ' .. pathify(path, 1) 
  .. ' to be ') or '') .. needtype .. ', but found ' .. (nil ~= v and (vt .. ': ') or '') .. vs

  -- Uncomment to help debug validation errors.
  -- msg = msg .. ' [' .. whence .. ']'
  msg = msg .. '.'

  return msg
end

-- A required string value. NOTE: Rejects empty strings.
-- @param state (table) The validation state
-- @param val (any) The value to validate
-- @param current (any) The current context
-- @return (string|nil) The validated string or nil
local function validate_STRING(state, val, current)
  local out = getprop(current, state.key)

  local t = typify(out)
  if S_string ~= t then
    local msg = _invalidTypeMsg(state.path, S_string, t, out, 'V1010')
    table.insert(state.errs, msg)
    return UNDEF
  end

  if S_MT == out then
    local msg = 'Empty string at ' .. pathify(state.path, 1)
    table.insert(state.errs, msg)
    return UNDEF
  end

  return out
end

-- A required number value (int or float).
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @return (number|nil) The validated number or nil
local function validate_NUMBER(state, _val, current)
  local out = getprop(current, state.key)

  local t = typify(out)
  if S_number ~= t then
    table.insert(state.errs, _invalidTypeMsg(state.path, S_number, t, out, 'V1020'))
    return UNDEF
  end

  return out
end

-- A required boolean value.
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @return (boolean|nil) The validated boolean or nil
local function validate_BOOLEAN(state, _val, current)
  local out = getprop(current, state.key)

  local t = typify(out)
  if S_boolean ~= t then
    table.insert(state.errs, _invalidTypeMsg(state.path, S_boolean, t, out, 'V1030'))
    return UNDEF
  end

  return out
end

-- A required object (map) value (contents not validated).
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @return (table|nil) The validated object or nil
local function validate_OBJECT(state, _val, current)
  local out = getprop(current, state.key)

  local t = typify(out)
  if t ~= S_object then
    table.insert(state.errs, _invalidTypeMsg(state.path, S_object, t, out, 'V1040'))
    return UNDEF
  end

  return out
end

-- A required array (list) value (contents not validated).
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @return (table|nil) The validated array or nil
local function validate_ARRAY(state, _val, current)
  local out = getprop(current, state.key)

  local t = typify(out)
  if t ~= S_array then
    table.insert(state.errs, _invalidTypeMsg(state.path, S_array, t, out, 'V1050'))
    return UNDEF
  end

  return out
end

-- A required function value.
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @return (function|nil) The validated function or nil
local function validate_FUNCTION(state, _val, current)
  local out = getprop(current, state.key)

  local t = typify(out)
  if S_function ~= t then
    table.insert(state.errs, _invalidTypeMsg(state.path, S_function, t, out, 'V1060'))
    return UNDEF
  end

  return out
end

-- Allow any value.
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @return (any) The value as is
local function validate_ANY(state, _val, current)
  return getprop(current, state.key)
end

-- Specify child values for map or list.
-- Map syntax: {'`$CHILD`': child-template }
-- List syntax: ['`$CHILD`', child-template ]
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @return (any) Depends on context
local function validate_CHILD(state, _val, current)
  local mode, key, parent, keys, path = state.mode, state.key, state.parent,
    state.keys, state.path

  -- Map syntax.
  if S_MKEYPRE == mode then
    local childtm = getprop(parent, key)

    -- Get corresponding current object.
    local pkey = getprop(path, #path - 2)
    local tval = getprop(current, pkey)

    if UNDEF == tval then
      tval = {}
    elseif not ismap(tval) then
      local msg = _invalidTypeMsg(table.move(state.path, 1, #state.path - 1, 1,
        {}), S_object, typify(tval), tval, 'V1070')
      table.insert(state.errs, msg)
      return UNDEF
    end

    local ckeys = keysof(tval)
    for _, ckey in ipairs(ckeys) do
      setprop(parent, ckey, clone(childtm))

      -- NOTE: modifying state! This extends the child value loop in inject.
      table.insert(keys, ckey)
    end

    -- Remove $CHILD to cleanup output.
    _setparentprop(state, UNDEF)
    return UNDEF
  end

  -- List syntax.
  if S_MVAL == mode then
    if not islist(parent) then
      -- $CHILD was not inside a list.
      table.insert(state.errs, 'Invalid $CHILD as value')
      return UNDEF
    end

    local childtm = getprop(parent, 1)

    if UNDEF == current then
      -- Empty list as default.
      for i = 1, #parent do
        parent[i] = nil
      end
      return UNDEF
    end

    if not islist(current) then
      local msg = _invalidTypeMsg(table.move(state.path, 1, #state.path - 1, 1,
        {}), S_array, typify(current), current, 'V0230')
      table.insert(state.errs, msg)
      state.keyI = #parent
      return current
    end

    -- Clone children and reset state key index.
    -- The inject child loop will now iterate over the cloned children,
    -- validating them against the current list values.
    for i = 1, #current do
      parent[i] = clone(childtm)
    end
    for i = #current + 1, #parent do
      parent[i] = nil
    end
    state.keyI = 0
    local out = getprop(current, 0)
    return out
  end

  return UNDEF
end

----------------------------------------------------------
-- Forward declaration for validate to resolve circular dependency
----------------------------------------------------------
local validate

-- Match at least one of the specified shapes.
-- Syntax: ['`$ONE`', alt0, alt1, ...] 
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @param _ref (string) The reference string (unused)
-- @param store (table) The data store
-- @return (nil) Does not return a value directly
local function validate_ONE(state, _val, current, _ref, store)
  local mode, parent, path, keyI, nodes = state.mode, state.parent, state.path,
    state.keyI, state.nodes

  -- Only operate in val mode, since parent is a list.
  if S_MVAL == mode then
    if not islist(parent) or 0 ~= keyI then
      table.insert(state.errs, 'The $ONE validator at field ' ..
        pathify(state.path, 1, 1) ..
        ' must be the first element of an array.')
      return
    end

    state.keyI = #state.keys

    local grandparent = nodes[#nodes - 1]
    local grandkey = path[#path - 1]

    -- Clean up structure, replacing [$ONE, ...] with current
    setprop(grandparent, grandkey, current)
    state.path = {table.unpack(state.path, 1, #state.path - 1)}
    state.key = state.path[#state.path]

    local tvals = parent.slice(1)
    if 0 == #tvals then
      table.insert(state.errs, 'The $ONE validator at field ' ..
        pathify(state.path, 1, 1) ..
        ' must have at least one argument.')
      return
    end

    -- See if we can find a match.
    for _, tval in ipairs(tvals) do
      -- If match, then errs.length = 0
      local terrs = {}
      setmetatable(terrs, {
        __jsontype = {
          type = 'array'
        }
      })

      local vstore = { }
      for k, v in pairs(store) do
        vstore[k] = v
      end
      vstore["$TOP"] = current
      local vcurrent = validate(current, tval, vstore, terrs)
      setprop(grandparent, grandkey, vcurrent)

      -- Accept current value if there was a match
      if 0 == #terrs then
        return
      end
    end

    -- There was no match.
    -- Build validation description
    local valdesc = {}
    for _, v in ipairs(tvals) do
      table.insert(valdesc, stringify(v))
    end
    local valdesc_str = table.concat(valdesc, ', ')
    -- Replace `$WORD` with word in lowercase
    valdesc_str = valdesc_str:gsub('`%$([A-Z]+)`', function(p1)
      return string.lower(p1)
    end)

    -- Create path slice
    local path_slice = {}
    for i = 1, #state.path do
      table.insert(path_slice, state.path[i - 1])

    end

    table.insert(state.errs, _invalidTypeMsg(path_slice,
      'one of ' .. valdesc_str, typify(current), current, 'V0210'))
  end
end

-- Match exactly one of the specified values.
-- Syntax: ['`$EXACT`', val1, val2, ...]
-- @param state (table) The validation state
-- @param _val (any) The value to validate (unused)
-- @param current (any) The current context
-- @param _ref (string) The reference string (unused)
-- @param _store (table) The data store
-- @return (nil) Does not return a value directly
local function validate_EXACT(state, _val, current, _ref, _store)
  local mode, parent, path, keyI, nodes = state.mode, state.parent, state.path, state.keyI, state.nodes

  -- Only operate in val mode, since parent is a list.
  if S_MVAL == mode then
    if not islist(parent) or 0 ~= keyI then
      table.insert(state.errs, 'The $EXACT validator at field ' ..
        pathify(state.path, 1, 1) ..
        ' must be the first element of an array.')
      return
    end

    state.keyI = #state.keys

    local grandparent = nodes[#nodes - 1]
    local grandkey = path[#path - 1]

    -- Clean up structure, replacing [$EXACT, ...] with current
    setprop(grandparent, grandkey, current)
    state.path = {table.unpack(state.path, 1, #state.path - 1)}
    state.key = state.path[#state.path]

    -- Create tvals array from parent elements starting at index 2
    local tvals = {}
    for i = 2, #parent do
      table.insert(tvals, parent[i])
    end

    if #tvals == 0 then
      table.insert(state.errs, 'The $EXACT validator at field ' ..
        pathify(state.path, 1, 1) ..
        ' must have at least one argument.')
      return
    end

    -- See if we can find an exact value match.
    local currentstr
    local found_match = false
    
    for _, tval in ipairs(tvals) do
      local exactmatch = tval == current

      if not exactmatch and isnode(tval) then
        if currentstr == nil then
          currentstr = stringify(current)
        end
        local tvalstr = stringify(tval)
        exactmatch = tvalstr == currentstr
      end

      if exactmatch then
        found_match = true
        break
      end
    end

    -- If no match was found, report the error
    if not found_match then
      local valdesc = {}
      for _, v in ipairs(tvals) do
        table.insert(valdesc, stringify(v))
      end
      local valdesc_str = table.concat(valdesc, ', ')
      
      table.insert(state.errs, _invalidTypeMsg(
        state.path,
        (#state.path > 1 and '' or 'value ') ..
        'exactly equal to ' .. (#tvals == 1 and '' or 'one of ') .. valdesc_str,
        typify(current), current, 'V0110'))
    end
  else
    setprop(parent, state.key, UNDEF)
  end
end


-- This is the "modify" argument to inject. Use this to perform
-- generic validation. Runs *after* any special commands.
-- @param pval (any) Property value from spec
-- @param key (any) The key being validated
-- @param parent (table) The parent object
-- @param state (table) The validation state
-- @param current (any) The current context
-- @param _store (table) The data store (unused)
_validation = function(pval, key, parent, state, current, _store)
  if UNDEF == state then
    return
  end

  -- Current val to verify.
  local cval = getprop(current, key)

  if UNDEF == cval or UNDEF == state then
    return
  end

  local ptype = typify(pval)

  -- Delete any special commands remaining.
  if S_string == ptype and string.find(pval, S_DS, 1, true) then
    return
  end

  local ctype = typify(cval)

  -- Type mismatch.
  if ptype ~= ctype and UNDEF ~= pval then
    table.insert(state.errs, _invalidTypeMsg(state.path, ptype, ctype, cval, 'V0010'))
    return
  end

  if ismap(cval) then
    if not ismap(pval) then
      table.insert(state.errs, _invalidTypeMsg(state.path, ptype, ctype, cval, 'V0020'))
      return
    end

    local ckeys = keysof(cval)
    local pkeys = keysof(pval)

    -- Empty spec object {} means object can be open (any keys).
    if #pkeys > 0 and getprop(pval, '`$OPEN`') ~= true then
      local badkeys = {}
      setmetatable(badkeys, {
        __jsontype = {
          type = 'array'
        }
      })

      for _, ckey in ipairs(ckeys) do
        if not haskey(pval, ckey) then
          table.insert(badkeys, ckey)
        end
      end

      -- Closed object, so reject extra keys not in shape.
      if #badkeys > 0 then
        local msg = 'Unexpected keys at ' .. pathify(state.path, 1) .. ': ' ..
                      table.concat(badkeys, ', ')
        table.insert(state.errs, msg)
      end
    else
      -- Object is open, so merge in extra keys.
      merge({pval, cval})
      if isnode(pval) then
        setprop(pval, '`$OPEN`', UNDEF)
      end
    end
  elseif islist(cval) then
    if not islist(pval) then
      table.insert(state.errs, _invalidTypeMsg(state.path, ptype, ctype, cval, 'V0030'))
    end
  else
    -- Spec value was a default, copy over data
    setprop(parent, key, cval)
  end

  return
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
validate = function(data, spec, extra, collecterrs)
  local errs = collecterrs or {}

  -- Create the store with validation functions and commands
  local store = {
    -- A special top level value to collect errors.
    ["$ERRS"] = errs,

    -- Remove the transform commands.
    ["$DELETE"] = nil,
    ["$COPY"] = nil,
    ["$KEY"] = nil,
    ["$META"] = nil,
    ["$MERGE"] = nil,
    ["$EACH"] = nil,
    ["$PACK"] = nil,

    -- Validation functions
    ["$STRING"] = validate_STRING,
    ["$NUMBER"] = validate_NUMBER,
    ["$BOOLEAN"] = validate_BOOLEAN,
    ["$OBJECT"] = validate_OBJECT,
    ["$ARRAY"] = validate_ARRAY,
    ["$FUNCTION"] = validate_FUNCTION,
    ["$ANY"] = validate_ANY,
    ["$CHILD"] = validate_CHILD,
    ["$ONE"] = validate_ONE,
    ["$EXACT"] = validate_EXACT
  }

  -- Merge in any extra validators/commands
  if extra then
    -- Check if extra is a table; if not, assume it's a string from a test
    if type(extra) == "table" then
      for k, v in pairs(extra) do
        store[k] = v
      end
    end
    -- If extra is not a table, simply ignore it
  end

  local out = transform(data, spec, store, _validation)

  if #errs > 0 and not collecterrs then
    error('Invalid data: ' .. table.concat(errs, ' | '))
  end

  return out
end


validate = function(data, spec, extra, collecterrs)
  local errs = collecterrs or {}

  -- Create the store with validation functions and commands
  local store = {
    -- A special top level value to collect errors.
    ["$ERRS"] = errs,

    -- Remove the transform commands.
    ["$DELETE"] = nil,
    ["$COPY"] = nil,
    ["$KEY"] = nil,
    ["$META"] = nil,
    ["$MERGE"] = nil,
    ["$EACH"] = nil,
    ["$PACK"] = nil,

    -- Validation functions
    ["$STRING"] = validate_STRING,
    ["$NUMBER"] = validate_NUMBER,
    ["$BOOLEAN"] = validate_BOOLEAN,
    ["$OBJECT"] = validate_OBJECT,
    ["$ARRAY"] = validate_ARRAY,
    ["$FUNCTION"] = validate_FUNCTION,
    ["$ANY"] = validate_ANY,
    ["$CHILD"] = validate_CHILD,
    ["$ONE"] = validate_ONE,
    ["$EXACT"] = validate_EXACT
  }

  -- Merge in any extra validators/commands
  if extra then
    -- Check if extra is a table; if not, assume it's a string from a test
    if type(extra) == "table" then
      for k, v in pairs(extra) do
        store[k] = v
      end
    end
    -- If extra is not a table, simply ignore it
  end

  local out = transform(data, spec, store, _validation)

  if #errs > 0 and not collecterrs then
    error('Invalid data: ' .. table.concat(errs, ' | '))
  end

  return out
end

----------------------------------------------------------
-- Module Export
----------------------------------------------------------

return {
  clone = clone,
  escre = escre,
  escurl = escurl,
  getpath = getpath,
  getprop = getprop,
  strkey = strkey,
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
  setprop = setprop,
  stringify = stringify,
  transform = transform,
  validate = validate,
  typify = typify,
  walk = walk,
  pathify = pathify
}
