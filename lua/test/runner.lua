--[[
  Runner utility module for executing JSON-specified tests.
  This is a Lua implementation matching the TypeScript version in runner.ts.
]] local json = require("dkjson")
local lfs = require("lfs")
local luassert = require("luassert")

-- Constants
local NULLMARK = "__NULL__"

-- Forward declarations to avoid interdependencies
local fixJSON, resolveFlags, resolveEntry, resolveSpec, resolveClients
local resolveSubject, resolveTestPack, resolveArgs, match, matchval
local checkResult, handleError, nullModifier

----------------------------------------------------------
-- Utility Functions
----------------------------------------------------------

-- Read file contents synchronously
-- @param path (string) The path to the file
-- @return (string) The contents of the file
local function readFileSync(path)
  local file = io.open(path, "r")
  if not file then
    error("Cannot open file: " .. path)
  end
  local content = file:read("*a")
  file:close()
  return content
end

-- Join path segments with forward slashes
-- @param ... (string) Path segments to join
-- @return (string) Joined path
local function join(...)
  return table.concat({...}, "/")
end

-- Assert failure with message
-- @param msg (string) Failure message
local function fail(msg)
  luassert(false, msg)
end

-- Deep equality check between two values
-- @param actual (any) The actual value
-- @param expected (any) The expected value
local function deepEqual(actual, expected)
  luassert.same(expected, actual)
end

----------------------------------------------------------
-- Client Class Implementation
----------------------------------------------------------

local Client = {}
Client.__index = Client

-- Create a new client instance
-- @param opts (table) Optional configuration table
-- @return (table) New Client instance
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
-- @param opts (table) Optional configuration table
-- @return (table) New Client instance
function Client.test(opts)
  return Client.new(opts)
end

----------------------------------------------------------
-- Core Helper Functions
----------------------------------------------------------

-- Check if a test value matches a base value according to defined rules
-- @param check (any) The test pattern or value to check
-- @param base (any) The base value to check against
-- @param structUtils (table) Structure utility functions
-- @return (boolean) Whether the value matches
function matchval(check, base, structUtils)
  if check == NULLMARK then
    check = nil
  end

  local pass = check == base

  if not pass then
    if type(check) == "string" then
      local basestr = structUtils.stringify(base)

      -- Check if string starts and ends with '/' (RegExp in TypeScript)
      local rem = check:match("^/(.+)/$")
      if rem then
        -- Convert JS RegExp to Lua pattern when possible
        -- This is a simplification and might need adjustments for complex patterns
        local lua_pattern = rem:gsub("%%", "%%%%"):gsub("%.", "%%."):gsub("%+",
          "%%+"):gsub("%-", "%%-"):gsub("%*", "%%*"):gsub("%?", "%%?"):gsub(
          "%[", "%%["):gsub("%]", "%%]"):gsub("%^", "%%^"):gsub("%$", "%%$")
          :gsub("%(", "%%("):gsub("%)", "%%)")
        pass = basestr:match(lua_pattern) ~= nil
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

-- Match a check structure against a base structure
-- @param check (table) The check structure with patterns
-- @param base (table) The base structure to validate against
-- @param structUtils (table) Structure utility functions
function match(check, base, structUtils)
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

-- Transform null values in JSON data according to flags
-- @param val (any) The value to process
-- @param flags (table) Processing flags including null handling
-- @return (any) The processed value
function fixJSON(val, flags)
  if val == nil or val == "null" then
    return flags.null and NULLMARK or val
  end

  -- Deep clone and preserve metatables
  local function deepClone(v)
    if (v == nil or v == "null") and flags.null then
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

-- Process null marker values
-- @param val (any) The value to check
-- @param key (any) The key in the parent
-- @param parent (table) The parent table
function nullModifier(val, key, parent)
  if val == "__NULL__" then
    parent[key] = nil -- In Lua, nil represents null
  elseif type(val) == "string" then
    parent[key] = val:gsub("__NULL__", "null")
  end
