-- Copyright (c) 2025 Voxgig Ltd. MIT LICENSE.

-- Voxgig Struct
-- =============
--
-- Utility functions to manipulate in-memory JSON-like data
-- structures. These structures assumed to be composed of nested
-- "nodes", where a node is a list or map, and has named or indexed
-- fields.  The general design principle is "by-example". Transform
-- specifications mirror the desired output.  This implementation is
-- designed for porting to multiple language, and to be tolerant of
-- undefined values.
--
-- Main utilities
-- - getpath: get the value at a key path deep inside an object.
-- - merge: merge multiple nodes, overriding values in earlier nodes.
-- - walk: walk a node tree, applying a function at each node and leaf.
-- - inject: inject values from a data store into a new data structure.
-- - transform: transform a data structure to an example structure.
-- - validate: valiate a data structure against a shape specification.
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

-- String constants are explicitly defined.
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

-- Forward declarations for functions that need to reference each other
local _injectstr
local injecthandler
local inject
local _pathify
local getpath
local walk

local function print_table(t)
  for k, v in pairs(t) do
    print(k, v)
  end
end

-- Value is a node - defined, and a map (hash) or list (array).
local function isnode(val)
  return val ~= UNDEF and type(val) == 'table'
end


-- Value is a defined list (array) with integer keys (indexes).
local function islist(val)
  -- Check if it's a table
  if type(val) ~= "table" then
    return false
  end

  -- Count total elements and max integer key
  local count = 0
  local max = 0
  for k, _ in pairs(val) do
    if type(k) == "number" then
      if k > max then max = k end
      count = count + 1
    end
  end

  -- Check if all keys are consecutive integers starting from 1
  return count > 0 and max == count
end

-- Value is a defined map (hash) with string keys.
local function ismap(val)
  return isnode(val) and not islist(val)
end

-- Value is a defined string (non-empty) or integer key.
local function iskey(key)
  local keytype = type(key)
  return (keytype == 'string' and key ~= '') or keytype == 'number'
end

-- Check for an "empty" value - undefined, empty string, array, object.
local function isempty(val)
  if val == UNDEF or val == '' then
    return true
  end

  if type(val) == 'table' then
    for _ in pairs(val) do
      return false -- If the table has any elements, it's not empty
    end
    return true    -- Table exists but has no elements
  end

  return false
end

-- Value is a function.
local function isfunc(val)
  return type(val) == 'function'
end

-- Safely get a property of a node. Undefined arguments return undefined.
-- If the key is not found, return the alternative value.
local function getprop(val, key, alt)
  if val == nil then
    return alt
  end

  if key == nil then
    return alt
  end

  local out = alt

  if isnode(val) then
    -- Check if we're dealing with an array-like table and a numeric index
    local isArray = #val > 0
    local isNumericKey = type(key) == "number" or (type(key) == "string" and tonumber(key) ~= nil)

    if isArray and isNumericKey then
      -- Convert from 0-based indexing to 1-based for arrays
      local numKey = type(key) == "number" and key or tonumber(key)
      if numKey >= 0 then     -- Only adjust non-negative indices
        out = val[numKey + 1] -- +1 for Lua's 1-based arrays
      end
    else
      -- Try the key as is
      out = val[key]

      -- If not found and key is a number, try as string
      if out == nil and type(key) == "number" then
        out = val[tostring(key)]
      end

      -- If not found and key is a string that looks like a number, try as number
      if out == nil and type(key) == "string" and tonumber(key) ~= nil then
        out = val[tonumber(key)]
      end
    end
  end

  if out == nil then
    out = alt
  end

  return out
end

-- Sorted keys of a map, or indexes of a list.
local function keysof(val)
  if not isnode(val) then
    return {}
  end

  if ismap(val) then
    local keys = {}
    for k, _ in pairs(val) do
      table.insert(keys, k)
    end
    table.sort(keys)
    return keys
  else
    local indexes = {}
    for i = 1, #val do
      table.insert(indexes, i)
    end
    return indexes
  end
end

-- Value of property with name key in node val is defined.
local function haskey(val, key)
  return getprop(val, key) ~= UNDEF
end

