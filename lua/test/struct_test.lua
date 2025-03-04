package.path    = package.path .. ";./test/?.lua"

local assert    = require("luassert")

local runner    = require("runner")
local struct    = require("struct")

-- Extract functions from the struct module
local clone     = struct.clone
local escre     = struct.escre
local escurl    = struct.escurl
local getpath   = struct.getpath
local getprop   = struct.getprop
local inject    = struct.inject
local isempty   = struct.isempty
local isfunc    = struct.isfunc
local iskey     = struct.iskey
local islist    = struct.islist
local ismap     = struct.ismap
local isnode    = struct.isnode
local items     = struct.items
local haskey    = struct.haskey
local keysof    = struct.keysof
local merge     = struct.merge
local setprop   = struct.setprop
local stringify = struct.stringify
local transform = struct.transform
local walk      = struct.walk
local validate  = struct.validate
local joinurl   = struct.joinurl


-- -- Load JSON test specification from file
-- local file      = assert(io.open("../../build/test/test.json", "r"))
-- local content   = file:read("*a")
-- file:close()
-- local TESTSPEC
-- if ok_json then
--   TESTSPEC = json.decode(content)
-- else
--   local obj, pos, err = json.decode(content, 1, nil)
--   assert(err == nil, "Failed to parse JSON: " .. tostring(err))
--   TESTSPEC = obj
-- end

-- Helper function to run a set of tests
-- local function test_set(tests, apply)
--   for _, entry in ipairs(tests.set) do
--     local ok, err = pcall(function()
--       local result = apply(entry['in'])
--       assert.same(entry.out, result) -- deep equality check
--     end)
--     if not ok then
--       local entry_err = entry.err
--       if entry_err ~= nil then
--         local err_msg = tostring(err)
--         if entry_err == true
--             or (type(entry_err) == "string" and string.find(err_msg, entry_err, 1, true)) then
--           break -- expected error occurred; stop further iterations
--         else
--           entry.thrown = err_msg
--           assert(false, json.encode(entry)) -- fail with details if wrong error
--         end
--       else
--         error(err, 0) -- unexpected error; rethrow to fail the test
--       end
--     end
--   end
-- end

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
-- local function nullModifier(key, val, parent)
--   if val == "__NULL__" then
--     setprop(parent, key, nil)
--   elseif type(val) == "string" then
--     local replaced = string.gsub(val, "__NULL__", "null")
--     setprop(parent, key, replaced)
--   end
-- end