end

-- Resolve test flags with defaults
-- @param flags (table) Input flags
-- @return (table) Resolved flags with defaults applied
function resolveFlags(flags)
  if flags == nil then
    flags = {}
  end
  if flags.null == nil then
    flags.null = true
  else
    flags.null = not not flags.null -- Convert to boolean
  end
  return flags
end

-- Prepare a test entry with the given flags
-- @param entry (table) The test entry
-- @param flags (table) Processing flags
-- @return (table) The processed entry
function resolveEntry(entry, flags)
  entry.out = entry.out == nil and flags.null and NULLMARK or entry.out
  return entry
end

-- Resolve the test subject function
-- @param name (string) The name of the subject to resolve
-- @param container (table) The container object
-- @return (function) The resolved subject function
function resolveSubject(name, container)
  return container and container[name]
end

-- Resolve the test specification from a file
-- @param name (string) The name of the test specification
-- @param testfile (string) The path to the test file
-- @return (table) The resolved test specification
function resolveSpec(name, testfile)
  local alltests = json.decode(readFileSync(join(lfs.currentdir(), testfile)),
    1, "null")
  local spec =
    (alltests.primary and alltests.primary[name]) or (alltests[name]) or
      alltests
  return spec
end

-- Resolve client instances based on specification
-- @param spec (table) The test specification
-- @param store (table) Store with configuration values
-- @param structUtils (table) Structure utility functions
-- @return (table) Table of resolved client instances
function resolveClients(spec, store, structUtils)
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

-- Prepare test arguments
-- @param entry (table) The test entry
-- @param testpack (table) The test pack with client and utility
-- @return (table) Array of arguments for the test
function resolveArgs(entry, testpack)
  local structUtils = testpack.utility.struct
  local args = {structUtils.clone(entry["in"])}

  if entry.ctx then
    args = {entry.ctx}
  elseif entry.args then
    args = entry.args
  end

  if entry.ctx or entry.args then
    local first = args[1]
    if type(first) == "table" and first ~= nil then
      local cloned_value = structUtils.clone(args[1])
      args[1] = cloned_value
      first = cloned_value
      entry.ctx = cloned_value

      first.client = testpack.client
      first.utility = testpack.utility
    end
  end

  return args
end

-- Resolve the test pack with client and subject
-- @param name (string) The name of the test
-- @param entry (table) The test entry
-- @param subject (function) The test subject function
-- @param client (table) The default client
-- @param clients (table) Table of available clients
-- @return (table) The resolved test pack
function resolveTestPack(name, entry, subject, client, clients)
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

-- Handle errors during test execution
-- @param entry (table) The test entry
-- @param err (any) The error that occurred
-- @param structUtils (table) Structure utility functions
function handleError(entry, err, structUtils)
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

-- Check the result of a test against expectations
-- @param entry (table) The test entry
-- @param res (any) The test result
-- @param structUtils (table) Structure utility functions
function checkResult(entry, res, structUtils)
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

----------------------------------------------------------
-- Main Runner Function
----------------------------------------------------------

-- Main test runner function
-- @param name (string) The name of the test
-- @param store (table) Store with configuration values
-- @param testfile (string) The path to the test file
-- @return (table) The runner pack with test functions
local function runner(name, store, testfile)
  local client = Client.test()
  local utility = client.utility()
  local structUtils = utility.struct

  local spec = resolveSpec(name, testfile)
  local clients = resolveClients(spec, store, structUtils)
  local subject = resolveSubject(name, utility)

  -- Run test set with flags
  -- @param testspec (table) The test specification
  -- @param flags (table) Processing flags
  -- @param testsubject (function) Optional test subject override
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

  -- Run test set with default flags
  -- @param testspec (table) The test specification
  -- @param testsubject (function) Optional test subject override
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

-- Module exports
return {
  NULLMARK = NULLMARK,
  nullModifier = nullModifier,
  runner = runner,
  Client = Client
}
