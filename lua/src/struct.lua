local struct = {}
local json = require("dkjson")

local S = {
  MKEYPRE      = "key:pre",
  MKEYPOST     = "key:post",
  MVAL         = "val",
  MKEY         = "key",
  DKEY         = "`$KEY`",
  DTOP         = "$TOP",
  DERRS        = "$ERRS",
  DMETA        = "`$META`",
  array        = "array",
  base         = "base",
  boolean      = "boolean",
  empty        = "",
  ["function"] = "function",
  number       = "number",
  object       = "object",
  string       = "string",
  key          = "key",
  parent       = "parent",
  BT           = "`",
  DS           = "$",
  DT           = ".",
  KEY          = "KEY",
}
struct.S = S

local UNDEF = nil

local function isnode(val)
  return val ~= nil and type(val) == "table"
end


local function islist(val)
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

local function ismap(val)
  return val ~= nil and type(val) == "table" and (not islist(val))
end


local function iskey(key)
  return (type(key) == "string" and key ~= "") or (type(key) == "number")
end

local function isempty(val)
  return val == nil or val == "" or
      (type(val) == "table" and next(val) == nil)
end

local function isfunc(val)
  return type(val) == "function"
end

local function items(val)
  local result = {}
  if ismap(val) then
    for k, v in pairs(val) do
      table.insert(result, { k, v })
    end
  elseif islist(val) then
    for i, v in ipairs(val) do
      table.insert(result, { i, v })
    end
  end
  return result
end

local function keysof(val)
  if not isnode(val) then return {} end
  local keys = {}
  if ismap(val) then
    for k, _ in pairs(val) do
      table.insert(keys, k)
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  elseif islist(val) then
    for i = 1, #val do
      table.insert(keys, i)
    end
  end
  return keys
end

local function haskey(val, key)
  return getprop(val, key) ~= UNDEF
end

local function stringify(val, maxlen)
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

local function clone(val)
  if val == nil then return nil end
  local t = type(val)
  if t ~= "table" then
    return val
  end
  local copy = {}
  for k, v in pairs(val) do
    copy[clone(k)] = clone(v)
  end
  return copy
end

local function escre(s)
  if s == nil then s = "" end
  return s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