-- Test suite using Busted
describe("struct", function()
  local provider = {
    test = function(options)
      options = options or {}
      return {
        utility = function()
          return {
            struct = {
              clone     = clone,
              escre     = escre,
              escurl    = escurl,
              getpath   = getpath,
              getprop   = getprop,
              inject    = inject,
              isempty   = isempty,
              isfunc    = isfunc,
              iskey     = iskey,
              islist    = islist,
              ismap     = ismap,
              isnode    = isnode,
              items     = items,
              haskey    = haskey,
              keysof    = keysof,
              merge     = merge,
              setprop   = setprop,
              stringify = stringify,
              transform = transform,
              walk      = walk,
              validate  = validate,
              joinurl   = joinurl,
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

    local original = { a = f0 }
    local copied = clone(original)

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

  -- -- walk tests
  -- -- ==========
  test("walk-exists", function()
    assert.equal("function", type(walk))
  end)

  test("walk-basic", function()
    runset(spec.walk.basic, function(vin)
      return walk(vin, walkpath)
    end)
  end)

  -- -- merge tests
  -- -- ===========
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

  test("merge-array", function()
    runset(spec.merge.array, merge)
  end)

  test("merge-special", function()
    local f0 = function() return nil end

    assert.same(f0, merge({ f0 }))
    assert.same(f0, merge({ nil, f0 }))
    assert.same({ a = f0 }, merge({ { a = f0 } }))
    assert.same({ a = { b = f0 } }, merge({ { a = { b = f0 } } }))
  end)

  -- -- getpath tests
  -- -- =============
  -- it("getpath-exists", function()
  --   assert.equal("function", type(getpath))
  -- end)
  --
  -- it("getpath-basic", function()
  --   test_set(clone(TESTSPEC.getpath.basic), function(vin)
  --     return getpath(vin.path, vin.store)
  --   end)
  -- end)
  --
  -- it("getpath-current", function()
  --   test_set(clone(TESTSPEC.getpath.current), function(vin)
  --     return getpath(vin.path, vin.store, vin.current)
  --   end)
  -- end)
  --
  -- it("getpath-state", function()
  --   local state = {
  --     handler = function(st, val, current, store)
  --       local out = tostring(st.step) .. ":" .. val
  --       st.step = st.step + 1
  --       return out
  --     end,
  --     step = 0,
  --     mode = "val",
  --     full = false,
  --     keyI = 0,
  --     keys = { "$TOP" },
  --     key = "$TOP",
  --     val = "",
  --     parent = {},
  --     path = { "$TOP" },
  --     nodes = { {} },
  --     base = "$TOP"
  --   }
  --   test_set(clone(TESTSPEC.getpath.state), function(vin)
  --     return getpath(vin.path, vin.store, vin.current, state)
  --   end)
  -- end)
  --
  -- -- inject tests
  -- -- ============
  -- it("inject-exists", function()
  --   assert.equal("function", type(inject))
  -- end)
  --
  -- it("inject-basic", function()
  --   local test = clone(TESTSPEC.inject.basic)
  --   assert.same(test.out, inject(test['in'].val, test['in'].store))
  -- end)
  --
  -- it("inject-string", function()
  --   test_set(clone(TESTSPEC.inject.string), function(vin)
  --     return inject(vin.val, vin.store, nullModifier, vin.current)
  --   end)
  -- end)
  --
  -- it("inject-deep", function()
  --   test_set(clone(TESTSPEC.inject.deep), function(vin)
  --     return inject(vin.val, vin.store)
  --   end)
  -- end)
  --
  -- -- transform tests
  -- -- ===============
  -- it("transform-exists", function()
  --   assert.equal("function", type(transform))
  -- end)
  --
  -- it("transform-basic", function()
  --   local test = clone(TESTSPEC.transform.basic)
  --   assert.same(test.out, transform(test['in'].data, test['in'].spec, test['in'].store))
  -- end)
  --
  -- it("transform-paths", function()
  --   test_set(clone(TESTSPEC.transform.paths), function(vin)
  --     return transform(vin.data, vin.spec, vin.store)
  --   end)
  -- end)
  --
  -- it("transform-cmds", function()
  --   test_set(clone(TESTSPEC.transform.cmds), function(vin)
  --     return transform(vin.data, vin.spec, vin.store)
  --   end)
  -- end)
  --
  -- it("transform-each", function()
  --   test_set(clone(TESTSPEC.transform.each), function(vin)
  --     return transform(vin.data, vin.spec, vin.store)
  --   end)
  -- end)
  --
  -- it("transform-pack", function()
  --   test_set(clone(TESTSPEC.transform.pack), function(vin)
  --     return transform(vin.data, vin.spec, vin.store)
  --   end)
  -- end)
  --
  -- it("transform-modify", function()
  --   test_set(clone(TESTSPEC.transform.modify), function(vin)
  --     return transform(vin.data, vin.spec, vin.store, function(key, val, parent)
  --       if key ~= nil and parent ~= nil and type(val) == "string" then
  --         val = "@" .. val
  --         parent[key] = val
  --       end
  --     end)
  --   end)
  -- end)
  --
  -- it("transform-extra", function()
  --   local input_data = { a = 1 }
  --   local spec = { x = "`a`", b = "`$COPY`", c = "`$UPPER`" }
  --   local store = { b = 2 }
  --   store["$UPPER"] = function(state)
  --     local path = state.path
  --     return string.upper(tostring(getprop(path, #path - 1)))
  --   end
  --   assert.same({ x = 1, b = 2, c = "C" }, transform(input_data, spec, store))
  -- end)
end)
