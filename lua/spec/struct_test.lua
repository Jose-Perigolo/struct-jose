-- struct_test.lua
-- Lua version of the TypeScript test file for the struct module.
-- This file uses luaunit and dkjson.
--
-- It loads test specifications from a JSON file (e.g. "../../build/test/test.json"),
-- obtains the struct utility functions via a runner (see runner.lua),
-- and then executes a battery of tests similar to the TypeScript version.

local lu = require("luaunit")
local json = require("dkjson")
local struct = require("struct")  -- our Lua port of the utility functions

-- Implement extra helper functions that are expected in tests.
local function isfunc(x)
  return type(x) == "function"
end

local function haskey(tbl, key)
  return tbl[key] ~= nil
end

local function keysof(tbl)
  local keys = {}
  for k, _ in pairs(tbl) do
    table.insert(keys, k)
  end
  return keys
end

local function joinurl(...)
  local parts = {...}
  return table.concat(parts, "/")
end

-- A simple implementation of validate.
local function validate(data, spec, extra, errs)
  errs = errs or {}
  for k, rule in pairs(spec) do
    local value = data[k]
    if type(rule) == "string" then
      if rule == "`$INTEGER`" then
        local transformer = extra and extra["$INTEGER"]
        if transformer then
          local result = transformer({ path = {k} }, value, data)
          if type(result) ~= "number" or math.floor(result) ~= result then
            table.insert(errs, "Not an integer at " .. k .. ": " .. tostring(value))
          end
        end
      else
        if value ~= rule then
          table.insert(errs, "Mismatch at " .. k .. ": expected " .. tostring(rule) .. ", got " .. tostring(value))
        end
      end
    end
  end
  return errs
end

-- Simulated provider as in your TypeScript runner.
local provider = {
  test = function(options)
    options = options or {}
    local client = {
      utility = function()
        return {
          struct = {
            clone      = struct.clone,
            escre      = struct.escre,
            escurl     = struct.escurl,
            getpath    = struct.getpath,
            getprop    = struct.getprop,
            inject     = struct.inject,
            isempty    = struct.isempty,
            iskey      = struct.iskey,
            islist     = struct.islist,
            ismap      = struct.ismap,
            isnode     = struct.isnode,
            items      = struct.items,
            haskey     = haskey,
            keysof     = keysof,
            merge      = struct.merge,
            setprop    = struct.setprop,
            stringify  = struct.stringify,
            transform  = struct.transform,
            walk       = struct.walk,
            validate   = validate,
            joinurl    = joinurl,
          }
        }
      end
    }
    return client
  end
}

-- Import the runner function from runner.lua.
local runnerModule = require("runner")
local runner = runnerModule.runner

-- Helper function similar to the TypeScript "test_set".
local function test_set(tests, apply)
  for _, entry in ipairs(tests.set) do
    local status, result = pcall(apply, entry.in)
    if status then
      local resComparable = (result ~= nil) and json.decode(json.encode(result)) or result
      local outComparable = entry.out
      lu.assertEquals(resComparable, outComparable)
    else
      if entry.err then
        if entry.err == true or string.find(result, entry.err) then
          -- Expected error; continue to next entry.
        else
          entry.thrown = result
          error(json.encode(entry))
        end
      else
        error(result)
      end
    end
  end
end

-- Helper for walk tests.
local function walkpath(_key, val, _parent, path)
  if type(val) == "string" then
    return val .. "~" .. table.concat(path, ".")
  else
    return val
  end
end

-- Helper modifier for inject tests.
local function nullModifier(key, val, parent)
  if val == "__NULL__" then
    struct.setprop(parent, key, nil)
  elseif type(val) == "string" then
    struct.setprop(parent, key, val:gsub("__NULL__", "null"))
  end
end

-- Runner integration: call runner to get the test spec, runset function, and subject.
local runnerResult = runner("struct", {}, "../../build/test/test.json", provider)
local spec   = runnerResult.spec
local runset = runnerResult.runset
local subject = runnerResult.subject

TestStruct = {}