-- List the keys of a map or list as an array of tuples of the form {key, value}.
local function items(val)
  if ismap(val) then
    local result = {}
    local keys = {}

    -- Collect all keys
    for k, _ in pairs(val) do
      table.insert(keys, k)
    end

    -- Sort keys (for consistent ordering)
    table.sort(keys)

    -- Create sorted key-value pairs
    for _, k in ipairs(keys) do
      table.insert(result, { k, val[k] })
    end

    return result
  elseif islist(val) then
    local result = {}
    for i, v in ipairs(val) do
      -- Subtract 1 from index to match JavaScript's 0-based indexing
      table.insert(result, { i - 1, v })
    end
    return result
  else
    return {}
  end
end

-- Escape regular expression.
local function escre(s)
  s = s or S.empty
  return s:gsub("([.*+?^${}%(%)%[%]\\|])", "\\%1")
end

-- Escape URLs.
local function escurl(s)
  s = s or S.empty
  -- Exact match for encodeURIComponent behavior
  return s:gsub("([^%w-_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

-- Concatenate url part strings, merging forward slashes as needed.
local function joinurl(sarr)
  local result = {}

  for i, s in ipairs(sarr) do
    if s ~= UNDEF and s ~= '' then
      local part = s
      if i == 1 then
        part = s:gsub("([^/])/+", "%1/"):gsub("/+$", "")
      else
        part = s:gsub("([^/])/+", "%1/"):gsub("^/+", ""):gsub("/+$", "")
      end
      if part ~= '' then
        table.insert(result, part)
      end
    end
  end

  return table.concat(result, "/")
end

-- Safely stringify a value for printing (NOT JSON!).
local function stringify(val, maxlen)
  local function stringifyTable(t, visited)
    visited = visited or {}

    -- Check for recursive references
    if visited[t] then
      return "<<recursive>>"
    end

    visited[t] = true

    -- Check if table is array-like
    local isArray = true
    local maxIndex = 0

    for k, _ in pairs(t) do
      if type(k) ~= 'number' or k <= 0 or k ~= math.floor(k) then
        isArray = false
        break
      end
      maxIndex = math.max(maxIndex, k)
    end

    -- Count actual elements
    local count = 0
    for _ in pairs(t) do count = count + 1 end

    -- If array-like (sequential keys from 1 to n)
    if isArray and count == maxIndex then
      local items = {}
      for i = 1, count do
        local v = t[i]
        if type(v) == 'table' then
          table.insert(items, stringifyTable(v, visited))
        elseif type(v) == 'string' then
          table.insert(items, v)
        else
          table.insert(items, tostring(v))
        end
      end
      return '[' .. table.concat(items, ',') .. ']'
    else
      -- Format as object
      local items = {}
      local sortedKeys = {}
      for k, _ in pairs(t) do
        table.insert(sortedKeys, k)
      end
      table.sort(sortedKeys)

      for _, k in ipairs(sortedKeys) do
        local v = t[k]
        local valStr
        if type(v) == 'table' then
          valStr = stringifyTable(v, visited)
        elseif type(v) == 'string' then
          valStr = v
        else
          valStr = tostring(v)
        end
        table.insert(items, tostring(k) .. ':' .. valStr)
      end
      return '{' .. table.concat(items, ',') .. '}'
    end
  end

  local json = S.empty

  if type(val) == 'table' then
    json = stringifyTable(val)
  else
    json = tostring(val)
  end

  json = type(json) ~= 'string' and tostring(json) or json
  json = json:gsub('"', '')

  if maxlen ~= nil then
    if #json > maxlen then
      json = json:sub(1, maxlen - 3) .. '...'
    end
  end

  return json
end

-- Clone a JSON-like data structure.
-- NOTE: function value references are copied, *not* cloned.
local function clone(val)
  if val == UNDEF then
    return UNDEF
  end

  if type(val) ~= 'table' then
    return val
  end

  local result = {}
  local refs = {}

  local function deepCopy(obj)
    if type(obj) ~= 'table' then
      return obj
    end

    if refs[obj] then
      return refs[obj]
    end

    local copy = {}
    refs[obj] = copy

    for k, v in pairs(obj) do
      if type(v) == 'table' then
        copy[k] = deepCopy(v)
      else
        copy[k] = v
      end
    end

    return copy
  end

  return deepCopy(val)
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

-- Convert a path string or array to a printable string
function _pathify(val, from)
  from = from or 1
  if type(val) == 'table' and islist(val) then
    local path = {}
    for i = from, #val do
      table.insert(path, val[i])
    end
    if #path == 0 then
      return '<root>'
    end
    return table.concat(path, '.')
  end
  return val == UNDEF and '<unknown-path>' or stringify(val)
end

-- Walk a data structure depth first, applying a function to each value.
function walk(
-- These arguments are the public interface.
    val,
    apply,

    -- These arguments are used for recursive state.
    key,
    parent,
    path
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
local function merge(objs)
  -- Handle cases of empty inputs
  if objs == UNDEF then
    return UNDEF
  end

  -- Check if it's an empty table
  if type(objs) == 'table' then
    local isEmpty = true
    for _ in pairs(objs) do
      isEmpty = false
      break
    end
    if isEmpty then
      return UNDEF -- Empty table/array should return nil
    end
  end

  -- Handle basic edge cases
  if not islist(objs) then
    -- Special case for sparse arrays (tables with only numeric keys)
    if type(objs) == 'table' then
      local hasNumericKeys = false
      local hasNonNumericKeys = false

      for k, _ in pairs(objs) do
        if type(k) == 'number' then
          hasNumericKeys = true
        else
          hasNonNumericKeys = true
        end
      end

      -- If all keys are numeric, treat it as a sparse array
      if hasNumericKeys and not hasNonNumericKeys then
        local keys = {}
        for k, _ in pairs(objs) do
          table.insert(keys, k)
        end
        table.sort(keys)

        -- Start with first value or empty table
        local out = objs[keys[1]] or {}

        -- Process remaining keys in order
        for i = 2, #keys do
          local key = keys[i]
          local obj = objs[key]

          if obj == nil then
            -- Skip nil values
          elseif not isnode(obj) then
            -- Non-nodes win over anything
            out = obj
          else
            -- Nodes win, also over nodes of a different kind
            if not isnode(out) or
                (ismap(obj) and islist(out)) or
                (islist(obj) and ismap(out)) or
                (isnode(out) and isempty(out) and not isempty(obj)) then
              out = obj
            else
              -- Deep merge for nodes of same type
              local cur = { out }
              local cI = 0

              local function merger(key, val, parent, path)
                if key == nil then
                  return val
                end

                -- Get the current value at the current path in obj.
                local lenpath = #path
                cI = lenpath
                if cur[cI] == UNDEF then
                  cur[cI] = getpath(
                    table.pack(table.unpack(path, 1, lenpath - 1)),
                    out
                  )
                end

                -- Create node if needed.
                if not isnode(cur[cI]) then
                  cur[cI] = islist(parent) and {} or {}
                end

                -- Node child is just ahead of us on the stack, since
                -- `walk` traverses leaves before nodes.
                if isnode(val) and not isempty(val) then
                  setprop(cur[cI], key, cur[cI + 1])
                  cur[cI + 1] = UNDEF
                else
                  setprop(cur[cI], key, val)
                end

                return val
              end

              -- Walk overriding node, creating paths in output as needed.
              walk(obj, merger)
            end
          end
        end

        return out
      end
    end

    return objs
  elseif #objs == 0 then
    return UNDEF
  elseif #objs == 1 then
    -- If the only item is an empty table, return nil
    if isnode(objs[1]) and isempty(objs[1]) then
      return UNDEF
    end
    return objs[1]
  end

  -- Merge a list of values (normal case for regular arrays).
  local out = getprop(objs, 0, {})

  -- Start with first entry of the array
  if islist(objs) and #objs > 0 then
    out = objs[1]
  end

  for oI = 2, #objs do
    local obj = objs[oI]

    -- Skip nil values
    if obj == UNDEF then
      -- Skip but do nothing (retain existing values)
      -- Handle empty arrays - don't override values with empty arrays
    elseif islist(obj) and #obj == 0 then
      -- Skip but do nothing (retain existing values)
    elseif not isnode(obj) then
      -- Non-nodes win.
      out = obj
    else
      -- Nodes win, also over nodes of a different kind.
      if not isnode(out) or
          (ismap(obj) and islist(out) and not isempty(obj)) or
          (islist(obj) and ismap(out) and not isempty(obj)) or
          (isnode(out) and isempty(out) and not isempty(obj)) then
        out = obj
      else
        -- Node stack. walking down the current obj.
        local cur = { out }
        local cI = 0

        local function merger(key, val, parent, path)
          if key == nil then
            return val
          end

          -- Get the current value at the current path in obj.
          local lenpath = #path
          cI = lenpath
          if cur[cI] == UNDEF then
            cur[cI] = getpath(
              table.pack(table.unpack(path, 1, lenpath - 1)),
              out
            )
          end

          -- Create node if needed.
          if not isnode(cur[cI]) then
            cur[cI] = islist(parent) and {} or {}
          end

          -- Node child is just ahead of us on the stack, since
          -- `walk` traverses leaves before nodes.
          if isnode(val) and not isempty(val) then
            setprop(cur[cI], key, cur[cI + 1])
            cur[cI + 1] = UNDEF
          else
            setprop(cur[cI], key, val)
          end

          return val
        end

        -- Walk overriding node, creating paths in output as needed.
        walk(obj, merger)
      end
    end
  end

  return out
end

-- Get a value deep inside a node using a key path.
-- For example the path `a.b` gets the value 1 from {a:{b:1}}.
-- The path can specified as a dotted string, or a string array.
-- If the path starts with a dot (or the first element is ''), the path is considered local,
-- and resolved against the `current` argument, if defined.
-- Integer path parts are used as array indexes.
-- The state argument allows for custom handling when called from `inject` or `transform`.
function getpath(path, store, current, state, skipHandler)
  -- Operate on a string array
  local parts
  if type(path) == 'table' and islist(path) then
    parts = path
  elseif type(path) == 'string' then
    parts = {}
    for part in string.gmatch(path, '([^' .. S.DT .. ']+)') do
      table.insert(parts, part)
    end
    if path:sub(1, 1) == S.DT then
      table.insert(parts, 1, '')
    end
  else
    return UNDEF
  end

  local root = store
  local val = store

  -- An empty path (incl empty string) just finds the store
  if path == UNDEF or store == UNDEF or (#parts == 1 and parts[1] == '') then
    -- The actual store data may be in a store sub property, defined by state.base
    val = getprop(store, getprop(state, S.base), store)
  elseif #parts > 0 then
    local pI = 1

    -- Relative path uses `current` argument
    if parts[1] == '' then
      pI = 2
      root = current
    end

    local part = pI <= #parts and parts[pI] or UNDEF
    local first = getprop(root, part)

    -- At top level, check state.base, if provided
    if first == UNDEF and pI == 1 then
      val = getprop(getprop(root, getprop(state, S.base)), part)
    else
      val = first
    end

    -- Move along the path, trying to descend into the store
    for i = pI + 1, #parts do
      if val == UNDEF then break end
      val = getprop(val, parts[i])
    end
  end

  -- State may provide a custom handler to modify found value
  if not skipHandler and state ~= UNDEF and isfunc(state.handler) then
    -- Create and prepare wrapper handler that protects against Lua concatenation errors
    local safe_handler = function(...)
      local args = { ... }
      -- Convert the val argument (args[2]) to string if it's a table
      if type(args[2]) == 'table' then
        -- For a table with a single value (like {'$TOP':'12'}), extract that value
        local key, value = next(args[2])
        if key ~= nil and next(args[2], key) == nil then
          -- Only one key/value pair exists
          args[2] = value
        else
          -- Otherwise convert to string representation
          args[2] = tostring(args[2])
        end
      end
      return state.handler(table.unpack(args))
    end

    val = safe_handler(state, val, current, _pathify(path), store)
  end

  return val
end

-- Inject store values into a string. Not a public utility - used by `inject`.
-- Inject are marked with `path` where path is resolved with getpath against the
-- store or current (if defined) arguments. See `getpath`.
-- Custom injection handling can be provided by state.handler (this is used for
-- transform functions).
-- The path can also have the special syntax $NAME999 where NAME is upper case letters only,
-- and 999 is any digits, which are discarded. This syntax specifies the name of a transform,
-- and optionally allows transforms to be ordered by alphanumeric sorting.
-- Modified _injectstr function
function _injectstr(val, store, current, state)
  -- Can't inject into non-strings
  if type(val) ~= 'string' then
    return ''
  end

  -- Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`"
  -- local m = { val:match("^`([$][A-Z]+|[^`]+)[0-9]*`$") }

  -- Full string of the val is an injection
  -- if m[1] then
  --   if state then
  --     state.full = true
  --   end
  --   local pathref = m[1]

  -- Check for full injection pattern: `path`
  if val:match("^`[^`]+`$") then
    if state then
      state.full = true
    end
    -- Extract the path without the backticks
    local pathref = val:sub(2, -2)

    -- Special escapes inside injection
    if #pathref > 3 then
      pathref = pathref:gsub("%$BT", S.BT):gsub("%$DS", S.DS)
    end

    -- Get the extracted path reference directly without any string conversion
    return getpath(pathref, store, current, state)
  end

  -- Check for injections within the string
  local out = val:gsub("`([^`]+)`", function(ref)
    -- Special escapes inside injection
    if #ref > 3 then
      ref = ref:gsub("%$BT", S.BT):gsub("%$DS", S.DS)
    end

    if state then
      state.full = false
    end

    local found = getpath(ref, store, current, state)

    -- For partial injections we do need to convert to string
    if found == nil then
      return ''
    elseif type(found) == 'table' then
      -- Simple table to JSON string conversion
      local json = '{'
      local items = {}
      for k, v in pairs(found) do
        if type(v) == 'string' then
          table.insert(items, '"' .. tostring(k) .. '":"' .. v .. '"')
        else
          table.insert(items, '"' .. tostring(k) .. '":' .. tostring(v))
        end
      end
      json = json .. table.concat(items, ',') .. '}'
      return json
    else
      return tostring(found)
    end
  end)

  -- Also call the state handler on the entire string, providing the
  -- option for custom injection
  if state and state.handler then
    state.full = true
    out = state.handler(state, out, current, val, store)
  end

  return out
end

-- Default inject handler for transforms. If the path resolves to a function,
-- call the function passing the injection state. This is how transforms operate.
function injecthandler(state, val, current, ref, store)
  local out = val

  -- Only call val function if it is a special command ($NAME format)
  if isfunc(val) and
      (ref == nil or (type(ref) == 'string' and ref:sub(1, 1) == S.DS)) then
    out = val(state, val, current, store)
    -- Update parent with value. Ensures references remain in node tree
  elseif state.mode == S.MVAL and state.full then
    setprop(state.parent, state.key, val)
  end

  return out
end

-- Inject values from a data store into a node recursively, resolving paths against the store,
-- or current if they are local. The modify argument allows custom modification of the result.
-- The state argument is used to maintain recursive state.
function inject(val, store, modify, current, state)
  local valtype = type(val)

  -- Create state if at root of injection
  -- The input value is placed inside a virtual parent holder
  -- to simplify edge cases
  if state == nil then
    local parent = {}
    parent[S.DTOP] = val

    -- Set up state assuming we are starting in the virtual parent
    state = {
      mode = S.MVAL,
      full = false,
      keyI = 1,
      keys = { S.DTOP },
      key = S.DTOP,
      val = val,
      parent = parent,
      path = { S.DTOP },
      nodes = { parent },
      handler = injecthandler,
      base = S.DTOP,
      modify = modify,
      errs = getprop(store, S.DERRS, {}),
      meta = {},
    }
  end

  -- Resolve current node in store for local paths
  if current == nil then
    current = { [S.DTOP] = store }
  else
    local parentkey = state.path[#state.path - 1]
    current = parentkey == nil and current or getprop(current, parentkey)
  end

  -- Descend into node
  if isnode(val) then
    -- Keys are sorted alphanumerically to ensure determinism
    -- Injection transforms ($FOO) are processed *after* other keys
    -- NOTE: the optional digits suffix of the transform can thus be used to
    -- order the transforms
    local origkeys = {}
    if ismap(val) then
      local nonDSKeys = {}
      local dsKeys = {}

      for k, _ in pairs(val) do
        if not string.find(tostring(k), S.DS) then
          table.insert(nonDSKeys, k)
        else
          table.insert(dsKeys, k)
        end
      end

      table.sort(dsKeys)
      for _, k in ipairs(nonDSKeys) do
        table.insert(origkeys, k)
      end
      for _, k in ipairs(dsKeys) do
        table.insert(origkeys, k)
      end
    else
      for i = 1, #val do
        table.insert(origkeys, i)
      end
    end

    -- Each child key-value pair is processed in three injection phases:
    -- 1. state.mode='key:pre' - Key string is injected, returning a possibly altered key
    -- 2. state.mode='val' - The child value is injected
    -- 3. state.mode='key:post' - Key string is injected again, allowing child mutation
    local okI = 1
    while okI <= #origkeys do
      local origkey = tostring(origkeys[okI])

      local childpath = {}
      for _, p in ipairs(state.path or {}) do
        table.insert(childpath, p)
      end
      table.insert(childpath, origkey)

      local childnodes = {}
      for _, n in ipairs(state.nodes or {}) do
        table.insert(childnodes, n)
      end
      table.insert(childnodes, val)

      local childstate = {
        mode = S.MKEYPRE,
        full = false,
        keyI = okI,
        keys = origkeys,
        key = origkey,
        val = val,
        parent = val,
        path = childpath,
        nodes = childnodes,
        handler = injecthandler,
        base = state.base,
        errs = state.errs,
        meta = state.meta,
      }

      -- Perform the key:pre mode injection on the child key
      local prekey = _injectstr(origkey, store, current, childstate)

      -- The injection may modify child processing
      okI = childstate.keyI

      -- Prevent further processing by returning an undefined prekey
      if prekey ~= nil then
        local child = getprop(val, prekey)
        childstate.mode = S.MVAL

        -- Perform the val mode injection on the child value
        -- NOTE: return value is not used
        inject(child, store, modify, current, childstate)

        -- The injection may modify child processing
        okI = childstate.keyI

        -- Perform the key:post mode injection on the child key
        childstate.mode = S.MKEYPOST
        _injectstr(origkey, store, current, childstate)

        -- The injection may modify child processing
        okI = childstate.keyI
      end

      okI = okI + 1
    end
    -- Inject paths into string scalars
  elseif valtype == 'string' then
    state.mode = S.MVAL
    local newval = _injectstr(val, store, current, state)
    val = newval

    setprop(state.parent, state.key, newval)
  end

  -- Custom modification
  if modify then
    modify(
      val,
      getprop(state, S.key),
      getprop(state, S.parent),
      state,
      current,
      store
    )
  end

  -- Original val reference may no longer be correct
  -- This return value is only used as the top level result
  return getprop(state.parent, S.DTOP)
end

-- Copy value from source data
local function transform_COPY(state, _val, current)
  local mode, key, parent = state.mode, state.key, state.parent

  local out
  if mode:sub(1, 3) == S.MKEY:sub(1, 3) then
    out = key
  else
    out = getprop(current, key)
    setprop(parent, key, out)
  end

  return out
end

-- As a value, inject the key of the parent node
-- As a key, define the name of the key property in the source object
local function transform_KEY(state, _val, current)
  local mode, path, parent = state.mode, state.path, state.parent

  -- Do nothing in val mode
  if mode ~= S.MVAL then
    return UNDEF
  end

  -- Key is defined by $KEY meta property
  local keyspec = getprop(parent, S.DKEY)
  if keyspec ~= UNDEF then
    setprop(parent, S.DKEY, UNDEF)
    return getprop(current, keyspec)
  end

  -- Key is defined within general purpose $META object
  return getprop(getprop(parent, S.DMETA), S.KEY, getprop(path, #path - 1))
end

-- Store meta data about a node
local function transform_META(state)
  local parent = state.parent
  setprop(parent, S.DMETA, UNDEF)
  return UNDEF
end

-- Merge a list of objects into the current object
-- Must be a key in an object. The value is merged over the current object.
-- If the value is an array, the elements are first merged using `merge`.
-- If the value is the empty string, merge the top level store.
-- Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
local function transform_MERGE(state, _val, store)
  local mode, key, parent = state.mode, state.key, state.parent

  if mode == S.MKEYPRE then return key end

  -- Operate after child values have been transformed
  if mode == S.MKEYPOST then
    local args = getprop(parent, key)
    args = args == '' and { store["$TOP"] } or (type(args) == 'table' and args or { args })

    -- Remove the $MERGE command
    setprop(parent, key, UNDEF)

    -- Literals in the parent have precedence, but we still merge onto
    -- the parent object, so that node tree references are not changed
    local mergelist = { parent }
    for _, arg in ipairs(args) do
      table.insert(mergelist, arg)
    end
    table.insert(mergelist, clone(parent))

    merge(mergelist)

    return key
  end

  return UNDEF
end

-- Convert a node to a list
-- Format: ['`$EACH`', '`source-path-of-node`', child-template]
local function transform_EACH(state, _val, current, store)
  local mode, keys, path, parent, nodes = state.mode, state.keys, state.path, state.parent, state.nodes

  -- Remove arguments to avoid spurious processing
  if keys then
    for i = 2, #keys do
      keys[i] = UNDEF
    end
  end

  -- Defensive context checks
  if mode ~= S.MVAL or path == UNDEF or nodes == UNDEF then
    return UNDEF
  end

  -- Get arguments
  local srcpath = parent[2]      -- Path to source data
  local child = clone(parent[3]) -- Child template

  -- Source data
  local src = getpath(srcpath, store, current, state)

  -- Create parallel data structures:
  -- source entries :: child templates
  local tcurrent = {}
  local tval = {}

  local tkey = path[#path - 1]
  local target = nodes[#path - 1] or nodes[#path]

  -- Create clones of the child template for each value of the current source
  if isnode(src) then
    if islist(src) then
      for i = 1, #src do
        table.insert(tval, clone(child))
      end
    else
      for k, _ in pairs(src) do
        local childClone = clone(child)
        -- Make a note of the key for $KEY transforms
        childClone[S.DMETA] = { KEY = k }
        table.insert(tval, childClone)
      end
    end

    -- Convert src to array of values
    for _, v in pairs(src) do
      table.insert(tcurrent, v)
    end
  end

  -- Parent structure
  tcurrent = { [S.DTOP] = tcurrent }

  -- Build the substructure
  tval = inject(
    tval,
    store,
    state.modify,
    tcurrent
  )

  setprop(target, tkey, tval)

  -- Prevent callee from damaging first list entry (since we are in `val` mode)
  return tval[1]
end

-- Convert a node to a map
-- Format: { '`$PACK`':['`source-path`', child-template]}
local function transform_PACK(state, _val, current, store)
  local mode, key, path, parent, nodes = state.mode, state.key, state.path, state.parent, state.nodes

  -- Defensive context checks
  if mode ~= S.MKEYPRE or type(key) ~= 'string' or path == UNDEF or nodes == UNDEF then
    return UNDEF
  end

  -- Get arguments
  local args = parent[key]
  local srcpath = args[1]      -- Path to source data
  local child = clone(args[2]) -- Child template

  -- Find key and target node
  local keyprop = child[S.DKEY]
  local tkey = path[#path - 1]
  local target = nodes[#path - 1] or nodes[#path]

  -- Source data
  local src = getpath(srcpath, store, current, state)

  -- Prepare source as a list
  if islist(src) then
    -- Keep as is
  elseif ismap(src) then
    local entries = {}
    for k, v in pairs(src) do
      if v[S.DMETA] == UNDEF then
        v[S.DMETA] = {}
      end
      v[S.DMETA].KEY = k
      table.insert(entries, v)
    end
    src = entries
  else
    return UNDEF
  end

  if src == UNDEF then
    return UNDEF
  end

  -- Get key if specified
  local childkey = getprop(child, S.DKEY)
  local keyname = childkey == UNDEF and keyprop or childkey
  setprop(child, S.DKEY, UNDEF)

  -- Build parallel target object
  local tval = {}
  for _, n in ipairs(src) do
    local kn = getprop(n, keyname)
    setprop(tval, kn, clone(child))
    local nchild = getprop(tval, kn)
    setprop(nchild, S.DMETA, getprop(n, S.DMETA))
  end

  -- Build parallel source object
  local tcurrent = {}
  for _, n in ipairs(src) do
    local kn = getprop(n, keyname)
    setprop(tcurrent, kn, n)
  end

  tcurrent = { [S.DTOP] = tcurrent }

  -- Build substructure
  tval = inject(
    tval,
    store,
    state.modify,
    tcurrent
  )

  setprop(target, tkey, tval)

  -- Drop transform key
  return UNDEF
end

-- Transform data using spec.
-- Only operates on static JSON-like data.
-- Arrays are treated as if they are objects with indices as keys.
local function transform(
    data,  -- Source data to transform into new data (original not mutated)
    spec,  -- Transform specification; output follows this shape
    extra, -- Additional store of data and transforms
    modify -- Optionally modify individual values
)
  -- Clone the spec so that the clone can be modified in place as the transform result
  spec = clone(spec)

  local extraTransforms = {}
  local extraData = {}

  if extra ~= UNDEF then
    for _, item in ipairs(items(extra)) do
      local k, v = item[1], item[2]
      if type(k) == 'string' and k:sub(1, 1) == S.DS then
        extraTransforms[k] = v
      else
        extraData[k] = v
      end
    end
  end

  local dataClone = merge({
    clone(extraData or {}),
    clone(data or {})
  })

  -- Define a top level store that provides transform operations
  local store = {
    -- The inject function recognizes this special location for the root of the source data
    -- NOTE: to escape data that contains "`$FOO`" keys at the top level,
    -- place that data inside a holding map: { myholder: mydata }
    [S.DTOP] = dataClone,

    -- Escape backtick (this also works inside backticks)
    [S.DS .. 'BT'] = function() return S.BT end,

    -- Escape dollar sign (this also works inside backticks)
    [S.DS .. 'DS'] = function() return S.DS end,

    -- Insert current date and time as an ISO string
    [S.DS .. 'WHEN'] = function()
      return os.date('!%Y-%m-%dT%H:%M:%S.000Z')
    end,

    [S.DS .. 'DELETE'] = transform_DELETE,
    [S.DS .. 'COPY'] = transform_COPY,
    [S.DS .. 'KEY'] = transform_KEY,
    [S.DS .. 'META'] = transform_META,
    [S.DS .. 'MERGE'] = transform_MERGE,
    [S.DS .. 'EACH'] = transform_EACH,
    [S.DS .. 'PACK'] = transform_PACK,
  }

  -- Add custom extra transforms, if any
  for k, v in pairs(extraTransforms) do
    store[k] = v
  end

  local out = inject(spec, store, modify, store)

  return out
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
  local mode, key, parent, keys, path = state.mode, state.key, state.parent, state.keys, state.path

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
      table.insert(state.errs, _invalidTypeMsg(
        { unpack(state.path, 1, #state.path - 1) }, S.object, type(tval), tval))
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
      table.insert(state.errs, _invalidTypeMsg(
        { unpack(state.path, 1, #state.path - 1) }, S.array, type(current), current))
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
  local mode, parent, path, nodes = state.mode, state.parent, state.path, state.nodes

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
    local valDescStr = table.concat(valdesc, ', '):gsub('`%$([A-Z]+)`', function(p1)
      return string.lower(p1)
    end)

    table.insert(state.errs, _invalidTypeMsg(
      { unpack(state.path, 1, #state.path - 1) },
      'one of ' .. valDescStr,
      type(current), current))
  end
end

-- Build a type validation error message
local function _invalidTypeMsg(path, type, vt, v)
  -- Deal with lua table type
  vt = islist(v) and vt == 'table' and S.array or vt
  v = stringify(v)
  return 'Expected ' .. type .. ' at ' .. _pathify(path) ..
      ', found ' .. (v ~= UNDEF and vt .. ': ' or '') .. v
end

-- This is the "modify" argument to inject. Use this to perform
-- generic validation. Runs *after* any special commands.
local function validation(
    val,
    key,
    parent,
    state,
    current,
    _store
)
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
      table.insert(state.errs, _invalidTypeMsg(state.path, islist(val) and S.array or t, ct, cval))
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
        table.insert(state.errs, 'Unexpected keys at ' .. _pathify(state.path) ..
          ': ' .. table.concat(badkeys, ', '))
      end
    else
      -- Object is open, so merge in extra keys
      merge({ pval, cval })
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
local function validate(
    data,       -- Source data to transform into new data (original not mutated)
    spec,       -- Transform specification; output follows this shape
    extra,      -- Additional custom checks
    collecterrs -- Optionally collect errors
)
  local errs = collecterrs or {}
  local out = transform(
    data,
    spec,
    {
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
      [S.DS .. 'ONE'] = validate_ONE,
    },
    validation
  )

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
}
