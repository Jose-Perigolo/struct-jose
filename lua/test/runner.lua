local json = require("dkjson")
local lfs = require("lfs")
local luassert = require("luassert")

local function readFileSync(path)
  local file = io.open(path, "r")
  if not file then error("Cannot open file: " .. path) end
  local content = file:read("*a")
  file:close()
  return content
end

local function join(...)
  return table.concat({ ... }, "/")
end

local function fail(msg)
  luassert(false, msg)
end

local function deepEqual(actual, expected)
  luassert.same(expected, actual)
end

local function matchval(check, base)
  check = (check == "__UNDEF__") and nil or check

  -- Special handling for error message comparison
  if type(check) == "string" and type(base) == "string" then
    -- Clean up base error string by removing file location and "Invalid data:" prefix
    local base_clean = base:match("Invalid data:%s*(.+)") or
        base:match("[^:]+:%d+:%s*(.+)") or
        base

    -- Handle the path format differences
    base_clean = base_clean:gsub("at %$TOP%.([^,]+)", "at %1") -- Replace "$TOP.a" with just "a"
    base_clean = base_clean:gsub("at %$TOP", "at <root>")      -- Replace remaining "$TOP" with "<root>"

    -- Direct comparison with cleaned error message
    if check == base_clean then
      return true
    end
  end

  local pass = check == base

  if not pass then
    if type(check) == "string" then
      local basestr = json.encode(base)
      local rem = check:match("^/(.+)/$")
      if rem then
        pass = basestr:match(rem) ~= nil
      else
        pass = basestr:lower():find(json.encode(check):lower(), 1, true) ~= nil
      end
    elseif type(check) == "function" then
      pass = true
    end
  end

  return pass
end

local function match(check, base, walk, getpath, stringify)
  walk(check, function(_key, val, _parent, path)
    if type(val) ~= "table" then
      local baseval = getpath(path, base)
      if not matchval(val, baseval) then
        fail("MATCH: " .. table.concat(path, ".") .. ": [" .. stringify(val) .. "] <=> [" .. stringify(baseval) .. "]")
      end
    end
  end)
end

local function runner(name, store, testfile, provider)
  local client = provider.test()
  local utility = client.utility()
  local clone, getpath, inject, items, stringify, walk =
      utility.struct.clone, utility.struct.getpath, utility.struct.inject,
      utility.struct.items, utility.struct.stringify, utility.struct.walk

  local alltests = json.decode(readFileSync(join(lfs.currentdir(), testfile)))

  -- TODO: a more coherent namespace perhaps?
  local spec = (alltests.primary and alltests.primary[name]) or alltests[name] or alltests

  local clients = {}
  if spec.DEF then
    for _, cdef in ipairs(items(spec.DEF.client)) do
      local copts = cdef[2].test.options or {}
      if type(store) == "table" then
        inject(copts, store)
      end
      clients[cdef[1]] = provider.test(copts)
    end
  end

  local subject = utility[name]

  local function runset(testspec, testsubject, makesubject)
    testsubject = testsubject or subject

    for _, entry in ipairs(testspec.set) do
      local success, err = pcall(function()
        local testclient = client

        if entry.client then
          testclient = clients[entry.client]
          testsubject = client.utility()[name]
        end

        if makesubject then
          testsubject = makesubject(testsubject)
        end

        local args = { clone(entry["in"]) }

        if entry.ctx then
          args = { entry.ctx }
        elseif entry.args then
          args = entry.args
        end

        if entry.ctx or entry.args then
          local first = args[1]
          if type(first) == "table" and first ~= nil then
            entry.ctx = first
            args[1] = clone(first)
            first.client = testclient
            first.utility = testclient.utility()
          end
        end

        local res = testsubject(table.unpack(args))
        entry.res = res

        if entry.match == nil or entry.out ~= nil then
          -- NOTE: don't use clone as we want to strip functions
          deepEqual(res ~= nil and json.decode(json.encode(res)) or res, entry.out)
        end

        if entry.match then
          match(entry.match, { ["in"] = entry["in"], out = entry.res, ctx = entry.ctx }, walk, getpath, stringify)
        end
      end)

      if not success then
        entry.thrown = err
        local entry_err = entry.err

        if entry_err ~= nil then
          if entry_err == true or matchval(entry_err, err) then
            if entry.match then
              match(entry.match, { ["in"] = entry["in"], out = entry.res, ctx = entry.ctx, err = err }, walk, getpath,
                stringify)
            end
          else
            fail("ERROR MATCH: [" .. stringify(entry_err) .. "] <=> [" .. err .. "]")
          end
        else
          fail(err)
        end
      end
    end
  end

  return {
    spec = spec,
    runset = runset,
    subject = subject
  }
end

return runner
