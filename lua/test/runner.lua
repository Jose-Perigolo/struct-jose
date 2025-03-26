local json = require("dkjson")
-- local inspect = require 'inspect' -- TEMPORARILY ADDED TO DEBUG
local lfs = require("lfs")
local luassert = require("luassert")

local NULLMARK = "__NULL__"

local function readFileSync(path)
  local file = io.open(path, "r")
  if not file then
    error("Cannot open file: " .. path)
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function join(...)
  return table.concat({...}, "/")
end

local Client = {}
Client.__index = Client

-- Constructor equivalent
function Client.new(opts)
  local instance = setmetatable({}, Client)

  -- Private fields (using closure instead of # private fields)
  local _opts = opts or {}
  local _utility = {
    struct = {
      clone = clone, -- Assuming these functions are defined elsewhere
      getpath = getpath,
      inject = inject,
      items = items,
      stringify = stringify,
      walk = walk
    },
    check = function(ctx)
      return {
        zed = "ZED" ..
          ((_opts == nil) and "" or (_opts.foo == nil and "" or _opts.foo)) ..
          "_" .. ((ctx.bar == nil) and "0" or ctx.bar)
      }
    end
  }

  -- Method to access private utility
  instance.utility = function()
    return _utility
  end

  return instance
end

-- Static method equivalent (matching TypeScript implementation)
function Client.test(opts)
  return Client.new(opts)
end

local function fail(msg)
  luassert(false, msg)
end

local function deepEqual(actual, expected)
  luassert.same(expected, actual)
end

local function fixJSON(val, flags)
  if val == "null" then
    return flags.null and NULLMARK or val
  end

  -- Deep clone and preserve metatables
  local function deepClone(v)
    if v == "null" and flags.null then
      return NULLMARK
    elseif type(v) == "table" then
      local result = {}
      for k, value in pairs(v) do
        result[k] = deepClone(value)
      end

      -- Preserve the metatable if it exists
      local mt = getmetatable(v)
      if mt then
        setmetatable(result, mt)
      end

      return result
    else
      return v
    end
  end

  return deepClone(val)
end

local function resolveFlags(flags)
  if flags == nil then
    flags = {}
  end
  flags.null = flags.null == nil and true or not not flags.null
  return flags
end

local function resolveEntry(entry, flags)
  entry.out = entry.out == nil and flags.null and NULLMARK or entry.out
  return entry
end

local function resolveSubject(name, container)
  return container and container[name]
end

local function resolveArgs(entry, testpack)
  local structUtils = testpack.utility.struct
  local args = {structUtils.clone(entry["in"])}

  if entry.ctx then
    args = {entry.ctx}
  end

  if entry.args then
    args = entry.args
  end

  if entry.ctx or entry.args then
    local first = args[1]
    if type(first) == "table" and first ~= nil then
      local cloned_value = structUtils.clone(args[1]) -- Note: Lua arrays are 1-indexed
      args[1] = cloned_value
      first = cloned_value
      entry.ctx = cloned_value

      first.client = testpack.client
      first.utility = testpack.utility
    end
  end

  return args
end

local function resolveTestPack(name, entry, subject, client, clients)
  local pack = {
    client = client,
    subject = subject,
    utility = client.utility()
  }

  if entry.client then
    pack.client = clients[entry.client]
    pack.utility = pack.client.utility()
    pack.subject = resolveSubject(name, pack.utility)
  end

  return pack
end

local function resolveSpec(name, testfile)
  local alltests = json.decode(readFileSync(join(lfs.currentdir(), testfile)),
    1, "null")
  local spec =
    (alltests.primary and alltests.primary[name]) or (alltests[name]) or
      alltests
  return spec
end

local function resolveClients(spec, store, structUtils)
  local clients = {}

  if spec.DEF and spec.DEF.client then
    for clientName, clientDef in pairs(spec.DEF.client) do
      local copts = clientDef.test.options or {}
      if type(store) == "table" and structUtils.inject then
        structUtils.inject(copts, store)
      end

      clients[clientName] = Client.test(copts)
    end
  end
  return clients
end

local function matchval(check, base, structUtils)
  if check == NULLMARK then
    check = nil
  end

  local pass = check == base

  if not pass then
    if type(check) == "string" then
      local basestr = structUtils.stringify(base)

      -- Check if string starts and ends with '/'
      local rem = check:match("^/(.+)/$")
      if rem then
        -- Lua pattern matching instead of RegExp
        pass = basestr:match(rem) ~= nil
      else
        -- Convert both strings to lowercase and check if one contains the other
        pass = basestr:lower():find(structUtils.stringify(check):lower(), 1,
          true) ~= nil
      end
    elseif type(check) == "function" then
      pass = true
    end
  end

  return pass
end

local function match(check, base, structUtils)
  structUtils.walk(check, function(_key, val, _parent, path)
    local scalar = type(val) ~= "table"
    if scalar then
      local baseval = structUtils.getpath(path, base)

      if not matchval(val, baseval, structUtils) then
        fail("MATCH: " .. table.concat(path, ".") .. ": [" ..
               structUtils.stringify(val) .. "] <=> [" ..
               structUtils.stringify(baseval) .. "]")
      end
    end
  end)
end

local function handleError(entry, err, structUtils)
  entry.thrown = err

  local entry_err = entry.err
  local err_message = (type(err) == "table" and err.message) or tostring(err)

  -- Handle expected errors
  if entry_err ~= nil then
    if entry_err == true or matchval(entry_err, err_message, structUtils) then
      if entry.match then
        match(entry.match, {
          ["in"] = entry["in"],
          out = entry.res,
          ctx = entry.ctx,
          err = err
        }, structUtils)
      end
      return
    end

    fail("ERROR MATCH: [" .. structUtils.stringify(entry_err) .. "] <=> [" ..
           err_message .. "]")
  else
    -- Unexpected error (test didn't specify an error expectation)
    if type(err) == "table" and err.name == "AssertionError" then
      fail(err_message .. "\n\nENTRY: " .. json.encode(entry, {
        indent = true
      }))
    else
      fail((err.stack or err_message) .. "\n\nENTRY: " .. json.encode(entry, {
        indent = true
      }))
    end
  end
end

local function checkResult(entry, res, structUtils)
  if entry.match == nil or entry.out ~= nil then
    -- NOTE: don't use clone as we want to strip functions
    if res ~= nil then
      local json_str = json.encode(res)
      local decoded = json.decode(json_str, 1, "null")
      deepEqual(decoded, entry.out)
    else
      deepEqual(res, entry.out)
    end
  end

  if entry.match then
    match(entry.match, {
      ["in"] = entry["in"],
      out = entry.res,
      ctx = entry.ctx
    }, structUtils)
  end
end

-- Added to match TypeScript version
local function nullModifier(val, key, parent)
  if val == "__NULL__" then
    parent[key] = nil -- In Lua, nil represents null
  elseif type(val) == "string" then
    parent[key] = val:gsub("__NULL__", "null")
  end
end

local function runner(name, store, testfile)
  local client = Client.test()
  local utility = client.utility()
  local structUtils = utility.struct

  local spec = resolveSpec(name, testfile)
  local clients = resolveClients(spec, store, structUtils)
  local subject = resolveSubject(name, utility)

  -- Updated to match TypeScript version
  local function runsetflags(testspec, flags, testsubject)
    subject = testsubject or subject
    flags = resolveFlags(flags)
    local testspecmap = fixJSON(testspec, flags)

    for _, entry in ipairs(testspecmap.set) do
      local success, err = pcall(function()
        entry = resolveEntry(entry, flags)

        local testpack = resolveTestPack(name, entry, subject, client, clients)
        local args = resolveArgs(entry, testpack)

        local res = testpack.subject(table.unpack(args))
        res = fixJSON(res, flags)
        entry.res = res

        checkResult(entry, res, structUtils)
      end)

      if not success then
        handleError(entry, err, structUtils)
      end
    end
  end

  local function runset(testspec, testsubject)
    return runsetflags(testspec, {}, testsubject)
  end

  local runpack = {
    spec = spec,
    runset = runset,
    runsetflags = runsetflags,
    subject = subject
  }

  return runpack
end

return {
  NULLMARK = NULLMARK,
  nullModifier = nullModifier,
  runner = runner,
  Client = Client
}

