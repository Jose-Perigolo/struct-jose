package.path = package.path .. ";./test/?.lua"

local assert = require("luassert")

local runner = require("runner")
local struct = require("struct")

-- Extract functions from the struct module
local clone = struct.clone
local escre = struct.escre
local escurl = struct.escurl
local getpath = struct.getpath
local getprop = struct.getprop
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
--
-- Modifier function to replace "__NULL__" markers with nil (Lua's null equivalent)
local function nullModifier(val, key, parent, _state, _current, _store)
  if val == "__NULL__" then
    setprop(parent, key, nil)
  elseif type(val) == "string" then
    local replaced = string.gsub(val, "__NULL__", "null")
    setprop(parent, key, replaced)
  end
end

-- Test suite using Busted
describe("struct", function()
  local provider = {
    test = function(options)
      options = options or {}
      return {
        utility = function()
          return {
            struct = {
              clone = clone,
              escre = escre,
              escurl = escurl,
              getpath = getpath,
              getprop = getprop,
              inject = inject,
              isempty = isempty,
              isfunc = isfunc,
              iskey = iskey,
              islist = islist,
              ismap = ismap,
              isnode = isnode,
              items = items,
              haskey = haskey,
              keysof = keysof,
              merge = merge,
              setprop = setprop,
              stringify = stringify,
              transform = transform,
              walk = walk,
              validate = validate,
              joinurl = joinurl,
              pathify = pathify
            }
          }
        end
      }
    end
  }

  local result = runner("struct", {}, "../build/test/test.json", provider)
  local spec = result.spec
  local runset = result.runset

  -- minor tests
  -- ===========
  test("minor-exists", function()
    assert.equal("function", type(clone))
    assert.equal("function", type(escre))
    assert.equal("function", type(escurl))
    assert.equal("function", type(getprop))
    assert.equal("function", type(haskey))

    assert.equal("function", type(isempty))
    assert.equal("function", type(isfunc))
    assert.equal("function", type(iskey))
    assert.equal("function", type(islist))
    assert.equal("function", type(ismap))

    assert.equal("function", type(isnode))
    assert.equal("function", type(items))
    assert.equal("function", type(joinurl))
    assert.equal("function", type(keysof))
    assert.equal("function", type(setprop))

    assert.equal("function", type(stringify))
    assert.equal("function", type(typify))
    assert.equal("function", type(pathify))
  end)

  test("minor-isnode", function()
    runset(spec.minor.isnode, isnode)
  end)

  test("minor-ismap", function()
    runset(spec.minor.ismap, ismap)
  end)

  test("minor-islist", function()
    runset(spec.minor.islist, islist)
  end)

  test("minor-iskey", function()
    runset(spec.minor.iskey, iskey)
  end)

  test("minor-isempty", function()
    runset(spec.minor.isempty, isempty)
  end)

  test("minor-isfunc", function()
    runset(spec.minor.isfunc, isfunc)

    local f0 = function()
      return nil
    end

    assert.equal(isfunc(f0), true)
    assert.equal(isfunc(function()
      return nil
    end), true)
  end)

  test("minor-clone", function()
    runset(spec.minor.clone, clone)

    local f0 = function()
      return nil
    end

    local original = {
      a = f0
    }
    local copied = clone(original)
    -- TODO: Check order of indx in array tables relevant to this test
    assert.are.same(original, copied)
  end)

  test("minor-escre", function()
    runset(spec.minor.escre, escre)
  end)

  test("minor-escurl", function()
    runset(spec.minor.escurl, escurl)
  end)

  test("minor-stringify", function()
    runset(spec.minor.stringify, function(vin)
      if vin.max == nil then
        return stringify(vin.val)
      else
        return stringify(vin.val, vin.max)
      end
    end)
  end)

  test("minor-items", function()
    runset(spec.minor.items, items)
  end)

  test("minor-getprop", function()
    runset(spec.minor.getprop, function(vin)
      if vin.alt == nil then
        return getprop(vin.val, vin.key)
      else
        return getprop(vin.val, vin.key, vin.alt)
      end
    end)
  end)

  test("minor-setprop", function()
    runset(spec.minor.setprop, function(vin)
      return setprop(vin.parent, vin.key, vin.val)
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
    runset(spec.minor.setprop, function(vin)
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
    runset(spec.minor.haskey, haskey)
  end)

  test("minor-keysof", function()
    runset(spec.minor.keysof, keysof)
  end)

  test("minor-joinurl", function()
    runset(spec.minor.joinurl, joinurl)
  end)

  test("minor-typify", function()
    runset(spec.minor.typify, typify)
  end)

  -- -- -- walk tests
  -- -- -- ==========

  test("walk-exists", function()
    assert.equal("function", type(walk))
  end)

  test("walk-log", function()
    local test = clone(spec.walk.log)
    local log = {}

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
    runset(spec.walk.basic, function(vin)
      return walk(vin, walkpath)
    end)
  end)

  -- -- -- merge tests
  -- -- -- ===========

  test("merge-exists", function()
    assert.equal("function", type(merge))
  end)

  test("merge-basic", function()
    local test = clone(spec.merge.basic)
    assert.same(test.out, merge(test['in']))
  end)

  test("merge-cases", function()
    runset(spec.merge.cases, merge)
  end)

  -- test("merge-array", function()
  --   runset(spec.merge.array, merge)
  -- end)

  -- test("merge-special", function()
  --   local f0 = function() return nil end

  --   assert.same(f0, merge({ f0 }))
  --   assert.same(f0, merge({ nil, f0 }))
  --   assert.same({ a = f0 }, merge({ { a = f0 } }))
  --   assert.same({ a = { b = f0 } }, merge({ { a = { b = f0 } } }))
  -- end)

  -- -- -- getpath tests
  -- -- -- =============

  -- test("getpath-exists", function()
  --   assert.equal("function", type(getpath))
  -- end)

  -- test("getpath-basic", function()
  --   runset(spec.getpath.basic, function(vin)
  --     return getpath(vin.path, vin.store)
  --   end)
  -- end)

  -- test("getpath-current", function()
  --   runset(spec.getpath.current, function(vin)
  --     return getpath(vin.path, vin.store, vin.current)
  --   end)
  -- end)

  -- test("getpath-state", function()
  --   local state = {
  --     handler = function(state, val, _current, _ref, _store)
  --       local out = state.meta.step .. ':' .. val
  --       state.meta.step = state.meta.step + 1
  --       return out
  --     end,
  --     meta = { step = 0 },
  --     mode = 'val',
  --     full = false,
  --     keyI = 0,
  --     keys = { '$TOP' },
  --     key = '$TOP',
  --     val = '',
  --     parent = {},
  --     path = { '$TOP' },
  --     nodes = { {} },
  --     base = '$TOP',
  --     errs = {}
  --   }
  --   runset(spec.getpath.state, function(vin)
  --     return getpath(vin.path, vin.store, vin.current, state)
  --   end)
  -- end)

  -- -- inject tests
  -- -- ============

  -- test("inject-exists", function()
  --   assert.equal("function", type(inject))
  -- end)

  -- test("inject-basic", function()
  --   local test = clone(spec.inject.basic)
  --   assert.same(test.out, inject(test['in'].val, test['in'].store))
  -- end)

  -- test("inject-string", function()
  --   runset(spec.inject.string, function(vin)
  --     local result = inject(vin.val, vin.store, nullModifier, vin.current)
  --     return result
  --   end)
  -- end)

  -- test("inject-deep", function()
  --   runset(spec.inject.deep, function(vin)
  --     return inject(vin.val, vin.store)
  --   end)
  -- end)

  -- -- -- transform tests
  -- -- -- ===============

  -- test("transform-exists", function()
  --   assert.equal("function", type(transform))
  -- end)

  -- test("transform-basic", function()
  --   local test = clone(spec.transform.basic)
  --   assert.same(transform(test['in'].data, test['in'].spec, test['in'].store), test.out)
  -- end)

  -- test("transform-paths", function()
  --   runset(spec.transform.paths, function(vin)
  --     return transform(vin.data, vin.spec, vin.store)
  --   end)
  -- end)

  -- test("transform-cmds", function()
  --   runset(spec.transform.cmds, function(vin)
  --     return transform(vin.data, vin.spec, vin.store)
  --   end)
  -- end)

  -- test("transform-each", function()
  --   runset(spec.transform.each, function(vin)
  --     return transform(vin.data, vin.spec, vin.store)
  --   end)
  -- end)
  --
  -- test("transform-pack", function()
  --   runset(spec.transform.pack, function(vin)
  --     return transform(vin.data, vin.spec, vin.store)
  --   end)
  -- end)
  --
  -- test("transform-modify", function()
  --   runset(spec.transform.modify, function(vin)
  --     return transform(vin.data, vin.spec, vin.store, function(key, val, parent)
  --       if key ~= nil and parent ~= nil and type(val) == "string" then
  --         val = "@" .. val
  --         parent[key] = val
  --       end
  --     end)
  --   end)
  -- end)
  --
  -- test("transform-extra", function()
  --   local input_data = { a = 1 }
  --   local spec = { x = "`a`", b = "`$COPY`", c = "`$UPPER`" }
  --   local store = { b = 2 }
  --   store["$UPPER"] = function(state)
  --     local path = state.path
  --     return string.upper(tostring(getprop(path, #path - 1)))
  --   end
  --   assert.same({ x = 1, b = 2, c = "C" }, transform(input_data, spec, store))
  -- end)

  -- validate tests
  -- ===============

  -- test("validate-exists", function()
  --   assert.equal("function", type(validate))
  -- end)

  -- test("validate-basic", function()
  --   runset(spec.validate.basic, function(vin)
  --     return validate(vin.data, vin.spec)
  --   end)
  -- end)

  -- test("validate-node", function()
  --   runset(spec.validate.node, function(vin)
  --     return validate(vin.data, vin.spec)
  --   end)
  -- end)
  --
  -- test("validate-custom", function()
  --   local errs = {}
  --   local extra = {
  --     ["$INTEGER"] = function(state, _val, current)
  --       local key = state.key
  --       local out = getprop(current, key)
  --
  --       local t = type(out)
  --       if t ~= "number" or out ~= math.floor(out) then
  --         -- Build path string from state.path elements, starting at index 2
  --         local path_parts = {}
  --         for i = 2, #state.path do
  --           table.insert(path_parts, tostring(state.path[i]))
  --         end
  --         local path_str = table.concat(path_parts, ".")
  --
  --         table.insert(state.errs, "Not an integer at " .. path_str .. ": " .. tostring(out))
  --         return nil
  --       end
  --
  --       return out
  --     end
  --   }
  --
  --   validate({ a = 1 }, { a = "`$INTEGER`" }, extra, errs)
  --   assert.equal(0, #errs)
  --
  --   validate({ a = "A" }, { a = "`$INTEGER`" }, extra, errs)
  --   assert.same({ "Not an integer at a: A" }, errs)
  -- end)
end)