local function escurl(s)
  s = s or S.empty
  return (s:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function joinurl(sarr)
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

local function getprop(val, key, alt)
  if val == nil or key == nil then return alt end
  local out = val[key]
  return (out == nil) and alt or out
end

local function setprop(parent, key, val)
  if not iskey(key) then return parent end
  if ismap(parent) then
    key = tostring(key)
    if val == nil then
      parent[key] = nil
    else
      parent[key] = val
    end
  elseif islist(parent) then
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

local function walk(val, apply, key, parent, path)
  path = path or {}
  if isnode(val) then
    for _, pair in ipairs(items(val)) do
      local ckey = pair[1]
      local child = pair[2]
      local newPath = {}
      for i, v in ipairs(path) do table.insert(newPath, v) end
      table.insert(newPath, tostring(ckey))
      val[ckey] = walk(child, apply, ckey, val, newPath)
    end
  end
  return apply(key, val, parent, path or {})
end

local function merge(objs)
  if not islist(objs) then
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
    local out = clone(objs[1])
    for i = 2, #objs do
      out = deepmerge(out, objs[i])
    end
    return out
  end
end

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

local function getpath(path, store, current, state)
  local parts = pathifyInput(path)
  if parts == nil then return nil end
  local root = store
  local val = store
  if path == nil or store == nil or (#parts == 1 and parts[1] == S.empty) then
    val = getprop(store, getprop(state, S.base), store)
  elseif #parts > 0 then
    local pI = 1
    if parts[1] == S.empty then
      pI = 2
      root = current
    end
    local part = parts[pI] or nil
    local first = getprop(root, part)
    if first == nil and pI == 1 then
      val = getprop(getprop(root, getprop(state, S.base)), part)
    else
      val = first
    end
    for i = pI + 1, #parts do
      if val == nil then break end
      val = getprop(val, parts[i])
    end
  end
  if state and type(state.handler) == "function" then
    val = state.handler(state, val, current, parts, store)
  end
  return val
end

local function injectstr(val, store, current, state)
  if type(val) ~= "string" then return S.empty end
  local out = val
  local m = { string.match(val, "^`([^`]+)`$") }
  if #m > 0 then
    if state then state.full = true end
    local pathref = m[1]
    if #pathref > 3 then
      pathref = pathref:gsub("%$BT", S.BT):gsub("%$DS", S.DS)
    end
    out = getpath(pathref, store, current, state)
  else
    out = val:gsub("`([^`]+)`", function(ref)
      if #ref > 3 then
        ref = ref:gsub("%$BT", S.BT):gsub("%$DS", S.DS)
      end
      if state then state.full = false end
      local found = getpath(ref, store, current, state)
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

local function inject(val, store, modify, current, state)
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
      handler = injecthandler,
      base = S.DTOP,
      modify = modify,
      errs = getprop(store, S.DERRS, {})
    }
  end
  if current == nil then
    current = { ["$TOP"] = store }
  else
    local parentkey = state.path[#state.path - 1]
    current = (parentkey == nil) and current or getprop(current, parentkey)
  end
  if isnode(val) then
    local origkeys = {}
    if ismap(val) then
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
    elseif islist(val) then
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
        handler = injecthandler,
        base = state.base,
        errs = state.errs
      }
      local prekey = injectstr(origkey, store, current, childstate)
      okI = childstate.keyI + 1
      if prekey ~= nil then
        local child = getprop(val, prekey)
        childstate.mode = S.MVAL
        inject(child, store, modify, current, childstate)
        childstate.mode = S.MKEYPOST
        injectstr(origkey, store, current, childstate)
        okI = childstate.keyI + 1
      end
    end
  elseif S.string == valtype then
    state.mode = S.MVAL
    local newval = injectstr(val, store, current, state)
    val = newval
    setprop(state.parent, state.key, newval)
  end
  if modify then
    modify(
      val,
      getprop(state, "key"),
      getprop(state, "parent"),
      state,
      current,
      store
    )
  end
  return getprop(state.parent, S.DTOP)
end

local function injecthandler(state, val, current, ref, store)
  local out = val
  if type(val) == "function" and (ref == nil or (type(ref) == "string" and string.sub(ref, 1, 1) == S.DS)) then
    out = val(state, val, current, store)
  elseif state.mode == S.MVAL and state.full then
    setprop(state.parent, state.key, val)
  end
  return out
end

local function transform_DELETE(state)
  local key = state.key
  local parent = state.parent
  setprop(parent, key, UNDEF)
  return UNDEF
end

local function transform_COPY(state, _val, current)
  local mode = state.mode
  local key = state.key
  local parent = state.parent
  local out
  if string.sub(mode, 1, #S.MKEY) == S.MKEY then
    out = key
  else
    out = getprop(current, key)
    setprop(parent, key, out)
  end
  return out
end

local function transform_KEY(state, _val, current)
  local mode = state.mode
  local parent = state.parent
  local path = state.path
  if state.mode ~= S.MVAL then
    return UNDEF
  end
  local keyspec = getprop(parent, S.DKEY)
  if keyspec ~= UNDEF then
    setprop(parent, S.DKEY, UNDEF)
    return getprop(current, keyspec)
  end
  return getprop(getprop(parent, S.DMETA), S.KEY, path[#path - 1])
end

local function transform_META(state)
  local parent = state.parent
  setprop(parent, S.DMETA, UNDEF)
  return UNDEF
end

local function transform_MERGE(state, _val, store)
  local mode = state.mode
  local key = state.key
  local parent = state.parent
  if mode == S.MKEYPRE then return key end
  if mode == S.MKEYPOST then
    local args = getprop(parent, key)
    if args == S.empty then
      args = { store["$TOP"] }
    elseif type(args) ~= "table" then
      args = { args }
    end
    setprop(parent, key, UNDEF)
    local mergelist = { parent }
    for i = 1, #args do
      table.insert(mergelist, args[i])
    end
    table.insert(mergelist, clone(parent))
    local merged = merge(mergelist)
    setprop(parent, key, merged)
    return key
  end
  return UNDEF
end

local function transform_EACH(state, _val, current, store)
  local mode = state.mode
  local keys = state.keys
  if keys then
    while #keys > 1 do table.remove(keys) end
  end
  local srcpath = getprop(state.parent, 2)
  local child = clone(getprop(state.parent, 3))
  local src = getpath(srcpath, store, current, state)
  local tcurrent = {}
  local tval = {}
  local tkey = state.path[#state.path - 1]
  local target = state.nodes[#state.nodes - 1] or state.nodes[#state.nodes]
  if isnode(src) then
    if islist(src) then
      for i = 1, #src do
        table.insert(tval, clone(child))
      end
    else
      for k, _ in pairs(src) do
        local entry = clone(child)
        entry[S.DMETA] = { KEY = k }
        tval[k] = entry
      end
    end
    tcurrent = islist(src) and src or {}
    if not islist(src) then
      for k, v in pairs(src) do
        tcurrent[k] = v
      end
    end
  end
  tcurrent = { ["$TOP"] = tcurrent }
  tval = inject(tval, store, state.modify, tcurrent)
  setprop(target, tkey, tval)
  return tval[1]
end

local function pathify(val, from)
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
  return (val == nil) and '<unknown-path>' or stringify(val)
end

local function transform_PACK(state, _val, current, store)
  if state.mode ~= S.MKEYPRE or type(state.key) ~= "string" then return UNDEF end
  local parent = state.parent
  local args = getprop(parent, state.key)
  local srcpath = args[1]
  local child = clone(args[2])
  local keyprop = child[S.DKEY]
  local tkey = state.path[#state.path - 1]
  local target = state.nodes[#state.nodes - 1] or state.nodes[#state.nodes]
  local childkey = getprop(child, S.DKEY)
  local keyname = (childkey == UNDEF) and keyprop or childkey
  setprop(child, S.DKEY, UNDEF)
  local tval = {}
  local src = getpath(srcpath, store, current, state)
  if src == nil then return UNDEF end
  if not islist(src) then
    local temp = {}
    for k, v in pairs(src) do
      table.insert(temp, { k, v })
    end
    src = temp
  end
  for _, n in ipairs(src) do
    local kn = getprop(n, keyname)
    setprop(tval, kn, clone(child))
    local nchild = getprop(tval, kn)
    setprop(nchild, S.DMETA, getprop(n, S.DMETA))
  end
  local tcurrent = {}
  for _, n in ipairs(src) do
    local kn = getprop(n, keyname)
    tcurrent[kn] = n
  end
  tcurrent = { ["$TOP"] = tcurrent }
  tval = inject(tval, store, state.modify, tcurrent)
  setprop(target, tkey, tval)
  return UNDEF
end

local function transform(data, spec, extra, modify)
  spec = clone(spec)
  local extraTransforms = {}
  local extraData = extra or {}
  for k, v in pairs(extraData) do
    if string.sub(k, 1, 1) == S.DS then
      extraTransforms[k] = v
    else
      extraData[k] = v
    end
  end
  local dataClone = merge({
    clone(extraData or {}),
    clone(data or {})
  })
  local store = {}
  for k, v in pairs(extraTransforms) do
    store[k] = v
  end
  store[S.DTOP]    = dataClone
  store["$BT"]     = function() return S.BT end
  store["$DS"]     = function() return S.DS end
  store["$WHEN"]   = function() return os.date("!%Y-%m-%dT%TZ") end
  store["$DELETE"] = transform_DELETE
  store["$COPY"]   = transform_COPY
  store["$KEY"]    = transform_KEY
  store["$META"]   = transform_META
  store["$MERGE"]  = transform_MERGE
  store["$EACH"]   = transform_EACH
  store["$PACK"]   = transform_PACK
  for k, v in pairs(extraTransforms) do
    store[k] = v
  end
  local out = inject(spec, store, modify, store)
  return out
end


local function invalidTypeMsg(path, expected, vt, v)
  vt = (type(v) == "table" and ismap(v)) and S.array or type(v)
  v = stringify(v)
  return 'Expected ' .. expected .. ' at ' .. pathify(path) ..
      ', found ' .. ((v ~= nil) and (vt .. ': ' .. v) or '')
end


local function validate(data, spec, extra, collecterrs)
  local errs = collecterrs or {}
  local out = transform(data, spec, extra,
    function(val, _key, parent, state, current, _store)
      local cval = getprop(current, state.key)
      if cval == UNDEF or state == UNDEF then
        return UNDEF
      end
      local pval = getprop(parent, state.key)
      local t = type(pval)
      if t == "string" and string.find(pval, S.DS) then
        return UNDEF
      end
      local ct = type(cval)
      if t ~= ct and pval ~= UNDEF then
        table.insert(state.errs, invalidTypeMsg(state.path, t, ct, cval))
        return UNDEF
      elseif ismap(cval) then
        if not ismap(val) then
          table.insert(state.errs, invalidTypeMsg(state.path, islist(val) and S.array or t, ct, cval))
          return UNDEF
        end
        local ckeys = keysof(cval)
        local pkeys = keysof(pval)
        if #pkeys > 0 and getprop(pval, '`$OPEN`') ~= true then
          local badkeys = {}
          for _, ckey in ipairs(ckeys) do
            if not haskey(val, ckey) then
              table.insert(badkeys, ckey)
            end
          end
          if #badkeys > 0 then
            table.insert(state.errs, 'Unexpected keys at ' .. pathify(state.path) .. ': ' .. table.concat(badkeys, ', '))
          end
        else
          merge({ pval, cval })
          if isnode(pval) then
            pval['`$OPEN`'] = nil
          end
        end
      elseif islist(cval) then
        if not islist(val) then
          table.insert(state.errs, invalidTypeMsg(state.path, t, ct, cval))
        end
      else
        setprop(parent, state.key, cval)
      end
      return UNDEF
    end
  )
  if #errs > 0 and collecterrs == nil then
    error('Invalid data: ' .. table.concat(errs, "\n"))
  end
  return out
end


struct.clone     = clone
struct.escre     = escre
struct.escurl    = escurl
struct.getpath   = getpath
struct.getprop   = getprop
struct.haskey    = haskey
struct.inject    = inject
struct.isempty   = isempty
struct.isfunc    = isfunc
struct.iskey     = iskey
struct.islist    = islist
struct.ismap     = ismap
struct.isnode    = isnode
struct.items     = items
struct.joinurl   = joinurl
struct.keysof    = keysof
struct.merge     = merge
struct.setprop   = setprop
struct.stringify = stringify
struct.transform = transform
struct.validate  = validate
struct.walk      = walk

return { struct = struct }
