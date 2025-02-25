-- struct.lua
-- Copyright (c) 2025 Voxgig Ltd.
-- MIT LICENSE.
--
-- Voxgig Struct
-- =============
--
-- Utility functions to manipulate in‑memory JSON‑like data structures.
-- These structures are assumed to be composed of nested nodes (maps or lists).
-- Transform specifications mirror the desired output.
--
-- Main utilities:
--   getpath, merge, walk, inject, transform, validate
--
-- Minor utilities:
--   isnode, islist, ismap, iskey, isfunc, isempty, keysof, haskey,
--   clone, items, getprop, setprop, stringify, escre, escurl, joinurl

local struct = {}
local json = require("dkjson")  -- external JSON encoder/decoder

-- String constants.
local S = {
  MKEYPRE  = "key:pre",
  MKEYPOST = "key:post",
  MVAL     = "val",
  MKEY     = "key",
  DKEY     = "`$KEY`",
  DTOP     = "$TOP",
  DERRS    = "$ERRS",
  DMETA    = "`$META`",
  array    = "array",
  base     = "base",
  boolean  = "boolean",
  empty    = "",
  ["function"] = "function",
  number   = "number",
  object   = "object",
  string   = "string",
  key      = "key",
  parent   = "parent",
  BT       = "`",
  DS       = "$",
  DT       = ".",
  KEY      = "KEY",
}
struct.S = S

-- In this port, UNDEF is represented by nil.
local UNDEF = nil

-- isnode: returns true if val is defined and is a table.
function struct.isnode(val)
  return val ~= nil and type(val) == "table"
end

-- ismap: returns true if val is a table and not a list.
function struct.ismap(val)
  return val ~= nil and type(val) == "table" and (not struct.islist(val))
end

-- islist: heuristic check—val is a list if its keys are sequential positive integers.
function struct.islist(val)
  if type(val) ~= "table" then return false end
  local n = #val
  local count = 0
  for k, _ in pairs(val) do
    if type(k) == "number" and k >= 1 and math.floor(k) == k then
      count = count + 1
    else
      return false
    end
  end
  return count == n
end

-- iskey: returns true if key is a non‑empty string or a number.
function struct.iskey(key)
  return (type(key) == "string" and key ~= "") or (type(key) == "number")
end

-- isempty: returns true if val is nil, an empty string, or an empty table.
function struct.isempty(val)
  if val == nil then return true end
  local t = type(val)
  if t == "string" then return val == "" end
  if t == "boolean" then return val == false end
  if t == "number" then return val == 0 end
  if t == "table" then
    local count = 0
    for _ in pairs(val) do count = count + 1 end
    return count == 0
  end
  return false
end

-- isfunc: returns true if val is a function.
function struct.isfunc(val)
  return type(val) == "function"
end

-- items: returns an array of {key, value} pairs for a map or list.
function struct.items(val)
  local result = {}
  if struct.ismap(val) then
    for k, v in pairs(val) do
      table.insert(result, {k, v})
    end
  elseif struct.islist(val) then
    for i, v in ipairs(val) do
      table.insert(result, {i, v})
    end
  end
  return result
end

-- keysof: returns sorted keys for a map, or indices for a list.
function struct.keysof(val)
  if not struct.isnode(val) then return {} end
  local keys = {}
  if struct.ismap(val) then
    for k, _ in pairs(val) do
      table.insert(keys, k)
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  elseif struct.islist(val) then
    for i = 1, #val do
      table.insert(keys, i)
    end
  end
  return keys
end

-- haskey: returns true if getprop(val, key) is defined.
function struct.haskey(val, key)
  return struct.getprop(val, key) ~= UNDEF
end

