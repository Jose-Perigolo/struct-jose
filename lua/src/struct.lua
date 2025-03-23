-- Copyright (c) 2025 Voxgig Ltd. MIT LICENSE.
-- Voxgig Struct
-- =============
--
-- Utility functions to manipulate in-memory JSON-like data
-- structures. These structures assumed to be composed of nested
-- "nodes", where a node is a list or map, and has named or indexed
-- fields.  The general design principle is "by-example". Transform
-- specifications mirror the desired output. This implementation is
-- designed for porting to multiple language, and to be tolerant of
-- undefined values.
--
-- Main utilities
-- - getpath: get the value at a key path deep inside an object.
-- - merge: merge multiple nodes, overriding values in earlier nodes.
-- - walk: walk a node tree, applying a function at each node and leaf.
-- - inject: inject values from a data store into a new data structure.
-- - transform: transform a data structure to an example structure.
-- - validate: validate a data structure against a shape specification.
--
-- Minor utilities
-- - isnode, islist, ismap, iskey, isfunc: identify value kinds.
-- - isempty: undefined values, or empty nodes.
-- - keysof: sorted list of node keys (ascending).
-- - haskey: true if key value is defined.
-- - clone: create a copy of a JSON-like data structure.
-- - items: list entries of a map or list as [key, value] pairs.
-- - getprop: safely get a property value by key.
-- - setprop: safely set a property value by key.
-- - stringify: human-friendly string version of a value.
-- - escre: escape a regular expresion string.
-- - escurl: escape a url.
-- - joinurl: join parts of a url, merging forward slashes.
--
-- This set of functions and supporting utilities is designed to work
-- uniformly across many languages, meaning that some code that may be
-- functionally redundant in specific languages is still retained to
-- keep the code human comparable.
--
-- NOTE: In this code JSON nulls are in general *not* considered the
-- same as undefined values in the given language. However most
-- JSON parsers do use the undefined value to represent JSON
-- null. This is ambiguous as JSON null is a separate value, not an
-- undefined value. You should convert such values to a special value
-- to represent JSON null, if this ambiguity creates issues
-- (thankfully in most APIs, JSON nulls are not used). For example,
-- the unit tests use the string "__NULL__" where necessary.
-- 
-- String constants are explicitly defined.
local S_MKEYPRE = 'key:pre'
local S_MKEYPOST = 'key:post'
local S_MVAL = 'val'
local S_MKEY = 'key'

-- Special keys.

local S_DKEY = '`$KEY`'
local S_DMETA = '`$META`'
local S_DTOP = '$TOP'
local S_DERRS = '$ERRS'

-- General strings.

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

-- The standard undefined value for this language.
local UNDEF = nil

-- Value is a defined list (array) with integer keys (indexes).
local function islist(val)
  -- Check if it's a table
  if type(val) ~= "table" or
    (getmetatable(val) and getmetatable(val).__jsontype == "object") then
    return false
  end

  if getmetatable(val) and getmetatable(val).__jsontype == "array" then
    return true
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
function ismap(val)
  -- Check if the value is a table
  if type(val) ~= "table" or
    (getmetatable(val) and getmetatable(val).__jsontype == "array") then
    return false
  end

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
local function isnode(val)
  if val == nil then
    return false
  end

  return ismap(val) or islist(val)
end

-- Value is a defined string (non-empty) or integer key.
local function iskey(key)
  local keytype = type(key)
  return (keytype == S_string and key ~= S_MT and key ~= S_null) or keytype ==
           S_number
end

-- Check for an "empty" value - nil, empty string, array, object.
function isempty(val)
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
local function isfunc(val)
  return type(val) == 'function'
end

-- Determine the type of a value as a string.
-- Returns one of: 'null', 'string', 'number', 'boolean', 'function', 'array', 'object'
-- Normalizes and simplifies Lua's type system for consistency.
function typify(value)
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
    -- In Lua, we need to distinguish between arrays and objects
    -- Check if the table has sequential numeric keys starting from 1
    local isArray = true
    local count = 0

    for k, _ in pairs(value) do
      if type(k) == "number" and k == math.floor(k) and k > 0 then
        count = count + 1
      else
        isArray = false
        break
      end
    end

    -- Check if all numeric keys are sequential
    if isArray and count > 0 then
      for i = 1, count do
        if value[i] == nil then
          isArray = false
          break
        end
      end
    end

    return isArray and "array" or "object"
  end

  -- For any other types (thread, userdata), return "object"
  return "object"
