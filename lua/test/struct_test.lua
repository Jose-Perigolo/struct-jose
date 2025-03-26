package.path = package.path .. ";./test/?.lua"

local assert = require("luassert")

local runnerModule = require("runner")
local inspect = require 'inspect' -- TEMPORARILY ADDED TO DEBUG
local struct = require("struct")

local NULLMARK, nullModifier, runner = runnerModule.NULLMARK,
  runnerModule.nullModifier, runnerModule.runner

-- Extract functions from the struct module
local clone = struct.clone
local escre = struct.escre
local escurl = struct.escurl
local getpath = struct.getpath
local getprop = struct.getprop
local strkey = struct.strkey
local inject = struct.inject
local isempty = struct.isempty
local isfunc = struct.isfunc
local iskey = struct.iskey
local islist = struct.islist
local ismap = struct.ismap
local isnode = struct.isnode
local items = struct.items
local haskey = struct.haskey
local keysof = struct.keysof
local merge = struct.merge
local setprop = struct.setprop
local stringify = struct.stringify
local transform = struct.transform
local typify = struct.typify
local walk = struct.walk
local validate = struct.validate
local joinurl = struct.joinurl
local pathify = struct.pathify

-- Modifier function for walk (appends path to string values)
local function walkpath(_key, val, _parent, path)
  if type(val) == "string" then
    return val .. "~" .. table.concat(path, ".")
  else
    return val
  end
end

-- Helper function to create an array-like table with metatable
local function array(...)
  local t = {...}
  return setmetatable(t, {
    __jsontype = "array"
  })
end

-- Helper function to create an object-like table with metatable
local function object(t)
  return setmetatable(t or {}, {
    __jsontype = "object"
  })
end

