-- runner.lua
-- This is the Lua equivalent of your TypeScript runner.ts file.
-- It imports the utility functions via provider.test().utility().struct,
-- loads the test spec from a JSON file, sets up client overrides, and
-- returns an object with the spec, a runset function, and the test subject.

local json = require("dkjson")
local path = require("pl.path")    -- using Penlight's path module; alternatively, define your own join()
local io = io

-- Dummy deepEqual and fail functions using luaunit-like behavior.
-- In your actual project you may want to use luaunit.assertEquals() and luaunit.fail().
local function deepEqual(a, b)
  assert(a == b, "Deep equality failed: " .. tostring(a) .. " ~= " .. tostring(b))
end

local function fail(message)
  error(message, 2)
end

-- matchval: compare check against base value.
local function matchval(check, base)
  if check == '__UNDEF__' then
    check = nil
  end
  local pass = (check == base)
  if not pass then
    if type(check) == "string" then
      local basestr = tostring(base)
      local rem = string.match(check, "^/(.+)/$")
      if rem then
        -- Lua does not have full regex; we simulate a simple substring test.
        pass = string.find(basestr, rem) ~= nil
      else
        pass = string.find(string.lower(basestr), string.lower(tostring(check))) ~= nil
      end
    elseif type(check) == "function" then
      pass = true
    end
  end
  return pass
end

-- match: traverse the check object using walk, compare each leaf with base.
local function match(check, base, struct)
  struct.walk(check, function(_key, val, _parent, path)
    if not struct.isnode(val) then
      local baseval = struct.getpath(path, base)
      if not matchval(val, baseval) then
        fail("MATCH: " .. table.concat(path, ".") ..
          ": [" .. struct.stringify(val) .. "] <=> [" .. struct.stringify(baseval) .. "]")
      end
    end
  end)
end

-- runner: main function. Parameters:
--   name      (string): name of the test subject.
--   store     (table): additional data store.
--   testfile  (string): path to the test JSON file (relative to __dirname).
--   provider  (table): provider with a test() function.
local function runner(name, store, testfile, provider)
  -- Get a client and its utility functions.
  local client = provider.test()
  local utility = client.utility()
  local struct = utility.struct

  local clone     = struct.clone
  local getpath   = struct.getpath
  local inject    = struct.inject
  local ismap     = struct.ismap
  local items     = struct.items
  local stringify = struct.stringify
  local walk      = struct.walk
  local isnode    = struct.isnode

  -- Read the JSON test file.
  local currentDir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
  local filename = path.join(currentDir, testfile)
  local f = io.open(filename, "r")
  if not f then error("Cannot open file: " .. filename) end
  local alltestsStr = f:read("*a")
  f:close()
  local alltests, pos, err = json.decode(alltestsStr, 1, nil)
  if err then error(err) end

  -- Determine spec: try primary[name], then [name], then alltests.
  local spec = nil
  if alltests.primary and alltests.primary[name] then
    spec = alltests.primary[name]
  elseif alltests[name] then
    spec = alltests[name]
  else
    spec = alltests
  end

  -- Setup client overrides if spec.DEF exists.
  local clients = {}
  if spec.DEF then
    for _, cdef in ipairs(items(spec.DEF.client)) do
      local copts = (cdef[2].test and cdef[2].test.options) or {}
      if ismap(store) then
        inject(copts, store)
      end
      -- Assume provider.test returns a client synchronously.
      clients[cdef[1]] = provider.test(copts)
    end
  end

  local subject = utility[name]

  -- runset: function to run a set of tests.
  local function runset(testspec, testsubject, makesubject)
    testsubject = testsubject or subject
    for _, entry in ipairs(testspec.set) do
      local testclient = client
      if entry.client then
        testclient = clients[entry.client]
        testsubject = client.utility()[name]
      end
      if makesubject then
        testsubject = makesubject(testsubject)
      end

      local args = { clone(entry.in) }
      if entry.ctx then
        args = { entry.ctx }
      elseif entry.args then
        args = entry.args
      end

      if entry.ctx or entry.args then
        local first = args[1]
        if ismap(first) then
          entry.ctx = clone(first)
          args[1] = entry.ctx
          entry.ctx.client = testclient
          entry.ctx.utility = testclient.utility()
        end
      end

      local res = testsubject(table.unpack(args))
      entry.res = res

      if entry.match == nil or entry.out ~= nil then
        local resComparable = (res ~= nil) and json.decode(json.encode(res)) or res
        deepEqual(resComparable, entry.out)
      end

      if entry.match then
        match(entry.match, { ["in"] = entry.in, out = entry.res, ctx = entry.ctx }, struct)
      end
    end
  end

  return {
    spec = spec,
    runset = runset,
    subject = subject,
  }
end

return { runner = runner }