-- stringify: returns a human-friendly string representation (using JSON, then stripping quotes).
function struct.stringify(val, maxlen)
  local jsonStr = ""
  local ok, encoded = pcall(function()
    return json.encode(val)
  end)
  if ok then
    jsonStr = encoded
  else
    jsonStr = tostring(val)
  end
  jsonStr = tostring(jsonStr):gsub('"', '')
  if maxlen then
    local js = string.sub(jsonStr, 1, maxlen)
    if #jsonStr > maxlen then
      jsonStr = string.sub(js, 1, maxlen - 3) .. "..."
    end
  end
  return jsonStr
end

-- clone: creates a deep copy of a JSON-like structure.
-- Functions are copied by reference.
function struct.clone(val)
  if val == nil then return nil end
  local t = type(val)
  if t ~= "table" then
    return val
  end
  local copy = {}
  for k, v in pairs(val) do
    copy[struct.clone(k)] = struct.clone(v)
  end
  return copy
end

-- escre: escapes regex-special characters.
function struct.escre(s)
  s = s or S.empty
  return s:gsub("([%.%*%+%-%?%^%$%(%)%[%]%%])", "%%%1")
end

-- escurl: URL-encodes a string.
function struct.escurl(s)
  s = s or S.empty
  return (s:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- joinurl: concatenates URL parts, merging forward slashes.
function struct.joinurl(sarr)
  local parts = {}
  for i, s in ipairs(sarr) do
    if s ~= nil and s ~= "" then
      local part = s
      if i == 1 then
        part = part:gsub("([^/])/+", "%1/"):gsub("/+$", "")
      else
        part = part:gsub("([^/])/+", "%1/"):gsub("^/+", ""):gsub("/+$", "")
      end
      if part ~= "" then
        table.insert(parts, part)
      end
    end
  end
  return table.concat(parts, "/")
end

-- getprop: safely gets a property; if undefined, returns alt.
function struct.getprop(val, key, alt)
  if val == nil or key == nil then return alt end
  local out = val[key]
  return (out == nil) and alt or out
end

-- setprop: safely sets a property on a map or list.
function struct.setprop(parent, key, val)
  if not struct.iskey(key) then return parent end
  if struct.ismap(parent) then
    key = tostring(key)
    if val == nil then
      parent[key] = nil
    else
      parent[key] = val
    end
  elseif struct.islist(parent) then
    local keyI = tonumber(key)
    if not keyI then return parent end
    keyI = math.floor(keyI)
    if val == nil then
      if keyI >= 1 and keyI <= #parent then
        table.remove(parent, keyI)
      end
    elseif keyI < 1 then
      table.insert(parent, 1, val)
    else
      if keyI > #parent then
        table.insert(parent, val)
      else
        parent[keyI] = val
      end
    end
  end
  return parent
end

-- walk: traverses a node tree depth-first, applying apply(key, val, parent, path).
function struct.walk(val, apply, key, parent, path)
  path = path or {}
  if struct.isnode(val) then
    for _, pair in ipairs(struct.items(val)) do
      local ckey = pair[1]
      local child = pair[2]
      local newPath = {}
      for i, v in ipairs(path) do table.insert(newPath, v) end
      table.insert(newPath, tostring(ckey))
      val[ckey] = struct.walk(child, apply, ckey, val, newPath)
    end
  end
  return apply(key, val, parent, path or {})
end

-- merge: merges a list of objects, with later values overriding earlier ones.
function struct.merge(objs)
  if not struct.islist(objs) then
    return objs
  elseif #objs == 0 then
    return nil
  elseif #objs == 1 then
    return objs[1]
  else
    local function deepmerge(a, b)
      if type(a) ~= "table" or type(b) ~= "table" then
        return b
      end
      for k, v in pairs(b) do
        if type(v) == "table" and type(a[k]) == "table" then
          a[k] = deepmerge(a[k], v)
        else
          a[k] = v
        end
      end
      return a
    end
    local out = struct.clone(objs[1])
    for i = 2, #objs do
      out = deepmerge(out, objs[i])
    end
    return out
  end
end

-- Helper: converts a path input (string or table) into an array of parts.
local function pathifyInput(path)
  if type(path) == "table" then
    return path
  elseif type(path) == "string" then
    local parts = {}
    for part in string.gmatch(path, "([^" .. S.DT .. "]+)") do
      table.insert(parts, part)
    end
    return parts
  else
    return nil
  end
end

-- getpath: retrieves a deep value given a dot-separated path or array of parts.
function struct.getpath(path, store, current, state)
  local parts = pathifyInput(path)
  if parts == nil then return nil end
  local root = store
  local val = store
  if path == nil or store == nil or (#parts == 1 and parts[1] == S.empty) then
    val = struct.getprop(store, struct.getprop(state, S.base), store)
  elseif #parts > 0 then
    local pI = 1
    if parts[1] == S.empty then
      pI = 2
      root = current
    end
    local part = parts[pI] or nil
    local first = struct.getprop(root, part)
    if first == nil and pI == 1 then
      val = struct.getprop(struct.getprop(root, struct.getprop(state, S.base)), part)
    else
      val = first
    end
    for i = pI + 1, #parts do
      if val == nil then break end
      val = struct.getprop(val, parts[i])
    end
  end
  if state and type(state.handler) == "function" then
    val = state.handler(state, val, current, parts, store)
  end
  return val
end

-- injectstr: performs injection on a string value.
function struct.injectstr(val, store, current, state)
  if type(val) ~= "string" then return S.empty end
  local out = val
  local m = { string.match(val, "^`([^`]+)`$") }
  if #m > 0 then
    if state then state.full = true end
    local pathref = m[1]
    if #pathref > 3 then
      pathref = pathref:gsub("%$BT", S.BT):gsub("%$DS", S.DS)
    end
    out = struct.getpath(pathref, store, current, state)
  else
    out = val:gsub("`([^`]+)`", function(ref)
      if #ref > 3 then
        ref = ref:gsub("%$BT", S.BT):gsub("%$DS", S.DS)
      end
      if state then state.full = false end
      local found = struct.getpath(ref, store, current, state)
      if found == nil then
        return S.empty
      elseif type(found) == "table" then
        local ok, encoded = pcall(function() return json.encode(found) end)
        return ok and encoded or tostring(found)
      else
        return tostring(found)
      end
    end)
    if state and state.handler then
      state.full = true
      out = state.handler(state, out, current, val, store)
    end
  end
  return out
end

-- inject: recursively injects store values into a node.
function struct.inject(val, store, modify, current, state)
  local valtype = type(val)
  if state == nil then
    local parent = { [S.DTOP] = val }
    state = {
      mode = S.MVAL,
      full = false,
      keyI = 0,
      keys = { S.DTOP },
      key = S.DTOP,
      val = val,
      parent = parent,
      path = { S.DTOP },
      nodes = { parent },
      handler = struct.injecthandler,
      base = S.DTOP,
      modify = modify,
      errs = struct.getprop(store, S.DERRS, {})
    }
  end
  if current == nil then
    current = { $TOP = store }
  else
    local parentkey = state.path[#state.path - 1]
    current = (parentkey == nil) and current or struct.getprop(current, parentkey)
  end
  if struct.isnode(val) then
    local origkeys = {}
    if struct.ismap(val) then
      for k, _ in pairs(val) do
        if not string.find(k, S.DS) then
          table.insert(origkeys, k)
        end
      end
      for k, _ in pairs(val) do
        if string.find(k, S.DS) then
          table.insert(origkeys, k)
        end
      end
      table.sort(origkeys, function(a, b) return tostring(a) < tostring(b) end)
    elseif struct.islist(val) then
      for i = 1, #val do
        table.insert(origkeys, i)
      end
    end
    for okI = 1, #origkeys do
      local origkey = S.empty .. origkeys[okI]
      local childpath = {}
      for i, v in ipairs(state.path or {}) do table.insert(childpath, v) end
      table.insert(childpath, origkey)
      local childnodes = {}
      for i, v in ipairs(state.nodes or {}) do table.insert(childnodes, v) end
      table.insert(childnodes, val)
      local childstate = {
        mode = S.MKEYPRE,
        full = false,
        keyI = okI - 1,
        keys = origkeys,
        key = origkey,
        val = val,
        parent = val,
        path = childpath,
        nodes = childnodes,
        handler = struct.injecthandler,
        base = state.base,
        errs = state.errs
      }
      local prekey = struct.injectstr(origkey, store, current, childstate)
      okI = childstate.keyI + 1
      if prekey ~= nil then
        local child = struct.getprop(val, prekey)
        childstate.mode = S.MVAL
        struct.inject(child, store, modify, current, childstate)
        childstate.mode = S.MKEYPOST
        struct.injectstr(origkey, store, current, childstate)
        okI = childstate.keyI + 1
      end
    end
  elseif S.string == valtype then
    state.mode = S.MVAL
    local newval = struct.injectstr(val, store, current, state)
    val = newval
    struct.setprop(state.parent, state.key, newval)
  end
  if modify then
    modify(
      val,
      struct.getprop(state, "key"),
      struct.getprop(state, "parent"),
      state,
      current,
      store
    )
  end
  return struct.getprop(state.parent, S.DTOP)
end

-- injecthandler: default injection handler.
function struct.injecthandler(state, val, current, ref, store)
  local out = val
  if type(val) == "function" and (ref == nil or (type(ref) == "string" and string.sub(ref, 1, 1) == S.DS)) then
    out = val(state, val, current, store)
  elseif state.mode == S.MVAL and state.full then
    struct.setprop(state.parent, state.key, val)
  end
  return out
end

-- transform_DELETE: deletes a key.
function struct.transform_DELETE(state)
  local key = state.key
  local parent = state.parent
  struct.setprop(parent, key, UNDEF)
  return UNDEF
end

-- transform_COPY: copies a value from current.
function struct.transform_COPY(state, _val, current)
  local mode = state.mode
  local key = state.key
  local parent = state.parent
  local out
  if string.sub(mode, 1, #S.MKEY) == S.MKEY then
    out = key
  else
    out = struct.getprop(current, key)
    struct.setprop(parent, key, out)
  end
  return out
end

-- transform_KEY: uses parent's key or meta data.
function struct.transform_KEY(state, _val, current)
  local mode = state.mode
  local parent = state.parent
  local path = state.path
  if state.mode ~= S.MVAL then
    return UNDEF
  end
  local keyspec = struct.getprop(parent, S.DKEY)
  if keyspec ~= UNDEF then
    struct.setprop(parent, S.DKEY, UNDEF)
    return struct.getprop(current, keyspec)
  end
  return struct.getprop(struct.getprop(parent, S.DMETA), S.KEY, path[#path - 1])
end

-- transform_META: clears meta data.
function struct.transform_META(state)
  local parent = state.parent
  struct.setprop(parent, S.DMETA, UNDEF)
  return UNDEF
end

-- transform_MERGE: merges objects.
function struct.transform_MERGE(state, _val, store)
  local mode = state.mode
  local key = state.key
  local parent = state.parent
  if mode == S.MKEYPRE then return key end
  if mode == S.MKEYPOST then
    local args = struct.getprop(parent, key)
    if args == S.empty then
      args = { store.$TOP }
    elseif type(args) ~= "table" then
      args = { args }
    end
    struct.setprop(parent, key, UNDEF)
    local mergelist = { parent }
    for i = 1, #args do
      table.insert(mergelist, args[i])
    end
    table.insert(mergelist, struct.clone(parent))
    local merged = struct.merge(mergelist)
    struct.setprop(parent, key, merged)
    return key
  end
  return UNDEF
end

-- transform_EACH: converts a node to a list.
function struct.transform_EACH(state, _val, current, store)
  local mode = state.mode
  local keys = state.keys
  if keys then
    while #keys > 1 do table.remove(keys) end
  end
  local srcpath = struct.getprop(state.parent, 2)
  local child = struct.clone(struct.getprop(state.parent, 3))
  local src = struct.getpath(srcpath, store, current, state)
  local tcurrent = {}
  local tval = {}
  local tkey = state.path[#state.path - 1]
  local target = state.nodes[#state.nodes - 1] or state.nodes[#state.nodes]
  if struct.isnode(src) then
    if struct.islist(src) then
      for i = 1, #src do
        table.insert(tval, struct.clone(child))
      end
    else
      for k, _ in pairs(src) do
        local entry = struct.clone(child)
        entry[S.DMETA] = { KEY = k }
        tval[k] = entry
      end
    end
    tcurrent = struct.islist(src) and src or {}
    if not struct.islist(src) then
      for k, v in pairs(src) do
        tcurrent[k] = v
      end
    end
  end
  tcurrent = { $TOP = tcurrent }
  tval = struct.inject(tval, store, state.modify, tcurrent)
  struct.setprop(target, tkey, tval)
  return tval[1]
end

-- transform_PACK: converts a node to a map.
function struct.transform_PACK(state, _val, current, store)
  if state.mode ~= S.MKEYPRE or type(state.key) ~= "string" then return UNDEF end
  local parent = state.parent
  local args = struct.getprop(parent, state.key)
  local srcpath = args[1]
  local child = struct.clone(args[2])
  local keyprop = child[S.DKEY]
  local tkey = state.path[#state.path - 1]
  local target = state.nodes[#state.nodes - 1] or state.nodes[#state.nodes]
  local childkey = struct.getprop(child, S.DKEY)
  local keyname = (childkey == UNDEF) and keyprop or childkey
  struct.setprop(child, S.DKEY, UNDEF)
  local tval = {}
  local src = struct.getpath(srcpath, store, current, state)
  if src == nil then return UNDEF end
  if not struct.islist(src) then
    local temp = {}
    for k, v in pairs(src) do
      table.insert(temp, {k, v})
    end
    src = temp
  end
  for _, n in ipairs(src) do
    local kn = struct.getprop(n, keyname)
    struct.setprop(tval, kn, struct.clone(child))
    local nchild = struct.getprop(tval, kn)
    struct.setprop(nchild, S.DMETA, struct.getprop(n, S.DMETA))
  end
  local tcurrent = {}
  for _, n in ipairs(src) do
    local kn = struct.getprop(n, keyname)
    tcurrent[kn] = n
  end
  tcurrent = { $TOP = tcurrent }
  tval = struct.inject(tval, store, state.modify, tcurrent)
  struct.setprop(target, tkey, tval)
  return UNDEF
end

-- transform: transforms data according to a spec.
function struct.transform(data, spec, extra, modify)
  spec = struct.clone(spec)
  local extraTransforms = {}
  local extraData = extra or {}
  for k, v in pairs(extraData) do
    if string.sub(k, 1, 1) == S.DS then
      extraTransforms[k] = v
    else
      extraData[k] = v
    end
  end
  local dataClone = struct.merge({
    struct.clone(extraData or {}),
    struct.clone(data or {})
  })
  local store = {}
  for k, v in pairs(extraTransforms) do
    store[k] = v
  end
  store[S.DTOP] = dataClone
  store["$BT"] = function() return S.BT end
  store["$DS"] = function() return S.DS end
  store["$WHEN"] = function() return os.date("!%Y-%m-%dT%TZ") end
  store["$DELETE"] = struct.transform_DELETE
  store["$COPY"]   = struct.transform_COPY
  store["$KEY"]    = struct.transform_KEY
  store["$META"]   = struct.transform_META
  store["$MERGE"]  = struct.transform_MERGE
  store["$EACH"]   = struct.transform_EACH
  store["$PACK"]   = struct.transform_PACK
  for k, v in pairs(extraTransforms) do
    store[k] = v
  end
  local out = struct.inject(spec, store, modify, store)
  return out
end

-- validate: validates data against a shape specification.
function struct.validate(data, spec, extra, collecterrs)
  local errs = collecterrs or {}
  local out = struct.transform(data, spec, extra,
    function(val, _key, parent, state, current, _store)
      local cval = struct.getprop(current, state.key)
      if cval == UNDEF or state == UNDEF then
        return UNDEF
      end
      local pval = struct.getprop(parent, state.key)
      local t = type(pval)
      if t == "string" and string.find(pval, S.DS) then
        return UNDEF
      end
      local ct = type(cval)
      if t ~= ct and pval ~= UNDEF then
        table.insert(state.errs, invalidTypeMsg(state.path, t, ct, cval))
        return UNDEF
      elseif struct.ismap(cval) then
        if not struct.ismap(val) then
          table.insert(state.errs, invalidTypeMsg(state.path, struct.islist(val) and S.array or t, ct, cval))
          return UNDEF
        end
        local ckeys = struct.keysof(cval)
        local pkeys = struct.keysof(pval)
        if #pkeys > 0 and struct.getprop(pval, '`$OPEN`') ~= true then
          local badkeys = {}
          for _, ckey in ipairs(ckeys) do
            if not struct.haskey(val, ckey) then
              table.insert(badkeys, ckey)
            end
          end
          if #badkeys > 0 then
            table.insert(state.errs, 'Unexpected keys at ' .. pathify(state.path) .. ': ' .. table.concat(badkeys, ', '))
          end
        else
          struct.merge({ pval, cval })
          if struct.isnode(pval) then
            pval['`$OPEN`'] = nil
          end
        end
      elseif struct.islist(cval) then
        if not struct.islist(val) then
          table.insert(state.errs, invalidTypeMsg(state.path, t, ct, cval))
        end
      else
        struct.setprop(parent, state.key, cval)
      end
      return UNDEF
    end
  )
  if #errs > 0 and collecterrs == nil then
    error('Invalid data: ' .. table.concat(errs, "\n"))
  end
  return out
end

-- invalidTypeMsg: produces an error message for type mismatches.
function invalidTypeMsg(path, expected, vt, v)
  vt = (type(v) == "table" and struct.ismap(v)) and S.array or type(v)
  v = struct.stringify(v)
  return 'Expected ' .. expected .. ' at ' .. pathify(path) ..
    ', found ' .. ((v ~= nil) and (vt .. ': ' .. v) or '')
end

-- pathify: converts a path (table) to a dot-separated string.
function pathify(val, from)
  from = (from == nil or from < 0) and 1 or from
  if type(val) == "table" then
    local path = {}
    for i = from, #val do
      table.insert(path, tostring(val[i]))
    end
    if #path == 0 then
      return '<root>'
    end
    return table.concat(path, '.')
  end
  return (val == nil) and '<unknown-path>' or struct.stringify(val)
end

-- Expose public functions.
struct.clone      = struct.clone
struct.escre      = struct.escre
struct.escurl     = struct.escurl
struct.getpath    = struct.getpath
struct.getprop    = struct.getprop
struct.haskey     = struct.haskey
struct.inject     = struct.inject
struct.isempty    = struct.isempty
struct.isfunc     = struct.isfunc
struct.iskey      = struct.iskey
struct.islist     = struct.islist
struct.ismap      = struct.ismap
struct.isnode     = struct.isnode
struct.items      = struct.items
struct.joinurl    = struct.joinurl
struct.keysof     = struct.keysof
struct.merge      = struct.merge
struct.setprop    = struct.setprop
struct.stringify  = struct.stringify
struct.transform  = struct.transform
struct.validate   = struct.validate
struct.walk       = struct.walk

return struct