-- Test suite using Busted
describe("struct", function()
  local runpack = runner("struct", {}, "../build/test/test.json")
  local spec, runset, runsetflags = runpack.spec, runpack.runset,
    runpack.runsetflags

  local minorSpec = spec.minor
  local walkSpec = spec.walk
  local mergeSpec = spec.merge
  local getpathSpec = spec.getpath
  local injectSpec = spec.inject
  local transformSpec = spec.transform
  local validateSpec = spec.validate

  test("exists", function()
    assert.equal("function", type(clone))
    assert.equal("function", type(escre))
    assert.equal("function", type(escurl))
    assert.equal("function", type(getprop))
    assert.equal("function", type(getpath))

    assert.equal("function", type(haskey))
    assert.equal("function", type(inject))
    assert.equal("function", type(isempty))
    assert.equal("function", type(isfunc))
    assert.equal("function", type(iskey))

    assert.equal("function", type(islist))
    assert.equal("function", type(ismap))
    assert.equal("function", type(isnode))
    assert.equal("function", type(items))
    assert.equal("function", type(joinurl))

    assert.equal("function", type(keysof))
    assert.equal("function", type(merge))
    assert.equal("function", type(pathify))
    assert.equal("function", type(setprop))
    assert.equal("function", type(strkey))

    assert.equal("function", type(stringify))
    assert.equal("function", type(transform))
    assert.equal("function", type(typify))
    assert.equal("function", type(validate))
    assert.equal("function", type(walk))
  end)

  -- minor tests
  -- ===========

  test("minor-isnode", function()
    runset(minorSpec.isnode, isnode)
  end)

  test("minor-ismap", function()
    runset(minorSpec.ismap, ismap)
  end)

  test("minor-islist", function()
    runset(minorSpec.islist, islist)
  end)

  test("minor-iskey", function()
    runsetflags(minorSpec.iskey, {
      null = false
    }, iskey)
  end)

  test("minor-strkey", function()
    runsetflags(minorSpec.strkey, {
      null = false
    }, strkey)
  end)

  test("minor-isempty", function()
    runsetflags(minorSpec.isempty, {
      null = false
    }, isempty)
  end)

  test("minor-isfunc", function()
    runset(minorSpec.isfunc, isfunc)

    local f0 = function()
      return nil
    end

    assert.equal(isfunc(f0), true)
    assert.equal(isfunc(function()
      return nil
    end), true)
  end)

  test("minor-clone", function()
    runsetflags(minorSpec.clone, {
      null = false
    }, clone)

    local f0 = function()
      return nil
    end

    local original = {
      a = f0
    }
    local copied = clone(original)
    assert.are.same(original, copied)
  end)

  test("minor-escre", function()
    runset(minorSpec.escre, escre)
  end)

  test("minor-escurl", function()
    runset(minorSpec.escurl, escurl)
  end)

  test("minor-stringify", function()
    runset(minorSpec.stringify, function(vin)
      if NULLMARK == vin.val then
        return stringify("null", vin.max)
      else
        return stringify(vin.val, vin.max)
      end
    end)
  end)

  test('minor-pathify', function()
    runsetflags(minorSpec.pathify, {
      null = true
    }, function(vin)
      if NULLMARK == vin.path then
        path = nil
      else
        path = vin.path
      end

      local pathstr = pathify(path, vin.from):gsub('__NULL__%.', '')
      pathstr = NULLMARK == vin.path and pathstr:gsub('>', ':null>') or pathstr
      return pathstr
    end)
  end)

  test("minor-items", function()
    runset(minorSpec.items, items)
  end)

  test("minor-getprop", function()
    runsetflags(minorSpec.getprop, {
      null = false
    }, function(vin)
      if vin.alt == nil then
        return getprop(vin.val, vin.key)
      else
        return getprop(vin.val, vin.key, vin.alt)
      end
    end)
  end)

  test("minor-edge-getprop", function()
    local strarr = {"a", "b", "c", "d", "e"}
    assert.same(getprop(strarr, 2), "c")
    assert.same(getprop(strarr, "2"), "c")

    local intarr = {2, 3, 5, 7, 11}
    assert.same(getprop(intarr, 2), 5)
    assert.same(getprop(intarr, "2"), 5)
  end)

  test("minor-setprop", function()
    runsetflags(minorSpec.setprop, {
      null = false
    }, function(vin)
      return setprop(vin.parent, vin.key, vin.val)
    end)
  end)

  test("minor-edge-setprop", function()
    local strarr0 = {"a", "b", "c", "d", "e"}
    local strarr1 = {"a", "b", "c", "d", "e"}
    assert.same({"a", "b", "C", "d", "e"}, setprop(strarr0, 2, "C"))
    assert.same({"a", "b", "CC", "d", "e"}, setprop(strarr1, "2", "CC"))

    local intarr0 = {2, 3, 5, 7, 11}
    local intarr1 = {2, 3, 5, 7, 11}
    assert.same({2, 3, 55, 7, 11}, setprop(intarr0, 2, 55))
    assert.same({2, 3, 555, 7, 11}, setprop(intarr1, "2", 555))
  end)

  test("minor-haskey", function()
    runset(minorSpec.haskey, haskey)
  end)

  test("minor-keysof", function()
    runset(minorSpec.keysof, keysof)
  end)

  test("minor-joinurl", function()
    runsetflags(minorSpec.joinurl, {
      null = false
    }, joinurl)
  end)

  test("minor-typify", function()
    runsetflags(minorSpec.typify, {
      null = false
    }, typify)
  end)

  --   -- -- -- -- walk tests
  --   -- -- -- -- ==========

  test("walk-log", function()
    local test = clone(walkSpec.log)
    local log = array()

    local function walklog(key, val, parent, path)
      table.insert(log,
        "k=" .. stringify(key) .. ", v=" .. stringify(val) .. ", p=" ..
          stringify(parent) .. ", t=" .. pathify(path))
      return val
    end

    walk(test["in"], walklog)
    assert.same(log, test.out)
  end)

  test("walk-basic", function()
    runset(walkSpec.basic, function(vin)
      return walk(vin, walkpath)
    end)
  end)

  --   -- -- -- merge tests
  --   -- -- -- ===========

  test("merge-basic", function()
    local test = clone(mergeSpec.basic)
    assert.same(test.out, merge(test['in']))
  end)

  test("merge-cases", function()
    runset(mergeSpec.cases, merge)
  end)

  test("merge-array", function()
    runset(mergeSpec.array, merge)
  end)

  --   test("merge-special", function()
  --     local f0 = function()
  --       return nil
  --     end

  --     assert.same(f0, merge(array(f0)))
  --     assert.same(f0, merge(array(nil, f0)))
  --     assert.same(object({
  --       a = f0
  --     }), merge(array(object({
  --       a = f0
  --     }))))
  --     assert.same(object({
  --       a = object({
  --         b = f0
  --       })
  --     }), merge(array(object({
  --       a = object({
  --         b = f0
  --       })
  --     }))))
  --   end)

  --   -- -- -- getpath tests
  --   -- -- -- =============

  --   test("getpath-basic", function()
  --     runset(spec.getpath.basic, function(vin)
  --       return getpath(vin.path, vin.store)
  --     end)
  --   end)

  --   test("getpath-current", function()
  --     runset(spec.getpath.current, function(vin)
  --       return getpath(vin.path, vin.store, vin.current)
  --     end)
  --   end)

  --   test("getpath-state", function()
  --     local state = {
  --       handler = function(state, val, _current, _ref, _store)
  --         local out = state.meta.step .. ':' .. val
  --         state.meta.step = state.meta.step + 1
  --         return out
  --       end,
  --       meta = {
  --         step = 0
  --       },
  --       mode = 'val',
  --       full = false,
  --       keyI = 0,
  --       keys = {'$TOP'},
  --       key = '$TOP',
  --       val = '',
  --       parent = {},
  --       path = {'$TOP'},
  --       nodes = {{}},
  --       base = '$TOP',
  --       errs = {}
  --     }
  --     runset(spec.getpath.state, function(vin)
  --       return getpath(vin.path, vin.store, vin.current, state)
  --     end)
  --   end)

  --   -- -- inject tests
  --   -- -- ============

  --   test("inject-exists", function()
  --     assert.equal("function", type(inject))
  --   end)

  --   test("inject-basic", function()
  --     local test = clone(spec.inject.basic)
  --     assert.same(test.out, inject(test['in'].val, test['in'].store))
  --   end)

  --   test("inject-string", function()
  --     runset(spec.inject.string, function(vin)
  --       local result = inject(vin.val, vin.store, nullModifier, vin.current)
  --       return result
  --     end)
  --   end)

  --   test("inject-deep", function()
  --     runset(spec.inject.deep, function(vin)
  --       return inject(vin.val, vin.store)
  --     end)
  --   end)

  --   -- -- -- transform tests
  --   -- -- -- ===============

  --   test("transform-basic", function()
  --     local test = clone(spec.transform.basic)
  --     assert.same(transform(test['in'].data, test['in'].spec, test['in'].store),
  --       test.out)
  --   end)

  --   test("transform-paths", function()
  --     runset(spec.transform.paths, function(vin)
  --       return transform(vin.data, vin.spec, vin.store)
  --     end)
  --   end)

  --   test("transform-cmds", function()
  --     runset(spec.transform.cmds, function(vin)
  --       return transform(vin.data, vin.spec, vin.store)
  --     end)
  --   end)

  --   test("transform-each", function()
  --     runset(spec.transform.each, function(vin)
  --       return transform(vin.data, vin.spec, vin.store)
  --     end)
  --   end)

  --   test("transform-pack", function()
  --     runset(spec.transform.pack, function(vin)
  --       return transform(vin.data, vin.spec, vin.store)
  --     end)
  --   end)

  --   test("transform-modify", function()
  --     runset(spec.transform.modify, function(vin)
  --       return transform(vin.data, vin.spec, vin.store, function(val, key, parent)
  --         if key ~= nil and parent ~= nil and type(val) == "string" then
  --           parent[key] = "@" .. val
  --           val = parent[key]
  --         end
  --       end)
  --     end)
  --   end)

  --   test("transform-extra", function()
  --     assert.same(transform({
  --       a = 1
  --     }, {
  --       x = '`a`',
  --       b = '`$COPY`',
  --       c = '`$UPPER`'
  --     }, {
  --       b = 2,
  --       ["$UPPER"] = function(state)
  --         local path = state.path
  --         return ('' .. tostring(getprop(path, #path - 1))):upper()
  --       end
  --     }), {
  --       x = 1,
  --       b = 2,
  --       c = 'C'
  --     })
  --   end)

  --   test("transform-funcval", function()
  --     local f0 = function()
  --       return 99
  --     end

  --     assert.same(transform({}, {
  --       x = 1
  --     }), {
  --       x = 1
  --     })
  --     assert.same(transform({}, {
  --       x = f0
  --     }), {
  --       x = f0
  --     })
  --     assert.same(transform({
  --       a = 1
  --     }, {
  --       x = '`a`'
  --     }), {
  --       x = 1
  --     })
  --     assert.same(transform({
  --       f0 = f0
  --     }, {
  --       x = '`f0`'
  --     }), {
  --       x = f0
  --     })
  --   end)

  --   -- validate tests
  --   -- ===============

  --   test("validate-basic", function()
  --     runset(spec.validate.basic, function(vin)
  --       return validate(vin.data, vin.spec)
  --     end)
  --   end)

  --   test("validate-node", function()
  --     runset(spec.validate.node, function(vin)
  --       return validate(vin.data, vin.spec)
  --     end)
  --   end)

  --   test("validate-custom", function()
  --     local errs = {}
  --     local extra = {
  --       ["$INTEGER"] = function(state, _val, current)
  --         local key = state.key
  --         local out = getprop(current, key)
  --         local t = type(out)
  --         if t ~= "number" or out ~= math.floor(out) then
  --           -- Build path string from state.path elements, starting at index 2
  --           local path_parts = {}
  --           for i = 2, #state.path do
  --             table.insert(path_parts, tostring(state.path[i]))
  --           end
  --           local path_str = table.concat(path_parts, ".")
  --           table.insert(state.errs, "Not an integer at " .. path_str .. ": " ..
  --             tostring(out))
  --           return nil
  --         end
  --         return out
  --       end
  --     }

  --     local shape = {
  --       a = "`$INTEGER`"
  --     }
  --     local out = validate({
  --       a = 1
  --     }, shape, extra, errs)
  --     assert.same({
  --       a = 1
  --     }, out)
  --     assert.equal(0, #errs)

  --     -- Reset errors array for the second test
  --     errs = {}
  --     out = validate({
  --       a = "A"
  --     }, shape, extra, errs)
  --     assert.same({
  --       a = "A"
  --     }, out)
  --     assert.same({"Not an integer at a: A"}, errs)
  --   end)
end)