-- Minor tests
function TestStruct:test_minor_exists()
  local util = provider.test().utility().struct
  lu.assertEquals(type(util.clone), "function")
  lu.assertEquals(type(util.escre), "function")
  lu.assertEquals(type(util.escurl), "function")
  lu.assertEquals(type(util.getprop), "function")
  lu.assertEquals(type(haskey), "function")
  lu.assertEquals(type(util.isempty), "function")
  lu.assertEquals(type(isfunc), "function")
  lu.assertEquals(type(util.iskey), "function")
  lu.assertEquals(type(util.islist), "function")
  lu.assertEquals(type(util.ismap), "function")
  lu.assertEquals(type(util.isnode), "function")
  lu.assertEquals(type(util.items), "function")
  lu.assertEquals(type(joinurl), "function")
  lu.assertEquals(type(keysof), "function")
  lu.assertEquals(type(util.setprop), "function")
  lu.assertEquals(type(util.stringify), "function")
end

function TestStruct:test_minor_clone()
  runset(spec.minor.clone, struct.clone)
end

function TestStruct:test_minor_isnode()
  runset(spec.minor.isnode, struct.isnode)
end

function TestStruct:test_minor_ismap()
  runset(spec.minor.ismap, struct.ismap)
end

function TestStruct:test_minor_islist()
  runset(spec.minor.islist, struct.islist)
end

function TestStruct:test_minor_iskey()
  runset(spec.minor.iskey, struct.iskey)
end

function TestStruct:test_minor_isempty()
  runset(spec.minor.isempty, struct.isempty)
end

function TestStruct:test_minor_escre()
  runset(spec.minor.escre, struct.escre)
end

function TestStruct:test_minor_escurl()
  runset(spec.minor.escurl, struct.escurl)
end

function TestStruct:test_minor_stringify()
  runset(spec.minor.stringify, function(vin)
    if vin.max == nil then
      return struct.stringify(vin.val)
    else
      return struct.stringify(vin.val, vin.max)
    end
  end)
end

function TestStruct:test_minor_items()
  runset(spec.minor.items, struct.items)
end

function TestStruct:test_minor_getprop()
  runset(spec.minor.getprop, function(vin)
    if vin.alt == nil then
      return struct.getprop(vin.val, vin.key)
    else
      return struct.getprop(vin.val, vin.key, vin.alt)
    end
  end)
end

function TestStruct:test_minor_setprop()
  runset(spec.minor.setprop, function(vin)
    return struct.setprop(vin.parent, vin.key, vin.val)
  end)
end

function TestStruct:test_minor_haskey()
  runset(spec.minor.haskey, haskey)
end

function TestStruct:test_minor_keysof()
  runset(spec.minor.keysof, keysof)
end

function TestStruct:test_minor_joinurl()
  runset(spec.minor.joinurl, joinurl)
end

function TestStruct:test_minor_isfunc()
  runset(spec.minor.isfunc, isfunc)
  local function f0() return nil end
  lu.assertEquals(isfunc(f0), true)
  lu.assertEquals(isfunc(function() return nil end), true)
end

-- Walk tests
function TestStruct:test_walk_exists()
  lu.assertEquals(type(struct.walk), "function")
end

function TestStruct:test_walk_basic()
  runset(spec.walk.basic, function(vin)
    return struct.walk(vin, walkpath)
  end)
end

-- Merge tests
function TestStruct:test_merge_exists()
  lu.assertEquals(type(struct.merge), "function")
end

function TestStruct:test_merge_basic()
  local testSpec = spec.merge.basic
  lu.assertEquals(struct.merge(testSpec.in), testSpec.out)
end

function TestStruct:test_merge_cases()
  runset(spec.merge.cases, struct.merge)
end

function TestStruct:test_merge_array()
  runset(spec.merge.array, struct.merge)
end

function TestStruct:test_merge_special()
  local f0 = function() return nil end
  lu.assertEquals(struct.merge({ f0 }), f0)
  lu.assertEquals(struct.merge({ nil, f0 }), f0)
  lu.assertEquals(struct.merge({ { a = f0 } }), { a = f0 })
  lu.assertEquals(struct.merge({ { a = { b = f0 } } }), { a = { b = f0 } })
  -- JavaScript-specific tests skipped.
end

-- getpath tests
function TestStruct:test_getpath_exists()
  lu.assertEquals(type(struct.getpath), "function")
end

function TestStruct:test_getpath_basic()
  runset(spec.getpath.basic, function(vin)
    return struct.getpath(vin.path, vin.store)
  end)
end

function TestStruct:test_getpath_current()
  runset(spec.getpath.current, function(vin)
    return struct.getpath(vin.path, vin.store, vin.current)
  end)
end