end

-- Safely get a property of a node. Nil arguments return nil.
-- If the key is not found, return the alternative value, if any.
function getprop(val, key, alt)
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

-- Sorted keys of a map, or indexes of a list.
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
local function haskey(val, key)
  return getprop(val, key) ~= UNDEF
end

-- Helper function to get sorted keys from a table
local function getKeys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

-- List the sorted keys of a map or list as an array of tuples of the form {key, value}
function items(val)
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

-- Escape regular expression.
local function escre(s)
  s = s or S_MT
  return s:gsub("([.*+?^${}%(%)%[%]\\|])", "\\%1")
end

-- Escape URLs.
local function escurl(s)
  s = s or S_MT
  -- Exact match for encodeURIComponent behavior
  return s:gsub("([^%w-_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

-- Concatenate url part strings, merging forward slashes as needed.
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

    -- Replace multiple slashes after non-slash with single slash
    s = s:gsub("([^/])/+", "%1/")

    if i == 1 then
      -- For first element, only remove trailing slashes
      s = s:gsub("/+$", "")
    else
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
function stringify(val, maxlen)
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
    local is_array = #obj > 0

    if is_array then
      -- Array-like tables
      for _, v in ipairs(obj) do
        table.insert(parts, serialize(v, seen))
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

-- Clone a JSON-like data structure.
-- NOTE: function value references are copied, *not* cloned.
function clone(val, flags)
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
-- Returns the (possible modified) parent.
-- If the value is undefined it the key will be deleted from the parent.
-- If the parent is a list, and the key is negative, prepend the value.
-- NOTE: If the key is above the list size, append the value; below, prepend.
-- If the value is undefined, remove the list element at index key, and shift the
-- remaining elements down. These rules avoids "holes" in the list.
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
      -- TypeScript: if (0 <= keyI && keyI < parent.length)
      -- For Lua: We need to handle keyI as a 0-based index coming from JS

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

      -- TypeScript: parent[parent.length < keyI ? parent.length : keyI] = val
      if #parent < luaIndex then
        -- If index is beyond current length, append to end
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

-- Build a human friendly path string.
local function pathify(val, from)
  local pathstr = UNDEF
  local path = UNDEF

  if islist(val) or ismap(val) then
    path = val
  elseif type(val) == 'string' then
    path = {val}
  elseif type(val) == 'number' then
    path = {val}
  end

  -- Calculate start index
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
      -- Filter valid path elements (strings and numbers)
      local filtered = {}
      for _, p in ipairs(path) do
        local t = type(p)
        if t == S_string or t == S_number then
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
          -- Replace dots with empty string for strings
          local replacedP = string.gsub(p, '%' .. S_DT, S_MT)
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

-- Walk a data structure depth first, applying a function to each value.
function walk(val, apply, -- These arguments are the public interface.
key, parent, path -- These arguments are used for recursive state.
)

  path = path or {}

  if isnode(val) then
    for _, item in ipairs(items(val)) do
      local ckey, child = item[1], item[2]
      local childPath = {}
      for _, p in ipairs(path) do
        table.insert(childPath, p)
      end
      table.insert(childPath, tostring(ckey))

      setprop(val, ckey, walk(child, apply, ckey, val, childPath))
    end
  end

  -- Nodes are applied *after* their children.
  -- For the root node, key and parent will be undefined.
  return apply(key, val, parent, path or {})
end

-- Merge a list of values into each other. Later values have
-- precedence. Nodes override scalars. Node kinds (list or map)
-- override each other, and do *not* merge. The first element is
-- modified.
function merge(val)
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
function getpath(path, store, current, state)
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

-- Inject store values into a string. Not a public utility - used by
-- `inject`.  Inject are marked with `path` where path is resolved
-- with getpath against the store or current (if defined)
-- arguments. See `getpath`.  Custom injection handling can be
-- provided by state.handler (this is used for transform functions).
-- The path can also have the special syntax $NAME999 where NAME is
-- upper case letters only, and 999 is any digits, which are
-- discarded. This syntax specifies the name of a transform, and
-- optionally allows transforms to be ordered by alphanumeric sorting.
function _injectstr(val, store, current, state)
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

-- Default inject handler for transforms. If the path resolves to a function,
-- call the function passing the injection state. This is how transforms operate.
local function injecthandler(state, val, current, ref, store)
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
    val = val(state, val, current, ref, store)
    -- Update parent with value. Ensures references remain in node tree.
  elseif S_MVAL == state.mode and state.full then
    setprop(state.parent, state.key, val)
  end

  return val
end

-- Inject values from a data store into a node recursively, resolving
-- paths against the store, or current if they are local. THe modify
-- argument allows custom modification of the result.  The state
-- (InjectState) argument is used to maintain recursive state.
function inject(val, store, modify, current, state)
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
      handler = injecthandler,
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

      local childpath = {unpack(state.path)}
      table.insert(childpath, nodekey)

      local childnodes = {unpack(state.nodes)}
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
        handler = injecthandler,
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

-- The transform_* functions are special command inject handlers (see Injector).

-- Delete a key from a map or list.
local function transform_DELETE(state)
  local key, parent = state.key, state.parent
  setprop(parent, key, UNDEF)
  return UNDEF
end

-- Copy value from source data.
function transform_COPY(state, _val, current)
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
local function transform_KEY(state, _val, current)
  local mode, path, parent = state.mode, state.path, state.parent

  -- Do nothing in val mode
  if mode ~= S_MVAL then
    return UNDEF
  end

  -- Key is defined by $KEY meta property
  local keyspec = getprop(parent, S_DKEY)
  if keyspec ~= UNDEF then
    setprop(parent, S_DKEY, UNDEF)
    return getprop(current, keyspec)
  end

  -- Key is defined within general purpose $META object
  return getprop(getprop(parent, S_DMETA), S_KEY, getprop(path, #path - 2))
end

-- Store meta data about a node.  Does nothing itself, just used by
-- other injectors, and is removed when called.
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

-- Convert a node to a list
-- Format: ['`$EACH`', '`source-path-of-node`', child-template]
local function transform_EACH(state, _val, current, _ref, store)
  local mode, keys, path, parent, nodes = state.mode, state.keys, state.path,
    state.parent, state.nodes

  -- Remove arguments to avoid spurious processing
  if keys then
    -- Keep only the first key ($EACH) to prevent processing the other args
    while #keys > 1 do
      table.remove(keys)
    end
  end

  if S_MVAL ~= mode then
    return UNDEF
  end

  -- Get arguments: ['`$EACH`', 'source-path', child-template]
  -- Note: JavaScript/TypeScript arrays are 0-indexed, but Lua arrays are 1-indexed
  -- So parent[1] in TS == parent[2] in Lua, parent[2] in TS == parent[3] in Lua
  local srcpath = parent[2]
  local child = clone(parent[3])

  -- Source data
  local src = getpath(srcpath, store, current, state)

  -- Find the target key and parent to update
  local tkey = path[#path - 1]
  local target = nodes[#nodes - 1]

  -- Create parallel data structures for source values and template values
  -- tcur will hold source data values
  -- tval will hold template values to be filled in
  local tcur = {}
  local tval = {}

  -- Clone the child template for each source value
  if islist(src) then
    -- For arrays, create a template clone for each item
    for i = 1, #src do
      -- Add template to output
      table.insert(tval, clone(child))

      -- Add source value to current using 0-based index (for JS compat)
      tcur[i - 1] = src[i]
    end

    -- Ensure tval is treated as an array
    setmetatable(tval, {
      __jsontype = "array"
    })

  elseif ismap(src) then
    -- For maps, create a template for each entry
    local items_array = items(src)

    for _, item in ipairs(items_array) do
      local k, v = item[1], item[2]

      -- Clone template and add metadata
      local cclone = clone(child)
      cclone[S_DMETA] = {
        KEY = k
      }

      -- Add template to output
      table.insert(tval, cclone)

      -- Add source value to current using original key
      tcur[k] = v
    end

    -- Ensure tval is treated as an array
    setmetatable(tval, {
      __jsontype = "array"
    })
  end

  -- Wrap tcur in a $TOP structure - this is crucial
  -- This matches both TypeScript and Go implementations
  local tcurrent = {
    [S_DTOP] = tcur
  }

  -- Build the substructure through injection
  -- This processes the templates with the source data
  tval = inject(tval, store, state.modify, tcurrent)

  -- Update the parent with the resulting list
  setprop(target, tkey, tval)

  -- Prevent callee from damaging first list entry (since we are in `val` mode)
  -- Return the first element (if any) or nil
  if #tval > 0 then
    return tval[1]
  end

  return UNDEF
end

-- Convert a node to a map
-- Format: { '`$PACK`':['`source-path`', child-template]}
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
  local tkey = path[#path - 2]
  local target = nodes[#path - 2] or nodes[#path - 1]

  -- Source data
  local src = getpath(srcpath, store, current, state)

  -- Prepare source as a list
  if islist(src) then
    -- Keep as is
  elseif ismap(src) then
    local entries = {}
    for k, v in pairs(src) do
      if v[S_DMETA] == UNDEF then
        v[S_DMETA] = {}
      end
      v[S_DMETA].KEY = k
      table.insert(entries, v)
    end
    src = entries
  else
    return UNDEF
  end

  if src == nil then
    return UNDEF
  end

  -- Get key if specified
  local childkey = getprop(child, S_DKEY)
  local keyname = childkey == UNDEF and keyprop or childkey
  setprop(child, S_DKEY, UNDEF)

  -- Build parallel target object
  local tval = {}
  for _, n in ipairs(src) do
    local kn = getprop(n, keyname)
    setprop(tval, kn, clone(child))
    local nchild = getprop(tval, kn)
    setprop(nchild, S_DMETA, getprop(n, S_DMETA))
  end

  -- Build parallel source object
  local tcurrent = {}
  for _, n in ipairs(src) do
    local kn = getprop(n, keyname)
    setprop(tcurrent, kn, n)
  end

  tcurrent = {
    ["$TOP"] = tcurrent
  }

  -- Build substructure
  tval = inject(tval, store, state.modify, tcurrent)

  setprop(target, tkey, tval)

  -- Drop transform key
  return UNDEF
end

-- Transform data using spec.
-- Only operates on static JSON-like data.
-- Arrays are treated as if they are objects with indices as keys.
function transform(data, -- Source data to transform into new data (original not mutated)
  spec, -- Transform specification; output follows this shape
  extra, -- Additional store of data and transforms
  modify -- Optionally modify individual values
)
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

-- Build a type validation error message
local function _invalidTypeMsg(path, type, vt, v)
  -- Deal with lua table type
  vt = islist(v) and vt == 'table' and S.array or vt
  v = stringify(v)
  return 'Expected ' .. type .. ' at ' .. _pathify(path) .. ', found ' ..
           (v ~= UNDEF and vt .. ': ' or '') .. v
end

-- A required string value. NOTE: Rejects empty strings.
local function validate_STRING(state, _val, current)
  local out = getprop(current, state.key)

  local t = type(out)
  if t == 'string' then
    if out == '' then
      table.insert(state.errs, 'Empty string at ' .. _pathify(state.path))
      return UNDEF
    else
      return out
    end
  else
    table.insert(state.errs, _invalidTypeMsg(state.path, S.string, t, out))
    return UNDEF
  end
end

-- A required number value (int or float)
local function validate_NUMBER(state, _val, current)
  local out = getprop(current, state.key)

  local t = type(out)
  if t ~= 'number' then
    table.insert(state.errs, _invalidTypeMsg(state.path, S.number, t, out))
    return UNDEF
  end

  return out
end

-- A required boolean value
local function validate_BOOLEAN(state, _val, current)
  local out = getprop(current, state.key)

  local t = type(out)
  if t ~= 'boolean' then
    table.insert(state.errs, _invalidTypeMsg(state.path, S.boolean, t, out))
    return UNDEF
  end

  return out
end

-- A required object (map) value (contents not validated)
local function validate_OBJECT(state, _val, current)
  local out = getprop(current, state.key)

  local t = type(out)

  if out == UNDEF or t ~= 'table' then
    table.insert(state.errs, _invalidTypeMsg(state.path, S.object, t, out))
    return UNDEF
  end

  return out
end

-- A required array (list) value (contents not validated)
local function validate_ARRAY(state, _val, current)
  local out = getprop(current, state.key)

  local t = type(out)
  if not islist(out) then
    table.insert(state.errs, _invalidTypeMsg(state.path, S.array, t, out))
    return UNDEF
  end

  return out
end

-- A required function value
local function validate_FUNCTION(state, _val, current)
  local out = getprop(current, state.key)

  local t = type(out)
  if t ~= 'function' then
    table.insert(state.errs, _invalidTypeMsg(state.path, S.func, t, out))
    return UNDEF
  end

  return out
end

-- Allow any value
local function validate_ANY(state, _val, current)
  local out = getprop(current, state.key)
  return out
end

-- Specify child values for map or list
-- Map syntax: {'`$CHILD`': child-template }
-- List syntax: ['`$CHILD`', child-template ]
local function validate_CHILD(state, _val, current)
  local mode, key, parent, keys, path = state.mode, state.key, state.parent,
    state.keys, state.path

  -- Setup data structures for validation by cloning child template

  -- Map syntax
  if mode == S.MKEYPRE then
    local child = getprop(parent, key)

    -- Get corresponding current object
    local pkey = path[#path - 1]
    local tval = getprop(current, pkey)

    if tval == UNDEF then
      -- Create an empty object as default
      tval = {}
    elseif not ismap(tval) then
      table.insert(state.errs,
        _invalidTypeMsg({unpack(state.path, 1, #state.path - 1)}, S.object,
          type(tval), tval))
      return UNDEF
    end

    local ckeys = keysof(tval)
    for _, ckey in ipairs(ckeys) do
      setprop(parent, ckey, clone(child))

      -- NOTE: modifying state! This extends the child value loop in inject
      table.insert(keys, ckey)
    end

    -- Remove $CHILD to cleanup output
    setprop(parent, key, UNDEF)
    return UNDEF
    -- List syntax
  elseif mode == S.MVAL then
    if not islist(parent) then
      -- $CHILD was not inside a list
      table.insert(state.errs, 'Invalid $CHILD as value')
      return UNDEF
    end

    local child = parent[2]

    if current == UNDEF then
      -- Empty list as default
      for i = 1, #parent do
        parent[i] = UNDEF
      end
      return UNDEF
    elseif not islist(current) then
      table.insert(state.errs,
        _invalidTypeMsg({unpack(state.path, 1, #state.path - 1)}, S.array,
          type(current), current))
      state.keyI = #parent
      return current
      -- Clone children and reset state key index
      -- The inject child loop will now iterate over the cloned children,
      -- validating them against the current list values
    else
      for i = 1, #current do
        parent[i] = clone(child)
      end
      for i = #current + 1, #parent do
        parent[i] = UNDEF
      end
      state.keyI = 1
      return current[1]
    end
  end

  return UNDEF
end

-- Match at least one of the specified shapes
-- Syntax: ['`$ONE`', alt0, alt1, ...]
local function validate_ONE(state, _val, current)
  local mode, parent, path, nodes = state.mode, state.parent, state.path,
    state.nodes

  -- Only operate in val mode, since parent is a list
  if mode == S.MVAL then
    state.keyI = #state.keys

    -- Shape alts
    local tvals = {}
    for i = 2, #parent do
      table.insert(tvals, parent[i])
    end

    -- See if we can find a match
    for _, tval in ipairs(tvals) do
      -- If match, then errs length = 0
      local terrs = {}
      validate(current, tval, UNDEF, terrs)

      -- The parent is the list we are inside. Go up one level
      -- to set the actual value
      local grandparent = nodes[#nodes - 1]
      local grandkey = path[#path - 1]

      if isnode(grandparent) then
        -- Accept current value if there was a match
        if #terrs == 0 then
          -- Ensure generic type validation (in validate "modify") passes
          setprop(grandparent, grandkey, current)
          return
          -- Ensure generic validation does not generate a spurious error
        else
          setprop(grandparent, grandkey, UNDEF)
        end
      end
    end

    -- There was no match
    local valdesc = {}
    for _, v in ipairs(tvals) do
      table.insert(valdesc, stringify(v))
    end

    -- Replace `$NAME` with name
    local valDescStr = table.concat(valdesc, ', '):gsub('`%$([A-Z]+)`',
      function(p1)
        return string.lower(p1)
      end)

    table.insert(state.errs,
      _invalidTypeMsg({unpack(state.path, 1, #state.path - 1)},
        'one of ' .. valDescStr, type(current), current))
  end
end

-- This is the "modify" argument to inject. Use this to perform
-- generic validation. Runs *after* any special commands.
local function validation(val, key, parent, state, current, _store)
  -- Current val to verify
  local cval = getprop(current, key)

  if cval == UNDEF or state == UNDEF then
    return UNDEF
  end

  local pval = getprop(parent, key)
  local t = type(pval)

  -- Delete any special commands remaining
  if t == 'string' and pval:find(S.DS) then
    return UNDEF
  end

  local ct = type(cval)

  -- Type mismatch
  if t ~= ct and pval ~= UNDEF then
    table.insert(state.errs, _invalidTypeMsg(state.path, t, ct, cval))
    return UNDEF
  elseif ismap(cval) then
    if not ismap(val) then
      table.insert(state.errs, _invalidTypeMsg(state.path,
        islist(val) and S.array or t, ct, cval))
      return UNDEF
    end

    local ckeys = keysof(cval)
    local pkeys = keysof(pval)

    -- Empty spec object {} means object can be open (any keys)
    if #pkeys > 0 and getprop(pval, '`$OPEN`') ~= true then
      local badkeys = {}
      for _, ckey in ipairs(ckeys) do
        if not haskey(val, ckey) then
          table.insert(badkeys, ckey)
        end
      end

      -- Closed object, so reject extra keys not in shape
      if #badkeys > 0 then
        table.insert(state.errs,
          'Unexpected keys at ' .. _pathify(state.path) .. ': ' ..
            table.concat(badkeys, ', '))
      end
    else
      -- Object is open, so merge in extra keys
      merge({pval, cval})
      if isnode(pval) then
        pval['`$OPEN`'] = UNDEF
      end
    end
  elseif islist(cval) then
    if not islist(val) then
      table.insert(state.errs, _invalidTypeMsg(state.path, t, ct, cval))
    end
  else
    -- Spec value was a default, copy over data
    setprop(parent, key, cval)
  end

  return UNDEF
end

-- Validate a data structure against a shape specification. The shape
-- specification follows the "by example" principle. Plain data in
-- the shape is treated as default values that also specify the
-- required type. Thus shape {a=1} validates {a=2}, since the types
-- (number) match, but not {a='A'}. Shape {a=1} against data {}
-- returns {a=1} as a=1 is the default value of the a key. Special
-- validation commands (in the same syntax as transform) are also
-- provided to specify required values. Thus shape {a='`$STRING`'}
-- validates {a='A'} but not {a=1}. Empty map or list means the node
-- is open, and if missing an empty default is inserted.
local function validate(data, -- Source data to transform into new data (original not mutated)
  spec, -- Transform specification; output follows this shape
  extra, -- Additional custom checks
  collecterrs -- Optionally collect errors
)
  local errs = collecterrs or {}
  local out = transform(data, spec, {
    -- A special top level value to collect errors
    [S.DERRS] = errs,

    -- Remove the transform commands
    [S.DS .. 'DELETE'] = UNDEF,
    [S.DS .. 'COPY'] = UNDEF,
    [S.DS .. 'KEY'] = UNDEF,
    [S.DS .. 'META'] = UNDEF,
    [S.DS .. 'MERGE'] = UNDEF,
    [S.DS .. 'EACH'] = UNDEF,
    [S.DS .. 'PACK'] = UNDEF,

    [S.DS .. 'STRING'] = validate_STRING,
    [S.DS .. 'NUMBER'] = validate_NUMBER,
    [S.DS .. 'BOOLEAN'] = validate_BOOLEAN,
    [S.DS .. 'OBJECT'] = validate_OBJECT,
    [S.DS .. 'ARRAY'] = validate_ARRAY,
    [S.DS .. 'FUNCTION'] = validate_FUNCTION,
    [S.DS .. 'ANY'] = validate_ANY,
    [S.DS .. 'CHILD'] = validate_CHILD,
    [S.DS .. 'ONE'] = validate_ONE
  }, validation)

  if #errs > 0 and collecterrs == UNDEF then
    error('Invalid data: ' .. table.concat(errs, '\n'))
  end

  return out
end

-- Define the module exports
return {
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
  setprop = setprop,
  stringify = stringify,
  transform = transform,
  validate = validate,
  walk = walk,
  pathify = pathify
}