function TestStruct:test_getpath_state()
  local state = {
    handler = function(state, val, _current, _ref, _store)
      local out = state.step .. ":" .. tostring(val)
      state.step = state.step + 1
      return out
    end,
    step = 0,
    mode = "val",
    full = false,
    keyI = 0,
    keys = {"$TOP"},
    key = "$TOP",
    val = "",
    parent = {},
    path = {"$TOP"},
    nodes = {{}},
    base = "$TOP",
    errs = {},
  }
  runset(spec.getpath.state, function(vin)
    return struct.getpath(vin.path, vin.store, vin.current, state)
  end)
end

-- Inject tests
function TestStruct:test_inject_exists()
  lu.assertEquals(type(struct.inject), "function")
end

function TestStruct:test_inject_basic()
  local testSpec = spec.inject.basic
  lu.assertEquals(struct.inject(testSpec.in.val, testSpec.in.store), testSpec.out)
end

function TestStruct:test_inject_string()
  runset(spec.inject.string, function(vin)
    return struct.inject(vin.val, vin.store, nullModifier, vin.current)
  end)
end

function TestStruct:test_inject_deep()
  runset(spec.inject.deep, function(vin)
    return struct.inject(vin.val, vin.store)
  end)
end

-- Transform tests
function TestStruct:test_transform_exists()
  lu.assertEquals(type(struct.transform), "function")
end

function TestStruct:test_transform_basic()
  local testSpec = spec.transform.basic
  lu.assertEquals(struct.transform(testSpec.in.data, testSpec.in.spec, testSpec.in.store), testSpec.out)
end

function TestStruct:test_transform_paths()
  runset(spec.transform.paths, function(vin)
    return struct.transform(vin.data, vin.spec, vin.store)
  end)
end

function TestStruct:test_transform_cmds()
  runset(spec.transform.cmds, function(vin)
    return struct.transform(vin.data, vin.spec, vin.store)
  end)
end

function TestStruct:test_transform_each()
  runset(spec.transform.each, function(vin)
    return struct.transform(vin.data, vin.spec, vin.store)
  end)
end

function TestStruct:test_transform_pack()
  runset(spec.transform.pack, function(vin)
    return struct.transform(vin.data, vin.spec, vin.store)
  end)
end

function TestStruct:test_transform_modify()
  runset(spec.transform.modify, function(vin)
    return struct.transform(vin.data, vin.spec, vin.store,
      function(key, val, parent)
        if key ~= nil and parent ~= nil and type(val) == "string" then
          parent[key] = "@" .. val
        end
      end
    )
  end)
end

function TestStruct:test_transform_extra()
  local res = struct.transform(
    { a = 1 },
    { x = "`a`", b = "`$COPY`", c = "`$UPPER`" },
    {
      b = 2,
      $UPPER = function(state)
        local path = state.path
        return tostring(path[#path]):upper()
      end,
    }
  )
  lu.assertEquals(res, { x = 1, b = 2, c = "C" })
end

function TestStruct:test_transform_funcval()
  local f0 = function() return 99 end
  lu.assertEquals(struct.transform({}, { x = 1 }), { x = 1 })
  lu.assertEquals(struct.transform({}, { x = f0 }), { x = f0 })
  lu.assertEquals(struct.transform({ a = 1 }, { x = "`a`" }), { x = 1 })
  lu.assertEquals(struct.transform({ f0 = f0 }, { x = "`f0`" }), { x = f0 })
end

-- Validate tests
function TestStruct:test_validate_exists()
  lu.assertEquals(type(validate), "function")
end

function TestStruct:test_validate_basic()
  runset(spec.validate.basic, function(vin)
    return validate(vin.data, vin.spec)
  end)
end

function TestStruct:test_validate_node()
  runset(spec.validate.node, function(vin)
    return validate(vin.data, vin.spec)
  end)
end

function TestStruct:test_validate_custom()
  local errs = {}
  local extra = {
    $INTEGER = function(state, _val, current)
      local key = state.key
      local out = struct.getprop(current, key)
      if type(out) ~= "number" or math.floor(out) ~= out then
        table.insert(state.errs or errs, "Not an integer at " .. table.concat(state.path, ".") .. ": " .. tostring(out))
        return nil
      end
      return out
    end,
  }
  validate({ a = 1 }, { a = "`$INTEGER`" }, extra, errs)
  lu.assertEquals(#errs, 0)

  validate({ a = "A" }, { a = "`$INTEGER`" }, extra, errs)
  lu.assertEquals(errs, {"Not an integer at a: A"})
end

os.exit(lu.LuaUnit.run())
